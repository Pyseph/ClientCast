--[=[
	@class ClientCast

	The constructor class for ClientCaster objects.
]=]
local ClientCast = {}
--[=[
	@interface Settings
	@within ClientCast

	.AttachmentName string
	.DebugAttachmentName string
	.FunctionDebug boolean
	.DebugMode boolean
	.DebugColor Color3
	.DebugLifetime number
	.AutoSetup boolean

	The settings which ClientCast relies on for module behavior.
]=]
--- @prop Settings Settings
--- @within ClientCast
local Settings = {
	AttachmentName = "DmgPoint", -- The name of the attachment that this network will raycast from
	DebugAttachmentName = "ClientCast-Debug", -- The name of the debug trail attachment

	FunctionDebug = false,
	DebugMode = false, -- DebugMode visualizes the rays, from last to current position
	DebugColor = Color3.new(1, 0, 0), -- The color of the visualized ray
	DebugLifetime = 1, -- Lifetime of the visualized trail
	AutoSetup = true, -- Automatically creates a LocalScript and a RemoteEvent to establish a connection to the server, from the client.
}

if Settings.AutoSetup then
	require(script.ClientConnection)()
end

ClientCast.Settings = Settings
ClientCast.InitiatedCasters = {}

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

if RunService:IsClient() then
	error("ClientCast can only be called from the server. Client communication is already handled by the module!")
end

local ReplicationRemote = ReplicatedStorage:FindFirstChild("ClientCast-Replication")
local PingRemote = ReplicatedStorage:FindFirstChild("ClientCast-Ping")

--[=[
	@class Signal
	A Lua-implementation of RBXScriptSignals, with near-identical behavior.
]=]

--- @method Connect
--- @within Signal
--- @param Callback function
--- @return Connection
--- Connects a callback to the Signal, which will be called everytime the Signal is fired.

--[=[
	@class Connection
	The constructor class for ClientCaster objects.
]=]

--- @method Disconnect
--- @within Connection
--- Disonnects the Connection, with any :Fire calls no longer updating it.

--- @prop Connected boolean
--- @within Connection
--- @readonly
--- A boolean which determines whether the Connection is currently active.

local Signal = require(script.Signal)

local function SerializeParams(Params)
	return {
		FilterDescendantsInstances = Params.FilterDescendantsInstances,
		FilterType = Params.FilterType.Name,
		IgnoreWater = Params.IgnoreWater,
		CollisionGroup = Params.CollisionGroup,
	}
end
local function IsA(Object, Type)
	return typeof(Object) == Type
end
local function AssertType(Object, ExpectedType, Message)
	if not IsA(Object, ExpectedType) then
		error(string.format(Message, ExpectedType, typeof(Object)), 4)
	end
end
local function AssertClass(Object, ExpectedClass, Message)
	AssertType(Object, "Instance", Message)
	if not Object:IsA(ExpectedClass) then
		error(string.format(Message, ExpectedClass, Object.Class), 4)
	end
end
local function IsValidOwner(Value, Error)
	local IsInstance = IsA(Value, "Instance")
	if not IsInstance and Value ~= nil then
		error("Unable to cast value to Object", 4)
	elseif IsInstance and not Value:IsA("Player") then
		error(Error or "SetOwner only takes player or 'nil' instance as an argument.", 4)
	end
end
local function DeserializeRaycastResult(SerializedResult)
	if not IsA(SerializedResult, "table") then
		return false
	end

	local HitInstance, Position, Material, Normal = unpack(SerializedResult)
	local IsValid = (
			HitInstance ~= nil
			and (HitInstance:IsA("BasePart") or HitInstance:IsA("Terrain"))
		)
		and IsA(Position, "Vector3")
		and IsA(Material, "EnumItem")
		and IsA(Normal, "Vector3")

	if IsValid then
		return true, {
			Instance = HitInstance,
			Position = Position,
			Material = Material,
			Normal = Normal,
		}
	else
		return false
	end
