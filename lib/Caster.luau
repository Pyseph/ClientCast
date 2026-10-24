--!strict
--[[
	A caster fires Hit the first time it touches each target during an activation, from a Start to its Stop. How it
	casts is in Sweep.luau; this is its lifecycle, and how a server caster and its owner's client talk.

	A caster has one of three roles:
	- local: it casts on this machine. Every caster without an Owner is one.
	- proxy: a server caster with an Owner. The owner's client casts it and the proxy takes the hits it reports.
	- mirror: the owner's copy of a proxy. It casts like a local caster and reports its hits to the server.

	The server and the owner talk over one RemoteEvent:
	- server to owner: Create(Object, State), Start(Object), Stop(), Destroy()
	- owner to server: Begin(), Hit(Part, Position, Normal, Material, Point), Done()
	Each server Start lets the owner begin one activation, and the proxy takes its hits until the owner says Done,
	even after the server's Stop, so players with high ping still land theirs. An owner that starts or stops its mirror
	itself decides when it casts, and the server's Start and Stop then only decide which hits count.
]]
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Filter = require(script.Parent.Filter)
local Signal = require(script.Parent.Signal)
local Sweep = require(script.Parent.Sweep)
local Visualizer = require(script.Parent.Visualizer)

local LateHits = 2 -- seconds a proxy still takes hits after Stop, unless the owner says Done first

export type Hit = {
	Instance: BasePart, -- the part (or Terrain) that was hit
	Position: Vector3,
	Normal: Vector3,
	Material: Enum.Material,
	Humanoid: Humanoid?, -- the humanoid of the model the part belongs to
	Point: Attachment?, -- the point whose sweep hit, or nil when a part swept its own shape
}

export type Options = {
	Owner: Player?, -- the player whose client casts this and reports the hits (server only)
	Points: string?, -- name or tag of the attachments and bones to cast from; "DmgPoint" by default
	Params: RaycastParams?, -- what the casts can hit; the object and whoever holds it are always left out
	Radius: number?, -- sweep spheres this wide instead of rays; a point's Radius attribute overrides it
	Debug: boolean?, -- draw this caster's casts
}

-- What a mirror gets from its proxy
type State = { Points: string, Radius: number, Debug: boolean, Filter: Filter.Filter }

local Caster = {}
Caster.__index = Caster
Caster.Remote = nil :: any -- the RemoteEvent, set by ClientCast (tests hand it a stand-in)
Caster.OwnerError = nil :: string? -- why this machine can't give casters an Owner, if it can't

export type Caster = typeof(setmetatable(
	{} :: {
		Id: number,
		Hit: Signal.Signal<Hit>,
		Object: Instance?,
		Owner: Player?,
		Active: boolean,
		Points: string,
		Radius: number,
		Debug: boolean,
		_Filter: Filter.Filter,
		_Targets: { [Instance]: true }, -- what this activation has hit, by humanoid model or part
		_Destroyed: boolean,
		_Destroying: RBXScriptConnection?,
		_Mirror: boolean,
		_Driven: boolean, -- the owner started or stopped its mirror itself
		_Grants: number, -- server Starts the owner hasn't begun yet
		_Begun: boolean, -- the owner is in an activation
		_Open: boolean, -- and it's one the server allowed
		_Until: number, -- after Stop, when the proxy stops taking hits
	},
	Caster
))

local Casters: { [Caster]: true } = {} -- every caster on this machine
local Running: { [Caster]: () -> () } = {} -- the ones casting here, and their sweeps
local Proxies: { [number]: Caster } = {}
local Mirrors: { [number]: Caster } = {}
local LastId = 0
Caster.Proxies, Caster.Mirrors = Proxies, Mirrors -- by id, for tests and debugging

function Caster.new(Object: Instance?, Options: Options?): Caster
	local Settings: Options = Options or {}
	LastId += 1
	local self = setmetatable({
		Id = LastId,
		Hit = Signal.new(),
		Object = Object,
		Owner = nil,
		Active = false,
		Points = Settings.Points or "DmgPoint",
		Radius = Settings.Radius or 0,
		Debug = Settings.Debug == true,
		_Filter = Filter.From(Settings.Params),
		_Targets = {},
		_Destroyed = false,
		_Destroying = nil,
		_Mirror = false,
		_Driven = false,
		_Grants = 0,
		_Begun = false,
		_Open = false,
		_Until = 0,
	}, Caster)
	Casters[self] = true
	self:_Watch()
	if Settings.Owner then
		self:SetOwner(Settings.Owner)
	end
	return self
