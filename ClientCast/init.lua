local ClientCast = {}
local Settings = {
	AttachmentName = "DmgPoint", -- The name of the attachment that this network will raycast from
	DebugAttachmentName = "ClientCast-Debug", -- The name of the debug trail attachment

	FunctionDebug = false,
	DebugMode = false, -- DebugMode visualizes the rays, from last to current position
	DebugColor = Color3.new(1, 0, 0), -- The color of the visualized ray
	DebugLifetime = 1, -- Lifetime of the visualized trail
	AutoSetup = true -- Automatically creates a LocalScript and a RemoteEvent to establish a connection to the server, from the client.
}

if Settings.AutoSetup then
	require(script.ClientConnection)()
end

ClientCast.Settings = Settings
ClientCast.InitiatedCasters = {}

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ReplicationRemote = ReplicatedStorage:FindFirstChild("ClientCast-Replication")
local PingRemote = ReplicatedStorage:FindFirstChild("ClientCast-Ping")

local Signal = require(script.Signal)

local function SafeRemoteInvoke(RemoteFunction, Player, MaxYield)
	local ThreadResumed = false
	local Thread = coroutine.running()

	task.spawn(function()
		local TimestampStart = time()
		RemoteFunction:InvokeClient(Player)
		local TimestampEnd = time()

		ThreadResumed = true
		task.spawn(Thread, math.min(TimestampEnd - TimestampStart, MaxYield))
	end)

	task.delay(MaxYield, function()
		if not ThreadResumed then
			ThreadResumed = true
			task.spawn(Thread, MaxYield)
		end
	end)

	return coroutine.yield()
end

local function SerializeParams(Params)
	return {
		FilterDescendantsInstances = Params.FilterDescendantsInstances,
		FilterType = Params.FilterType.Name,
		IgnoreWater = Params.IgnoreWater,
		CollisionGroup = Params.CollisionGroup
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
local function AssertNaN(Object, Message)
	if Object ~= Object then
		error(string.format(Message, "number", typeof(Object)), 4)
	end
end
local function IsValidOwner(Value)
	local IsInstance = IsA(Value, "Instance")
	if not IsInstance and Value ~= nil then
		error("Unable to cast value to Object", 4)
	elseif IsInstance and not Value:IsA("Player") then
		error("SetOwner only takes player or 'nil' instance as an argument.", 4)
	end
end
local function IsValid(SerializedResult)
	if not IsA(SerializedResult, "table") then
		return false
	end

	return (SerializedResult.Instance ~= nil and (SerializedResult.Instance:IsA("BasePart") or SerializedResult.Instance:IsA("Terrain"))) and
		IsA(SerializedResult.Position, "Vector3") and
		IsA(SerializedResult.Material, "EnumItem") and
		IsA(SerializedResult.Normal, "Vector3")
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
		Id = self.Caster._UniqueId
	})

	self.Connection = ReplicationRemote.OnServerEvent:Connect(function(Player, Code, RaycastResult)
		if Player == Owner and IsValid(RaycastResult) and (Code == "Any" or Code == "Humanoid") then
			local Humanoid
			if Code == "Humanoid" then
				local Model = RaycastResult.Instance:FindFirstAncestorOfClass("Model")
				Humanoid = Model and Model:FindFirstChildOfClass("Humanoid")
			end

			if Code == "Humanoid" and Humanoid == nil then
				return
			end

			for Event in next, self.Caster._CollidedEvents[Code] do
				Event:Invoke(RaycastResult, Humanoid)
			end
		end
	end)
end
function ReplicationBase:Update(AdditionalData)
	local Data = {
		Owner = self.Owner,
		Object = self.Object,
		Debug = self.Caster._Debug,
		RaycastParams = SerializeParams(self.RaycastParams),
		Id = self.Caster._UniqueId
	}
	ReplicationRemote:FireClient(self.Owner, "Update", Data, AdditionalData)