end

local Replication = {}
local ReplicationBase = {}
ReplicationBase.__index = ReplicationBase

function ReplicationBase:Start()
	local Owner = self.Owner
	AssertClass(Owner, "Player")

	ReplicationRemote:FireClient(Owner, "Start", {
		Owner = Owner,
		Object = self.Object,
		Debug = self.Caster._Debug,
		RaycastParams = SerializeParams(self.RaycastParams),
		Id = self.Caster._UniqueId,
	})

	local LocalizedConnection
	LocalizedConnection = ReplicationRemote.OnServerEvent:Connect(function(Player, CasterId, Code, SerializedRaycastResult)
		if self.Caster.Disabled or self.Caster._UniqueId ~= CasterId then
			return
		end
		local IsValid, RaycastResult = DeserializeRaycastResult(SerializedRaycastResult)

		if Player == Owner and IsValid and (Code == "Any" or Code == "Humanoid") then
			local Humanoid
			if Code == "Humanoid" then
				local Model = RaycastResult.Instance:FindFirstAncestorOfClass("Model")
				Humanoid = Model and Model:FindFirstChildOfClass("Humanoid")
			end

			if Code == "Humanoid" and Humanoid == nil then
				return
			end

			for Event in next, self.Caster._CollidedEvents[Code] do
				Event:Fire(RaycastResult, Humanoid)
			end
		end
	end)

	self.Connection = LocalizedConnection
end
function ReplicationBase:Update(AdditionalData)
	local Data = {
		Owner = self.Owner,
		Object = self.Object,
		Debug = self.Caster._Debug,
		RaycastParams = SerializeParams(self.RaycastParams),
		Id = self.Caster._UniqueId,
	}
	ReplicationRemote:FireClient(self.Owner, "Update", Data, AdditionalData)
end
function ReplicationBase:Stop(Destroying)
	local Owner = self.Owner

	ReplicationRemote:FireClient(Owner, Destroying and "Destroy" or "Stop", {
		Owner = Owner,
		Object = self.Object,
		Id = self.Caster._UniqueId,
	})

	local ReplicationConnection = self.Connection

	if Destroying then
		table.clear(self)
		setmetatable(self, nil)

		if ReplicationConnection then
			ReplicationConnection:Disconnect()
		end
	elseif ReplicationConnection then
		task.delay(1, function()
			if self.Connection == ReplicationConnection then
				ReplicationConnection:Disconnect()
			end
		end)
	end
end
function ReplicationBase:Destroy()
	self:Stop(true)
end

function Replication.new(Player, Object, RaycastParameters, Caster)
	AssertClass(Player, "Player", "Unexpected owner in 'ReplicationBase.Stop' (%s expected, got %s)")
	assert(type(Caster) == "table" and Caster._Class == "Caster", "Unexpect argument #4 - Caster expected")

	return setmetatable({
		Owner = Player,
		Object = Object,
		RaycastParams = RaycastParameters,
		Caster = Caster,
	}, ReplicationBase)
end

--[=[
	@class ClientCaster

	An object which handles raycasting and client-communication.
]=]

--- @prop RaycastParams RaycastParams
--- @within ClientCaster
--- @readonly
--- Returns the ClientCaster's set RaycastParams.

--- @prop Debug boolean
--- @within ClientCaster
--- @readonly
--- Returns whether the ClientCaster object has debug mode enabled, visualizing the ClientCaster's rays.

--- @prop Recursive boolean
--- @within ClientCaster
--- @readonly
--- Determines whether the Caster object will search for Raycast points (DmgPoints) from the whole object's descendants, rather then the object's direct children.

--- @prop Object Instance
--- @within ClientCaster
--- @readonly
--- Returns the object that the ClientCaster is raycasting from.

--- @prop Owner Player?
--- @within ClientCaster
--- @readonly
--- Returns the current Player who is the owner of the caster, or nil in case of the server. The owner calculates intersections, and as such it's recommended to have the client calculate it to have less of a burden on the server.