end

-- Starts an activation: Hit fires for each new target touched until Stop. Starting again starts a fresh one.
function Caster.Start(self: Caster)
	if self._Destroyed then
		return
	elseif self.Owner then
		self.Active = true
		self._Grants = math.min(self._Grants + 1, 3)
		if self._Begun and not self._Open then
			self:_Allow() -- the owner began before this Start reached the server
		end
		self:_Send("Start", self.Object)
	else
		self._Driven = self._Mirror
		self:_Begin()
	end
end

function Caster.Stop(self: Caster)
	if self.Owner then
		if self.Active then
			self.Active = false
			self._Until = os.clock() + LateHits
			self:_Send("Stop")
		end
	else
		self._Driven = self._Mirror
		self:_End()
	end
end

-- Casters also go away with their object
function Caster.Destroy(self: Caster)
	if self._Destroyed then
		return
	end
	self:Stop()
	if self.Owner then
		self:_Send("Destroy")
		Proxies[self.Id] = nil
	elseif self._Mirror then
		Mirrors[self.Id] = nil
	end
	self._Destroyed = true
	Casters[self] = nil
	if self._Destroying then
		self._Destroying:Disconnect()
	end
	self.Hit:DisconnectAll()
end

-- Hands the caster to a player's client, or back to this machine with nil (server only)
function Caster.SetOwner(self: Caster, Owner: Player?)
	if Owner and Caster.OwnerError then
		error(`ClientCast: {Caster.OwnerError}`, 2)
	elseif Owner == self.Owner or self._Destroyed then
		return
	end
	local Active = self.Active
	self:Stop()
	if self.Owner then
		self:_Send("Destroy")
		Proxies[self.Id] = nil
	end
	self.Owner = Owner
	if Owner then
		Proxies[self.Id] = self
		self._Grants, self._Begun, self._Open = 0, false, false
		self:_Sync()
	end
	if Active then
		self:Start()
	end
end

function Caster.SetObject(self: Caster, Object: Instance?)
	self.Object = Object
	self:_Watch()
	self:_Changed()
end

function Caster.SetParams(self: Caster, Params: RaycastParams?)
	self._Filter = Filter.From(Params)
	self:_Changed()
end

function Caster.SetDebug(self: Caster, Debug: boolean)
	self.Debug = Debug
	if self.Owner then
		self:_Sync()
	end
end

-- After a setting changes, the owner gets the new state and a caster casting here picks it up
function Caster._Changed(self: Caster)
	if self.Owner then
		self:_Sync()
	elseif self.Active then
		Running[self] = Sweep.new(self)
	end
end

function Caster._Watch(self: Caster)
	if self._Destroying then
		self._Destroying:Disconnect()
	end
	local Object = self.Object
	self._Destroying = if Object
		then Object.Destroying:Connect(function()
			self:Destroy()
		end)
		else nil
end

function Caster._Send(self: Caster, Action: string, ...: any)
	local Owner = self.Owner :: Player
	if Owner.Parent then
		Caster.Remote:FireClient(Owner, self.Id, Action, ...)
	end
end

function Caster._Sync(self: Caster)
	local State: State = { Points = self.Points, Radius = self.Radius, Debug = self.Debug, Filter = self._Filter }
	self:_Send("Create", self.Object, State)
end

function Caster._Begin(self: Caster)
	self:_End()
	self.Active = true
	Running[self] = Sweep.new(self)
	if self._Mirror then
		Caster.Remote:FireServer(self.Id, "Begin")
	end
end

function Caster._End(self: Caster)
	if self.Active then
		self.Active = false
		Running[self] = nil
		table.clear(self._Targets)
		if self._Mirror then
			Caster.Remote:FireServer(self.Id, "Done")
		end
	end
end

