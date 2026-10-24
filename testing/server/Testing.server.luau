-- A place to try ClientCast in: a spinning bar the server casts, a few dummies, and a sword for every player that
-- their own client casts.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local ClientCast = require(ReplicatedStorage.ClientCast)
ReplicatedStorage.ClientCast:SetAttribute("Debug", true)

local Swing = Instance.new("RemoteEvent")
Swing.Name = "Swing"
Swing.Parent = ReplicatedStorage

local function Block(Name, Size, At, Parent)
	local Part = Instance.new("Part")
	Part.Name = Name
	Part.Size = Size
	Part.CFrame = At
	Part.Anchored = true
	Part.Parent = Parent
	return Part
end

for Index = 1, 3 do
	local Dummy = Instance.new("Model")
	Dummy.Name = `Dummy {Index}`
	local Torso = Block("Torso", Vector3.new(2, 2, 1), CFrame.new(Index * 6 - 12, 3, -12), Dummy)
	Block("Head", Vector3.new(1, 1, 1), Torso.CFrame + Vector3.new(0, 1.5, 0), Dummy)
	Instance.new("Humanoid").Parent = Dummy
	Dummy.Parent = workspace
end

-- The server casts this one itself: it has no owner. A fresh activation every second lets it hit someone again.
local Bar = Block("Spinner", Vector3.new(14, 0.4, 0.4), CFrame.new(0, 2, 10), workspace)
Bar.CanCollide = false
Bar.Color = Color3.fromRGB(255, 90, 90)
for X = -7, 7, 1.75 do
	local Point = Instance.new("Attachment")
	Point.Name = "DmgPoint"
	Point.Position = Vector3.new(X, 0, 0)
	Point.Parent = Bar
end
local Spinner = ClientCast.new(Bar)
Spinner.Hit:Connect(function(Hit)
	if Hit.Humanoid then
		Hit.Humanoid:TakeDamage(15)
	end
end)
RunService.PreSimulation:Connect(function()
	Bar.CFrame = CFrame.new(0, 2, 10) * CFrame.Angles(0, os.clock() * 2, 0)
end)
task.spawn(function()
	while true do
		Spinner:Start()
		task.wait(1)
	end
end)

-- Every player gets a sword. Its owner's client casts it and decides when it swings; the server only allows each
-- swing and takes the hits.
local Cooldowns = {}
local function Arm(Player, Character)
	local Hand = Character:WaitForChild("RightHand", 2) or Character:FindFirstChild("Right Arm")
	if not Hand then
		return
	end
	local Sword = Instance.new("Part")
	Sword.Name = "Sword"
	Sword.Size = Vector3.new(0.3, 0.3, 4)
	Sword.CanCollide = false
	Sword.Massless = true
	for Z = -2, 2 do
		local Point = Instance.new("Attachment")
		Point.Name = "DmgPoint"
		Point.Position = Vector3.new(0, 0, Z)
		Point.Parent = Sword
	end
	local Grip = Instance.new("Motor6D")
	Grip.Name = "Grip"
	Grip.Part0 = Hand
	Grip.Part1 = Sword
	Grip.C0 = CFrame.new(0, -Hand.Size.Y / 2, -2)
	Grip.Parent = Sword
	Sword.Parent = Character

	local Caster = ClientCast.new(Sword, { Owner = Player })
	Caster.Hit:Connect(function(Hit)
		if Hit.Humanoid then
			print(`{Player.Name} hit {Hit.Humanoid.Parent.Name} with {Hit.Point}`)
			Hit.Humanoid:TakeDamage(20)
		end
	end)
	-- the caster goes away with the sword when the character does
end

Swing.OnServerEvent:Connect(function(Player)
	local Character = Player.Character
	local Sword = Character and Character:FindFirstChild("Sword")
	local Caster = Sword and ClientCast.Get(Sword)
	if not Caster or os.clock() - (Cooldowns[Player] or 0) < 0.5 then
		return
	end
	Cooldowns[Player] = os.clock()
	Caster:Start()
	task.wait(0.5)
	Caster:Stop()
end)

local function Join(Player)
	Player.CharacterAdded:Connect(function(Character)
		Arm(Player, Character)
	end)
	if Player.Character then
		Arm(Player, Player.Character)
	end
end
Players.PlayerAdded:Connect(Join)
for _, Player in Players:GetPlayers() do
	Join(Player)
end
Players.PlayerRemoving:Connect(function(Player)
	Cooldowns[Player] = nil
end)
