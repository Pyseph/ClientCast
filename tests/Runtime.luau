--!nocheck
--[[
	Runtime tests for ClientCast. They need a client, since they cast against parts they build there:
	- in Studio, require this from a LocalScript during a play test and call what it returns: `require(Path)({})`
	- with the roblox-engine-emulator: `ree run --harness tests/Runtime.luau --mount ReplicatedStorage/ClientCast=lib
	  --player Tester --seconds 40`
	A server caster and its owner's copy are wired together in one place, through a stand-in remote that delays every
	message by a set latency, so the tests can play the part of a laggy server. Each prints PASS or FAIL, then a total.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Library = ReplicatedStorage:WaitForChild("ClientCast")
local Caster = require(Library.Caster)
local Signal = require(Library.Signal)
local Filter = require(Library.Filter)
local Visualizer = require(Library.Visualizer)

local Player = Players.LocalPlayer
local Results = { Pass = 0, Fail = 0, Failed = {} }

local function Check(Name, Condition, Detail)
	if Condition then
		Results.Pass += 1
	else
		Results.Fail += 1
		table.insert(Results.Failed, Name)
	end
	print(`{if Condition then "PASS" else "FAIL"} {Name}{if Detail ~= nil then ` ({Detail})` else ""}`)
end

-- A remote whose messages arrive Latency seconds later, in order. Counts what the owner sends.
local Latency = 0
local Remote = { OnServerEvent = Signal.new(), OnClientEvent = Signal.new(), ToServer = 0 }
function Remote:FireServer(...)
	local Args = table.pack(...)
	self.ToServer += 1
	task.delay(Latency, function()
		self.OnServerEvent:Fire(Player, table.unpack(Args, 1, Args.n))
	end)
end
function Remote:FireClient(_, ...)
	local Args = table.pack(...)
	task.delay(Latency, function()
		self.OnClientEvent:Fire(table.unpack(Args, 1, Args.n))
	end)
end
Caster.Remote = Remote
Caster.OwnerError = nil -- these tests play the server too
Remote.OnServerEvent:Connect(Caster.FromOwner)
Remote.OnClientEvent:Connect(Caster.FromServer)

local World = Instance.new("Folder")
World.Name = "World"
World.Parent = workspace

local function Part(Name, Size, At, Parent)
	local New = Instance.new("Part")
	New.Name = Name
	New.Size = Size
	New.CFrame = At
	New.Anchored = true
	New.Parent = Parent or World
	return New
end

local function Dummy(Name, At)
	local Model = Instance.new("Model")
	Model.Name = Name
	Part("Torso", Vector3.new(2, 2, 1), CFrame.new(At), Model)
	Part("Head", Vector3.new(1, 1, 1), CFrame.new(At + Vector3.new(0, 1.5, 0)), Model)
	Instance.new("Humanoid").Parent = Model
	Model.Parent = World
	return Model
end

-- A thin blade along Z with points spread over it. CanQuery is off, so tests that aren't about the caster leaving
-- out its own object don't depend on that.
local function Blade(Count, Name)
	local New = Part("Blade", Vector3.new(0.2, 0.2, 4), CFrame.new(0, -50, 0))
	New.CanQuery = false
	New.CanCollide = false
	for Index = 1, Count do
		local Point = Instance.new("Attachment")
		Point.Name = Name or "DmgPoint"
		Point.Position = Vector3.new(0, 0, if Count == 1 then 0 else -2 + 4 * (Index - 1) / (Count - 1))
		Point.Parent = New
	end
	return New
end

-- Moves a part from one CFrame to another over Frames frames, each move before the casters step
local function Move(Target, From, To, Frames)
	local Frame = 0
	local Connection
	Connection = RunService.PreSimulation:Connect(function()
		Target.CFrame = From:Lerp(To, Frame / Frames)
		Frame += 1
	end)
	repeat
		task.wait()
	until Frame > Frames
	Connection:Disconnect()
	task.wait()
end

local function Collect(Subject)
	local Hits = {}
	Subject.Hit:Connect(function(Hit)
		table.insert(Hits, Hit)
	end)
	return Hits
end

local function Names(Hits)
	local Found = {}
	for _, Hit in Hits do
		Found[if Hit.Humanoid then Hit.Humanoid.Parent.Name else Hit.Instance.Name] = true
	end
	return Found
end

local Tests = {}

function Tests.SweepHitsOncePerTarget()
	local Target = Dummy("Target", Vector3.new(0, 0, 0))
	local Sword = Blade(5)
	local Subject = Caster.new(Sword)
	local Hits = Collect(Subject)
	Subject:Start()
	Move(Sword, CFrame.new(-6, 0.5, 0), CFrame.new(6, 0.5, 0), 12)
	Subject:Stop()
	task.wait()
	Check("one hit for one target", #Hits == 1, #Hits)
	local Hit = Hits[1]
	Check("the hit has the humanoid", Hit and Hit.Humanoid == Target.Humanoid)
	Check("the hit names its point", Hit and Hit.Point and Hit.Point.Parent == Sword)
	Check("the hit is on the target's surface", Hit and math.abs(Hit.Position.X + 1) < 0.01, Hit and Hit.Position)
	Check("the normal faces the swing", Hit and Hit.Normal.X < -0.9, Hit and Hit.Normal)
	Subject:Destroy()
end

function Tests.RestartCountsTargetsAgain()
	Dummy("Target", Vector3.new(0, 0, 0))
	local Sword = Blade(3)
	local Subject = Caster.new(Sword)
	local Hits = Collect(Subject)
	Subject:Start()
	Move(Sword, CFrame.new(-6, 0.5, 0), CFrame.new(6, 0.5, 0), 8)
	Subject:Start()
	Move(Sword, CFrame.new(6, 0.5, 0), CFrame.new(-6, 0.5, 0), 8)
	Subject:Stop()
	task.wait()
	Check("each activation hits the target once", #Hits == 2, #Hits)
end

function Tests.CleavesThroughACrowd()
	Dummy("Front", Vector3.new(0, 0, 0))
	Dummy("Back", Vector3.new(4, 0, 0))
	local Sword = Blade(5)
	local Subject = Caster.new(Sword)
	local Hits = Collect(Subject)
	Subject:Start()
	-- one frame sweeps from in front of both to past both
	Move(Sword, CFrame.new(-6, 0.5, 0), CFrame.new(10, 0.5, 0), 1)
	Subject:Stop()
	task.wait()
	local Found = Names(Hits)
	Check("a hit target doesn't shield the one behind it", Found.Front and Found.Back, #Hits)
end

function Tests.WallsBlock()
	Part("Wall", Vector3.new(0.5, 6, 6), CFrame.new(-2, 0, 0))
	Dummy("Behind", Vector3.new(1, 0, 0))
	local Sword = Blade(5)
	local Subject = Caster.new(Sword)
	local Hits = Collect(Subject)
	Subject:Start()
	-- one sweep from in front of the wall to past the target
	Move(Sword, CFrame.new(-6, 0.5, 0), CFrame.new(4, 0.5, 0), 1)
	Subject:Stop()
	task.wait()
	local Found = Names(Hits)
	Check("the wall blocks the sweep", #Hits == 1 and Found.Wall, #Hits)
	Check("a wall hit has no humanoid", Hits[1] and Hits[1].Humanoid == nil)
end

function Tests.LeavesOutItselfAndItsHolder()
	local Holder = Dummy("Holder", Vector3.new(0, 0, 0))
	local Sword = Blade(5)
	Sword.CanQuery = true
	Sword.Parent = Holder
	Dummy("Enemy", Vector3.new(6, 0, 0))
	local Subject = Caster.new(Sword)
	local Hits = Collect(Subject)
	Subject:Start()
	-- sweeps out of the holder's torso and into the enemy
	Move(Sword, CFrame.new(-6, 0.5, 0), CFrame.new(9, 0.5, 0), 6)
	Subject:Stop()
	task.wait()
	local Found = Names(Hits)
	Check("the holder isn't hit", not Found.Holder)
	Check("the sword doesn't hit itself", not Found.Blade)
	Check("the enemy past the holder is hit", Found.Enemy == true, #Hits)
end

function Tests.ParamsFilterTheCasts()
	local Ignored = Dummy("Ignored", Vector3.new(0, 0, 0))
	Dummy("Kept", Vector3.new(4, 0, 0))
	local Sword = Blade(3)
	local Params = RaycastParams.new()
	Params.FilterDescendantsInstances = { Ignored }
	local Subject = Caster.new(Sword, { Params = Params })
	local Hits = Collect(Subject)
	Subject:Start()
	Move(Sword, CFrame.new(-6, 0.5, 0), CFrame.new(10, 0.5, 0), 8)
	Subject:Stop()
	task.wait()
	local Found = Names(Hits)
	Check("a target the params leave out isn't hit", #Hits == 1 and Found.Kept, #Hits)
end

function Tests.StopInHandler()
	Dummy("A", Vector3.new(0, 0, -1.5))
	Dummy("B", Vector3.new(0, 0, 1.5))
	local Sword = Blade(6)
	local Subject = Caster.new(Sword)
	local Count = 0
	Subject.Hit:Connect(function()
		Count += 1
		Subject:Stop()
	end)
	Subject:Start()
	Move(Sword, CFrame.new(-6, 0.5, 0), CFrame.new(6, 0.5, 0), 1)
	task.wait()
	Check("stopping in Hit stops at the first target", Count == 1, Count)
end

function Tests.RadiusSweepsSpheres()
	Dummy("Target", Vector3.new(0, 0, 0))
	local function Run(Radius, Attribute)
		local Sword = Blade(1)
		if Attribute then
			Sword.DmgPoint:SetAttribute("Radius", Attribute)
		end
		local Subject = Caster.new(Sword, { Radius = Radius })
		local Hits = Collect(Subject)
		Subject:Start()
		-- passes 1.3 studs over the top of the head (y 2)
		Move(Sword, CFrame.new(-6, 3.3, 0), CFrame.new(6, 3.3, 0), 6)
		Subject:Destroy()
		Sword:Destroy()
		task.wait()
		return #Hits
	end
	Check("a ray passes over", Run(0) == 0)
	Check("a sphere 1.5 wide clips the head", Run(1.5) == 1)
	Check("a point's Radius attribute wins", Run(0, 1.5) == 1 and Run(1.5, 0.1) == 0)
end

function Tests.PartsSweepTheirShape()
	Dummy("Target", Vector3.new(0, 0, 0))
	for _, Shape in { Enum.PartType.Ball, Enum.PartType.Block, Enum.PartType.Cylinder } do
		local Projectile = Part("Projectile", Vector3.new(1, 1, 1), CFrame.new(-6, 0, 0))
		Projectile.Shape = Shape
		Projectile.CanQuery = false
		local Subject = Caster.new(Projectile)
		local Hits = Collect(Subject)
		Subject:Start()
		Move(Projectile, CFrame.new(-6, 0, 0), CFrame.new(6, 0, 0), 6)
		Subject:Stop()
		task.wait()
		Check(`a {Shape.Name} part with no points sweeps itself`, #Hits == 1 and Hits[1].Point == nil, #Hits)
		Projectile:Destroy()
	end
end

function Tests.BonesAndTags()
	Dummy("Target", Vector3.new(0, 0, 0))
	local Sword = Blade(0)
	local Bone = Instance.new("Bone")
	Bone.Name = "Tip"
	Bone:AddTag("DmgPoint")
	Bone.Parent = Sword
	local Subject = Caster.new(Sword)
	local Hits = Collect(Subject)
	Subject:Start()
	Move(Sword, CFrame.new(-6, 0.5, 0), CFrame.new(6, 0.5, 0), 6)
	Subject:Stop()
	task.wait()
	Check("a bone tagged DmgPoint casts", #Hits == 1 and Hits[1].Point == Bone, #Hits)
end

function Tests.PointsOption()
	Dummy("Target", Vector3.new(0, 0, 0))
	-- the Left points pass beside the target, the Right one through it
	local Sword = Blade(2, "Left")
	local Other = Instance.new("Attachment")
	Other.Name = "Right"
	Other.Parent = Sword
	local function Run(Points)
		local Subject = Caster.new(Sword, { Points = Points })
		local Hits = Collect(Subject)
		Subject:Start()
		Move(Sword, CFrame.new(-6, 0.5, 0), CFrame.new(6, 0.5, 0), 6)
		Subject:Stop()
		task.wait()
		Check(`Points = {Points} casts only from those`, #Hits == (if Points == "Right" then 1 else 0), #Hits)
		return Subject
	end
	local Left, Right = Run("Left"), Run("Right")
	Check(
		"Find tells casters apart by points",
		Caster.Find(Sword, "Left") == Left and Caster.Find(Sword, "Right") == Right
	)
end

function Tests.TeleportsDontSweep()
	Dummy("Target", Vector3.new(0, 0, 0))
	local Sword = Blade(2)
	local Subject = Caster.new(Sword)
	local Hits = Collect(Subject)
	Subject:Start()
	Move(Sword, CFrame.new(-300, 0.5, 0), CFrame.new(300, 0.5, 0), 1)
	Subject:Stop()
	task.wait()
	Check("a 600 stud jump isn't swept", #Hits == 0, #Hits)
end

function Tests.GoesAwayWithItsObject()
	local Sword = Blade(2)
	local Subject = Caster.new(Sword)
	Subject.Hit:Connect(function() end)
	Subject:Start()
	Sword:Destroy()
	task.wait()
	Check("destroying the object destroys the caster", Subject._Destroyed and not Subject.Active)
	Check("it isn't found any more", Caster.Find(Sword) == nil)
	Check("its Hit is disconnected", #Subject.Hit._Handlers == 0)
end

function Tests.WarnsWithoutPoints()
	local Model = Instance.new("Model")
	Model.Parent = World
	local Subject = Caster.new(Model)
	local Ok = pcall(function()
		Subject:Start()
		task.wait()
		Subject:Start()
		task.wait()
	end)
	Check("a model without points is harmless (and warns once, below)", Ok and Subject.Active)
	Subject:Destroy()
end

function Tests.FilterCopies()
	local A, B = Instance.new("Folder"), Instance.new("Folder")
	local Legacy = RaycastParams.new()
	Legacy.FilterType = Enum.RaycastFilterType.Include
	Legacy.FilterDescendantsInstances = { A }
	Legacy.IgnoreWater = true
	Legacy.CollisionGroup = "Weapons"
	local Copy = Filter.From(Legacy)
	Check("a legacy include list becomes Include", Copy.Include and Copy.Include[1] == A and #Copy.Exclude == 0)
	Check("plain fields are copied", Copy.IgnoreWater == true and Copy.CollisionGroup == "Weapons")
	local Built = Filter.Build(Copy, { B })
	Check("built params carry both lists", Built.IncludeInstances[1] == A and Built.ExcludeInstances[1] == B)
	Check("built params carry the fields", Built.IgnoreWater == true and Built.CollisionGroup == "Weapons")
	local Excluding = RaycastParams.new()
	Excluding.FilterDescendantsInstances = { A }
	Excluding.ExcludeInstances = { B }
	local Joined = Filter.From(Excluding)
	Check("legacy and new exclude lists are joined", #Joined.Exclude == 2 and Joined.Include == nil)
end

function Tests.Debugging()
	Dummy("Target", Vector3.new(0, 0, 0))
	local Sword = Blade(3)
	local Subject = Caster.new(Sword, { Debug = true, Radius = 0.5 })
	Subject:Start()
	local Ok, Problem = pcall(Move, Sword, CFrame.new(-6, 0.5, 0), CFrame.new(6, 0.5, 0), 6)
	Subject:Stop()
	local Ball = Part("Ball", Vector3.one, CFrame.new(0, 10, 0))
	local Shape = Caster.new(Ball, { Debug = true })
	Shape:Start()
	local BoxOk, BoxProblem = pcall(Move, Ball, CFrame.new(0, 10, 0), CFrame.new(0, 12, 0), 3)
	task.wait()
	local Canvases = 0
	for _, Child in workspace.Terrain:GetChildren() do
		if Child.Name == "ClientCastDebug" and Child:IsA("WireframeHandleAdornment") then
			Canvases += 1
		end
	end
	Check("drawing sweeps doesn't error", Ok, Problem)
	Check("drawing shapes doesn't error", BoxOk, BoxProblem)
	Check("one set of 8 canvases under Terrain", Canvases == 8, Canvases)
	Shape:Destroy()
end

-- The server's caster with an Owner, and the owner's mirror of it
local function Owned(Sword)
	local Proxy = Caster.new(Sword, { Owner = Player })
	task.wait(Latency + 0.05)
	return Proxy, Caster.Mirrors[Proxy.Id]
end

function Tests.MirrorsFollowTheServer()
	Latency = 0.1
	local Sword = Blade(2)
	local Params = RaycastParams.new()
	Params.CollisionGroup = "Swords"
	local Proxy, Mirror = Owned(Sword)
	Check("the owner gets a mirror", Mirror ~= nil and Mirror._Mirror and Mirror.Object == Sword)
	Proxy:SetParams(Params)
	Proxy:SetDebug(true)
	task.wait(Latency + 0.05)
	Check("settings reach the mirror", Mirror._Filter.CollisionGroup == "Swords" and Mirror.Debug)
	Proxy:Start()
	task.wait(Latency + 0.05)
	Check("Start reaches the mirror", Mirror.Active)
	Proxy:Stop()
	task.wait(Latency + 0.05)
	Check("Stop reaches the mirror", not Mirror.Active)
	Proxy:SetOwner(nil)
	task.wait(Latency + 0.05)
	Check("taking the owner away removes the mirror", Caster.Mirrors[Proxy.Id] == nil and Mirror._Destroyed)
	Check("the caster now casts here", Proxy.Owner == nil and Caster.Proxies[Proxy.Id] == nil)
	Proxy:Destroy()
end

function Tests.LateHitsCount()
	Latency = 0.15
	Dummy("Target", Vector3.new(0, 0, 0))
	local Sword = Blade(5)
	local Proxy, Mirror = Owned(Sword)
	local ServerHits, OwnerHits = Collect(Proxy), Collect(Mirror)
	Proxy:Start()
	task.wait(0.2)
	-- the server stops before the owner's hit can reach it
	task.delay(0.05, function()
		Proxy:Stop()
	end)
	Move(Sword, CFrame.new(-6, 0.5, 0), CFrame.new(6, 0.5, 0), 6)
	task.wait(0.5)
	Check("the owner sees its hit at once", #OwnerHits == 1, #OwnerHits)
	Check("a hit arriving after the server's Stop still counts", #ServerHits == 1, #ServerHits)
	Check("the server resolves the humanoid itself", ServerHits[1] and ServerHits[1].Humanoid ~= nil)
	Check("the owner said Done, so nothing more is taken", not Proxy._Open)
	Proxy:Destroy()
	task.wait(0.4)
end

function Tests.CombosAtHighPing()
	Latency = 0.25
	Dummy("Target", Vector3.new(0, 0, 0))
	local Sword = Blade(5)
	local Proxy = Owned(Sword)
	local ServerHits = Collect(Proxy)
	-- two swings, each shorter than the 500 ms round trip
	local Started = os.clock()
	Proxy:Start()
	task.delay(0.2, function()
		Proxy:Stop()
	end)
	task.delay(0.25, function()
		Proxy:Start()
	end)
	task.delay(0.45, function()
		Proxy:Stop()
	end)
	task.wait(0.27 - (os.clock() - Started))
	Move(Sword, CFrame.new(-6, 0.5, 0), CFrame.new(6, 0.5, 0), 6)
	task.wait(0.53 - (os.clock() - Started))
	Move(Sword, CFrame.new(6, 0.5, 0), CFrame.new(-6, 0.5, 0), 6)
	task.wait(1)
	Check("both swings of a combo count", #ServerHits == 2, #ServerHits)
	Proxy:Destroy()
	task.wait(0.6)
end

function Tests.OwnerDecidesTheTiming()
	Latency = 0.1
	Dummy("Target", Vector3.new(0, 0, 0))
	local Sword = Blade(5)
	local Proxy, Mirror = Owned(Sword)
	local ServerHits = Collect(Proxy)
	for _, Order in { "attack first", "begin first" } do
		-- the owner starts its swing right away and tells the server, which starts the caster when it gets that
		task.delay(if Order == "attack first" then Latency else Latency + 0.05, function()
			Proxy:Start()
		end)
		Mirror:Start()
		Move(Sword, CFrame.new(-6, 0.5, 0), CFrame.new(-4, 0.5, 0), 3)
		task.wait(0.1)
		Move(Sword, CFrame.new(-4, 0.5, 0), CFrame.new(6, 0.5, 0), 4)
		Mirror:Stop()
		task.wait(Latency + 0.1)
		Proxy:Stop()
		task.wait(Latency + 0.1)
	end
	Check("the owner's own swings count, whichever reaches the server first", #ServerHits == 2, #ServerHits)
	Check(
		"after that the server's Start doesn't start the mirror",
		(function()
			Proxy:Start()
			task.wait(Latency + 0.1)
			local Ignored = not Mirror.Active
			Proxy:Stop()
			task.wait(Latency + 0.1)
			return Ignored
		end)()
	)
	-- a swing the server never allowed, once the last Start's window has closed
	task.wait(2.1)
	Mirror:Start()
	Move(Sword, CFrame.new(-6, 0.5, 0), CFrame.new(6, 0.5, 0), 6)
	Mirror:Stop()
	task.wait(Latency + 0.1)
	Check("a swing the server didn't start doesn't count", #ServerHits == 2, #ServerHits)
	Proxy:Destroy()
	task.wait(0.3)
end

function Tests.RejectsBadReports()
	Latency = 0
	local Target = Dummy("Target", Vector3.new(0, 0, 0))
	local Elsewhere = Instance.new("Part")
	local Sword = Blade(1)
	local Proxy = Owned(Sword)
	local ServerHits = Collect(Proxy)
	-- no real owner here: these reports stand in for what a client (or an exploiter) sends
	Caster.Mirrors[Proxy.Id]:Destroy()
	Caster.Mirrors[Proxy.Id] = nil
	local Torso = Target.Torso
	local Good = { Torso, Vector3.new(-1, 0, 0), Vector3.new(-1, 0, 0), Enum.Material.Plastic, Sword.DmgPoint }
	local function Report(...)
		Caster.FromOwner(Player, Proxy.Id, "Hit", ...)
	end
	Report(table.unpack(Good))
	Check("hits before the owner begins are ignored", #ServerHits == 0)
	Proxy:Start()
	Caster.FromOwner(Player, Proxy.Id, "Begin")
	local Stranger = Instance.new("Folder")
	Caster.FromOwner(Stranger, Proxy.Id, "Hit", table.unpack(Good))
	Report(Torso, Vector3.new(0 / 0, 0, 0), Vector3.xAxis, Enum.Material.Plastic)
	Report(Torso, Vector3.new(math.huge, 0, 0), Vector3.xAxis, Enum.Material.Plastic)
	Report(Elsewhere, Vector3.zero, Vector3.xAxis, Enum.Material.Plastic)
	Report(Torso, Vector3.zero, Vector3.xAxis, Enum.Material.Plastic, Instance.new("Attachment"))
	Report(Torso, Vector3.zero, Vector3.xAxis, Enum.KeyCode.A)
	Report("Torso", Vector3.zero, Vector3.xAxis, Enum.Material.Plastic)
	local Survived = pcall(function()
		Caster.FromOwner(Player, 0 / 0, "Hit")
		Caster.FromOwner(Player, {}, {})
		Caster.FromOwner(Player, Proxy.Id, nil)
		Caster.FromServer(12345, "Start")
	end)
	task.wait()
	Check(
		"wrong players, NaN, infinity, outside parts, foreign points and bad types are ignored",
		#ServerHits == 0,
		#ServerHits
	)
	Check("junk messages don't error", Survived)
	Report(table.unpack(Good))
	Report(Target.Head, Vector3.zero, Vector3.xAxis, Enum.Material.Plastic)
	task.wait()
	Check("a good report counts once per target", #ServerHits == 1, #ServerHits)
	Caster.FromOwner(Player, Proxy.Id, "Done")
	Report(Target.Head, Vector3.zero, Vector3.xAxis, Enum.Material.Plastic)
	task.wait()
	Check("hits after Done are ignored", #ServerHits == 1, #ServerHits)
	local Id = Proxy.Id
	Proxy:Destroy()
	local Late = pcall(Caster.FromOwner, Player, Id, "Hit", table.unpack(Good))
	Check("reports for a destroyed caster are dropped quietly", Late)
end

-- What the owner sends for one activation: a Begin, one Hit per target and a Done, however long it casts
function Tests.Traffic()
	Latency = 0
	local Holder = Dummy("Holder", Vector3.new(-3, 0, 0))
	Dummy("Target", Vector3.new(3, 0, 0))
	local Sword = Blade(10)
	Sword.Parent = Holder
	local Proxy = Owned(Sword)
	local Before = Remote.ToServer
	Proxy:Start()
	task.wait()
	-- four sweeps back and forth through the holder and the target
	for Sweep = 1, 4 do
		local A, B = CFrame.new(-6, 0, 0), CFrame.new(6, 0, 0)
		if Sweep % 2 == 0 then
			A, B = B, A
		end
		Move(Sword, A, B, 15)
	end
	Proxy:Stop()
	task.wait(0.1)
	local Sent = Remote.ToServer - Before
	Check("the owner sends one Begin, one hit and one Done", Sent == 3, Sent)
	Proxy:Destroy()
end

local Order = {
	"SweepHitsOncePerTarget",
	"RestartCountsTargetsAgain",
	"CleavesThroughACrowd",
	"WallsBlock",
	"LeavesOutItselfAndItsHolder",
	"ParamsFilterTheCasts",
	"StopInHandler",
	"RadiusSweepsSpheres",
	"PartsSweepTheirShape",
	"BonesAndTags",
	"PointsOption",
	"TeleportsDontSweep",
	"GoesAwayWithItsObject",
	"WarnsWithoutPoints",
	"FilterCopies",
	"Debugging",
	"MirrorsFollowTheServer",
	"LateHitsCount",
	"CombosAtHighPing",
	"OwnerDecidesTheTiming",
	"RejectsBadReports",
	"Traffic",
}

return function(Context)
	local Only = Context.Only
	for _, Name in Order do
		if Only == nil or Only == Name then
			print(`-- {Name}`)
			local Ok, Problem = pcall(Tests[Name])
			if not Ok then
				Check(`{Name} ran`, false, Problem)
			end
			World:ClearAllChildren()
			Latency = 0
			task.wait(0.1)
		end
	end
	print(
		`RESULT {Results.Pass} passed, {Results.Fail} failed{if Results.Fail > 0
			then ": " .. table.concat(Results.Failed, ", ")
			else ""}`
	)
end