end
function ReplicationBase:Stop(Destroy)
	local Owner = self.Owner

	ReplicationRemote:FireClient(Owner, Destroy and "Destroy" or "Stop", {
		Owner = Owner,
		Object = self.Object,
		Id = self.Caster._UniqueId
	})

	local ReplicationConn = self.Connection
	if ReplicationConn then
		ReplicationConn:Disconnect()
		ReplicationConn = nil
	end

	if Destroy then
		table.clear(self)
		setmetatable(self, nil)
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
		Caster = Caster
	}, ReplicationBase)
end

local ClientCaster = {}

local TrailTransparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0),
	NumberSequenceKeypoint.new(0.5, 0),
	NumberSequenceKeypoint.new(1, 1)
})
local AttachmentOffset = Vector3.new(0, 0, 0.1)

function ClientCaster:DisableDebug()
	local ReplicationConnection = self._ReplicationConnection

	if ReplicationConnection then
		ReplicationConnection:Update({
			Debug = false
		})
	end

	self._Debug = false
	for Trail in next, self._DebugTrails do
		Trail.Enabled = false
	end
end
function ClientCaster:StartDebug()
	local ReplicationConnection = self._ReplicationConnection

	if ReplicationConnection then
		ReplicationConnection:Update({
			Debug = true
		})
	end

	self._Debug = true
	for Trail in next, self._DebugTrails do
		Trail.Enabled = true
	end
end

local CollisionBaseName = {
	Collided = "Any",
	HumanoidCollided = "Humanoid"
}

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
function ClientCaster:Destroy()
	local ReplicationConn = self._ReplicationConnection
	if ReplicationConn then
		self._ReplicationConnection = nil
		ReplicationConn:Destroy()
	end

	self._DescendantConnection:Disconnect()
	for _, DebugAttachment in next, self._DebugTrails do
		DebugAttachment:Destroy()
	end
	for _, EventsHolder in next, self._CollidedEvents do
		for Event in next, EventsHolder do
			Event:Destroy()
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
function ClientCaster:SetOwner(NewOwner)
	local Remainder = time() - self._Created
	task.spawn(function()
		if Remainder < 0.1 then
			task.wait(0.1 - Remainder)
		end

		IsValidOwner(NewOwner)
		local OldConn = self._ReplicationConnection
		local ReplConn = NewOwner ~= nil and Replication.new(NewOwner, self.Object, self.RaycastParams, self)
		self._ReplicationConnection = ReplConn

		if OldConn then
			OldConn:Destroy()
		end
		self.Owner = NewOwner

		if ClientCast.InitiatedCasters[self] then
			if NewOwner ~= nil and ReplConn then
				ReplConn:Start()
			end
		end
	end)
end
function ClientCaster:GetOwner()
	return self.Owner
end
function ClientCaster:SetMaxPingExhaustion(Time)
	AssertType(Time, "number", "Unexpected argument #1 to 'ClientCaster.SetMaxPingExhaustion' (%s expected, got %s)")
	AssertNaN(Time, "Unexpected argument #1 to 'ClientCaster.SetMaxPingExhaustion' (%s expected, got NaN)")
	if Time < 0.1 then
		error("The max ping exhaustion time passed to 'ClientCaster.SetMaxPingExhaustion' must be longer than 0.1", 3)
		return
	end

	self._ExhaustionTime = Time
end
function ClientCaster:GetMaxPingExhaustion()
	return self._ExhaustionTime
end
function ClientCaster:GetPing()
	if self.Owner == nil then
		return 0
	end

	return SafeRemoteInvoke(PingRemote, self.Owner, self._ExhaustionTime)
end
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
	task.spawn(function()
		if ReplicationConnection then
			local Remainder = time() - self._Created
			if Remainder < 1 then
				task.wait(1 - Remainder)
			end

			ReplicationConnection:Update({
				Object = Object
			})
		end
	end)
end
function ClientCaster:GetObject()
	return self.Object