--- @prop Disabled boolean
--- @within ClientCaster
--- @readonly
--- Returns whether the ClientCaster is disabled (not raycasting).

--- @prop Collided Signal<RaycastResult>
--- Fires whenever any object intersects any one of the ClientCaster's rays.
--- @within ClientCaster
--- @tag Events

--- @prop HumanoidCollided Signal<RaycastResult, Humanoid>
--- Fires whenever any of the ClientCaster's rays intersect with an object, whose ancestor Model has a Humanoid object.
--- @within ClientCaster
--- @tag Events

local ClientCaster = {}

local TrailTransparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0),
	NumberSequenceKeypoint.new(0.5, 0),
	NumberSequenceKeypoint.new(1, 1),
})
local AttachmentOffset = Vector3.new(0, 0, 0.1)

--[=[
	Disables the debug trails of the ClientCaster.
]=]
function ClientCaster:DisableDebug()
	local ReplicationConnection = self._ReplicationConnection

	if ReplicationConnection then
		ReplicationConnection:Update({
			Debug = false,
		})
	end

	self._Debug = false
	for Trail in next, self._DebugTrails do
		Trail.Enabled = false
	end
end
--[=[
	Starts the debug trails of the ClientCaster.
]=]
function ClientCaster:StartDebug()
	local ReplicationConnection = self._ReplicationConnection

	if ReplicationConnection then
		ReplicationConnection:Update({
			Debug = true,
		})
	end

	self._Debug = true
	for Trail in next, self._DebugTrails do
		Trail.Enabled = true
	end
end

local CollisionBaseName = {
	Collided = "Any",
	HumanoidCollided = "Humanoid",
}

--[=[
	Starts this ClientCaster object, beginning to raycast for the hit detection.
]=]
function ClientCaster:Start()
	self.Disabled = false

	local ReplicationConn = self._ReplicationConnection
	if ReplicationConn then
		ReplicationConn:Start()
	end

	ClientCast.InitiatedCasters[self] = {}
	if self._Debug then
		self:StartDebug()
	end
end
--[=[
	Destroys this ClientCaster object, cleaning up any remnant connections.
]=]
function ClientCaster:Destroy()
	local ReplicationConn = self._ReplicationConnection
	if ReplicationConn then
		self._ReplicationConnection = nil
		ReplicationConn:Destroy()
	end

	if self._DescendantConnection then
		self._DescendantConnection:Disconnect()
		self.__DescendantConnection = nil
	end
	for _, DebugAttachment in next, self._DebugTrails do
		DebugAttachment:Destroy()
	end
	for _, EventsHolder in next, self._CollidedEvents do
		for Event in next, EventsHolder do
			Event:DisconnectAll()
		end
	end

	ClientCast.InitiatedCasters[self] = nil

	self.RaycastParams = nil
	self.Object = nil
	self.Owner = nil
	self.Disabled = true

	for Prop, Val in next, self do
		if type(Val) == "function" then
			self[Prop] = function() end
		end
	end
end
--[=[
	Stops this ClientCaster object, stopping raycasts for hit detection.
]=]
function ClientCaster:Stop()
	local OldConn = self._ReplicationConnection
	if OldConn then
		OldConn:Stop()
	end

	ClientCast.InitiatedCasters[self] = nil
	self.Disabled = true

	local LocalizedState = self._Debug
	self:DisableDebug()
	self._Debug = LocalizedState
end
--[=[
	Sets the given Player as owner for this caster object. When NewOwner is nil, the server will be the owner instead of a Player.
	@param NewOwner Player
]=]
function ClientCaster:SetOwner(NewOwner)
	IsValidOwner(NewOwner)
	local OldConnection = self._ReplicationConnection
	local ReplicationConnection = NewOwner ~= nil and Replication.new(NewOwner, self.Object, self.RaycastParams, self)
	self._ReplicationConnection = ReplicationConnection

	if OldConnection then
		OldConnection:Destroy()
	end
	self.Owner = NewOwner

	if ClientCast.InitiatedCasters[self] then
		if NewOwner ~= nil and ReplicationConnection then
			ReplicationConnection:Start()
		end
	end