-- Counts a touched part once per target, then hands it to the server (from a mirror) and to Hit. Returns a newly hit
-- humanoid's model when the caster casts here, for its sweeps to go through.
function Caster._Register(
	self: Caster,
	Part: BasePart,
	Position: Vector3,
	Normal: Vector3,
	Material: Enum.Material,
	Point: Attachment?
): Model?
	if self._Targets[Part] then
		return nil -- a wall it keeps sweeping along
	end
	local Humanoid, Model = Sweep.Resolve(Part)
	local Target = Model or Part
	if self._Targets[Target] then
		return nil
	end
	self._Targets[Target] = true
	if self._Mirror then
		Caster.Remote:FireServer(self.Id, "Hit", Part, Position, Normal, Material, Point)
	end
	if self.Debug or Visualizer.Enabled then
		Visualizer.Mark(Position, Normal, Target.Name)
	end
	self.Hit:Fire({
		Instance = Part,
		Position = Position,
		Normal = Normal,
		Material = Material,
		Humanoid = Humanoid,
		Point = Point,
	})
	return if Running[self] then Model else nil
end

-- The owner's activation counts: a fresh one for each server Start
function Caster._Allow(self: Caster)
	self._Grants -= 1
	self._Open = true
	table.clear(self._Targets)
end

local function IsVector(Value: any): boolean
	return typeof(Value) == "Vector3" and Value == Value and Value.Magnitude < math.huge -- no NaN or infinity
end

-- Whether what an owner reported could be a hit of this caster's
local function IsHit(self: Caster, Part: any, Position: any, Normal: any, Material: any, Point: any): boolean
	if not (typeof(Part) == "Instance" and Part:IsA("BasePart") and Part:IsDescendantOf(Workspace)) then
		return false
	elseif not (IsVector(Position) and IsVector(Normal)) then
		return false
	elseif not (typeof(Material) == "EnumItem" and Material.EnumType == Enum.Material) then
		return false
	end
	local Object = self.Object
	return Point == nil
		or typeof(Point) == "Instance"
			and Point:IsA("Attachment")
			and Object ~= nil
			and Point:IsDescendantOf(Object)
end

-- A message from a proxy's owner (server)
function Caster.FromOwner(Player: Player, Id: any, Action: any, ...: any)
	local self = Proxies[Id]
	if not self or self.Owner ~= Player then
		return
	end
	local Taking = self.Active or os.clock() < self._Until
	if Action == "Begin" then
		self._Begun, self._Open = true, false
		if Taking and self._Grants > 0 then
			self:_Allow()
		end
	elseif Action == "Done" then
		self._Begun, self._Open = false, false
		table.clear(self._Targets)
	elseif Action == "Hit" and self._Open and Taking and IsHit(self, ...) then
		self:_Register(...)
	end
end

-- A message from the server to this player (client)
function Caster.FromServer(Id: any, Action: any, ...: any)
	local Mirror = Mirrors[Id]
	if Action == "Create" then
		local Object, State: State = ...
		local Copy = Mirror or Caster.new(nil)
		Mirrors[Id] = Copy
		Copy.Id, Copy._Mirror, Copy.Object = Id, true, Object
		Copy.Points, Copy.Radius, Copy.Debug, Copy._Filter = State.Points, State.Radius, State.Debug, State.Filter
		Copy:_Changed()
	elseif Mirror and Action == "Start" then
		Mirror.Object = (...) -- sent again, so an object that streamed in late is picked up
		if not Mirror._Driven then
			Mirror:_Begin()
		end
	elseif Mirror and Action == "Stop" then
		if not Mirror._Driven then
			Mirror:_End()
		end
	elseif Mirror and Action == "Destroy" then
		Mirror:Destroy()
	end
end

-- A caster on an object. On a client, this finds the mirrors of casters the server gave this player.
function Caster.Find(Object: Instance, Points: string?): Caster?
	for Candidate in Casters do
		if Candidate.Object == Object and (Points == nil or Candidate.Points == Points) then
			return Candidate
		end
	end
	return nil
end

RunService.PostSimulation:Connect(function()
	for _, Step in Running do
		Step()
	end
	Visualizer.Render()
end)

return Caster