end
function ClientCaster:EditRaycastParams(RaycastParameters)
	self.RaycastParams = RaycastParameters
	local ReplicationConnection = self._ReplicationConnection
	if ReplicationConnection then
		local Remainder = time() - self._Created

		task.spawn(function()
			if Remainder < 1 then
				task.wait(1 - Remainder)
			end
			ReplicationConnection:Update({
				RaycastParams = RaycastParameters
			})
		end)
	end
end
function ClientCaster:SetRecursive(Bool)
	AssertType(Bool, "boolean", "Unexpected argument #1 to 'ClientCaster.SetRecursive' (%s expected, got %s)")
	self.Recursive = Bool

	local Remainder = time() - self._Created
	task.spawn(function()
		if Remainder < 0.1 then
			task.wait(0.1 - Remainder)
		end

		local ReplicationConnection = self._ReplicationConnection
		if ReplicationConnection then
			ReplicationConnection:Update({
				Recursive = Bool
			})
		end
	end)
end
function ClientCaster:__index(Index)
	local CollisionIndex = CollisionBaseName[Index]
	if CollisionIndex then
		local CollisionEvent = Signal.new()
		self._CollidedEvents[CollisionIndex][CollisionEvent] = true

		return CollisionEvent.Invoked
	end

	return rawget(ClientCaster, Index)
end

local UniqueId = 0
local function GenerateId()
	UniqueId += 1
	return UniqueId
end
function ClientCast.new(Object, RaycastParameters, NetworkOwner)
	IsValidOwner(NetworkOwner)
	AssertType(Object, "Instance", "Unexpected argument #2 to 'CastObject.new' (%s expected, got %s)")
	AssertType(RaycastParameters, "RaycastParams", "Unexpected argument #3 to 'CastObject.new' (%s expected, got %s)")
	local CasterObject

	local DebugTrails = {}
	local DamagePoints = {}

	local function OnDamagePointAdded(Attachment)
		if Attachment.ClassName == "Attachment" and Attachment.Name == Settings.AttachmentName and not DamagePoints[Attachment] then
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
			Any = {}
		},
		_ToClean = {},
		_Created = time(),
		_ReplicationConnection = false,
		_Debug = Settings.DebugMode,
		_ExhaustionTime = 1,
		_UniqueId = GenerateId(),
		_DamagePoints = DamagePoints,
		_DebugTrails = DebugTrails,
		_OnDamagePointAdded = OnDamagePointAdded,
		_Class = "Caster"
	}, ClientCaster)

	for _, Descendant in next, Object:GetDescendants() do
		OnDamagePointAdded(Descendant)
	end

	CasterObject._DescendantConnection = Object.DescendantAdded:Connect(OnDamagePointAdded)
	CasterObject._ReplicationConnection = NetworkOwner ~= nil and Replication.new(NetworkOwner, Object, RaycastParameters, CasterObject)
	return CasterObject
end

local function UpdateCasterEvents(Caster, RaycastResult)
	if RaycastResult then
		for CollisionEvent in next, Caster._CollidedEvents.Any do
			CollisionEvent:Invoke(RaycastResult)
		end

		local ModelAncestor = RaycastResult.Instance:FindFirstAncestorOfClass("Model")
		local Humanoid = ModelAncestor and ModelAncestor:FindFirstChildOfClass("Humanoid")
		if Humanoid then
			for HumanoidEvent in next, Caster._CollidedEvents.Humanoid do
				HumanoidEvent:Invoke(RaycastResult, Humanoid)
			end
		end
	end
end
local function UpdateAttachment(Attachment, Caster, LastPositions)
	local CurrentPosition = Attachment.WorldPosition
	local LastPosition = LastPositions[Attachment] or CurrentPosition

	if CurrentPosition ~= LastPosition then
		local RaycastResult = workspace:Raycast(CurrentPosition, LastPosition - CurrentPosition, Caster.RaycastParams)

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