end
--[=[
	Returns the current Player who is the owner of the caster, or nil in case of the server. The owner calculates intersections, and
	as such it's recommended to have the client calculate it to have less of a burden on the server.
	@return Player?
]=]
function ClientCaster:GetOwner()
	return self.Owner
end
--[=[
	Sets this ClientCaster's object which it will raycast from to Object.
	@param Object Instance
]=]
function ClientCaster:SetObject(Object)
	self.Object = Object

	for _, DebugAttachment in next, self._DebugTrails do
		DebugAttachment:Destroy()
	end
	table.clear(self._DebugTrails)
	table.clear(self._DamagePoints)

	local OldConnection = self._DescendantConnection
	if OldConnection then
		OldConnection:Disconnect()
		self._DescendantConnection = nil
	end

	if self.Owner == nil then
		for _, Descendant in next, Object:GetDescendants() do
			self._OnDamagePointAdded(Descendant)
		end
	end
	self._DescendantConnection = self.Owner == nil and Object.DescendantAdded:Connect(self._OnDamagePointAdded) or nil

	local ReplicationConnection = self._ReplicationConnection
	if ReplicationConnection then
		ReplicationConnection:Update({
			Object = Object,
		})
	end
end
--[=[
	Returns the object this ClientCaster is raycasting from.
	@return Instance
]=]
function ClientCaster:GetObject()
	return self.Object
end
--[=[
	Updates the ClientCaster's RaycastParams property.
	@param RaycastParameters RaycastParams
]=]
function ClientCaster:EditRaycastParams(RaycastParameters)
	self.RaycastParams = RaycastParameters
	local ReplicationConnection = self._ReplicationConnection
	if ReplicationConnection then
		ReplicationConnection:Update({
			RaycastParams = RaycastParameters,
		})
	end
end
--[=[
	when set to true, the ClientCasterobject will search for Raycast points (DmgPoints) from the whole Object's descendants, rather then the Object's direct children.
	Useful for whole model hitboxes and characters.
	@param Recursive boolean
]=]
function ClientCaster:SetRecursive(Recursive)
	AssertType(Recursive, "boolean", "Unexpected argument #1 to 'ClientCaster.SetRecursive' (%s expected, got %s)")
	self.Recursive = Recursive

	local ReplicationConnection = self._ReplicationConnection
	if ReplicationConnection then
		ReplicationConnection:Update({
			Recursive = Recursive,
		})
	end
end
function ClientCaster:__index(Index)
	local CollisionIndex = CollisionBaseName[Index]
	if CollisionIndex then
		local CollisionEvent = Signal.new()
		self._CollidedEvents[CollisionIndex][CollisionEvent] = true

		return CollisionEvent
	end

	return rawget(ClientCaster, Index)
end

local UniqueId = 0
local function GenerateId()
	UniqueId += 1
	return UniqueId
end

--[=[
	@param Object Instance
	@param RaycastParameters RaycastParams
	@param NetworkOwner Player

	@return ClientCaster
]=]
function ClientCast.new(Object, RaycastParameters, NetworkOwner)
	AssertType(Object, "Instance", "Unexpected argument #2 to 'ClientCast.new' (%s expected, got %s)")
	AssertType(RaycastParameters, "RaycastParams", "Unexpected argument #3 to 'ClientCast.new' (%s expected, got %s)")
	IsValidOwner(NetworkOwner, "Third argument of ClientCast.new must be a Player")
	local CasterObject

	local DebugTrails = {}
	local DamagePoints = {}

	local function OnDamagePointAdded(Attachment)
		if
			Attachment:IsA("Attachment")
			and Attachment.Name == Settings.AttachmentName
			and not DamagePoints[Attachment]
		then
			local DirectChild = Attachment.Parent == CasterObject.Object
			DamagePoints[Attachment] = DirectChild

			if CasterObject.Owner == nil then
				local Trail = Instance.new("Trail")
				local TrailAttachment = Instance.new("Attachment")

				TrailAttachment.Name = Settings.DebugAttachmentName
				TrailAttachment.Position = Attachment.Position - AttachmentOffset

				Trail.Color = ColorSequence.new(Settings.DebugColor)
				Trail.Enabled = CasterObject._Debug and (DirectChild or CasterObject.Recursive)
				Trail.LightEmission = 1
				Trail.Transparency = TrailTransparency
				Trail.FaceCamera = true
				Trail.Lifetime = Settings.DebugLifetime

				Trail.Attachment0 = Attachment
				Trail.Attachment1 = TrailAttachment

				Trail.Parent = TrailAttachment
				TrailAttachment.Parent = Attachment.Parent

				task.spawn(function()
					repeat
						Attachment.AncestryChanged:Wait()
					until not Attachment:IsDescendantOf(CasterObject.Object)

					TrailAttachment:Destroy()
					DebugTrails[Trail] = nil
					DamagePoints[Attachment] = nil
				end)
				DebugTrails[Trail] = TrailAttachment
			end
		end
	end
	CasterObject = setmetatable({
		RaycastParams = RaycastParameters,
		Object = Object,
		Owner = NetworkOwner,
		Disabled = true,
		Recursive = false,

		_CollidedEvents = {
			Humanoid = {},
			Any = {},
		},
		_ToClean = {},
		_ReplicationConnection = false,
		_Debug = Settings.DebugMode,
		_ExhaustionTime = 1,
		_UniqueId = GenerateId(),
		_DamagePoints = DamagePoints,
		_DebugTrails = DebugTrails,
		_OnDamagePointAdded = OnDamagePointAdded,
		_Class = "Caster",
	}, ClientCaster)

	for _, Descendant in next, Object:GetDescendants() do
		OnDamagePointAdded(Descendant)
	end

	CasterObject._DescendantConnection = Object.DescendantAdded:Connect(OnDamagePointAdded)
	CasterObject._ReplicationConnection = NetworkOwner ~= nil
		and Replication.new(NetworkOwner, Object, RaycastParameters, CasterObject)
	return CasterObject
end

local function UpdateCasterEvents(Caster, RaycastResult)
	if RaycastResult then
		for CollisionEvent in next, Caster._CollidedEvents.Any do
			CollisionEvent:Fire(RaycastResult)
		end

		local ModelAncestor = RaycastResult.Instance:FindFirstAncestorOfClass("Model")
		local Humanoid = ModelAncestor and ModelAncestor:FindFirstChildOfClass("Humanoid")
		if Humanoid then
			for HumanoidEvent in next, Caster._CollidedEvents.Humanoid do
				HumanoidEvent:Fire(RaycastResult, Humanoid)
			end
		end
	end
end
local function UpdateAttachment(Attachment, Caster, LastPositions)
	local CurrentPosition = Attachment.WorldPosition
	local LastPosition = LastPositions[Attachment] or CurrentPosition

	if CurrentPosition ~= LastPosition then
		local RaycastResult = workspace:Raycast(LastPosition, CurrentPosition - LastPosition, Caster.RaycastParams)

		UpdateCasterEvents(Caster, RaycastResult)
	end

	LastPositions[Attachment] = CurrentPosition
end
RunService.Heartbeat:Connect(function()
	for Caster, LastPositions in next, ClientCast.InitiatedCasters do
		local CasterObject = Caster.Object

		if Caster.Owner == nil and CasterObject then
			local RecursiveCaster = Caster.Recursive

			for Attachment, DirectChild in next, Caster._DamagePoints do
				if DirectChild or RecursiveCaster then
					UpdateAttachment(Attachment, Caster, LastPositions)
				end
			end
		end
	end
end)

return ClientCast
