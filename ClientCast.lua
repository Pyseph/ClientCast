local ClientCast = {}
local Settings = {
	AttachmentName = 'DmgPoint', -- The name of the attachment that this network will raycast from

	FunctionDebug = false,
	DebugMode = true, -- DebugMode visualizes the rays, from last to current position
	DebugColor = Color3.new(1, 0, 0), -- The color of the visualized ray
	DebugLifetime = 1, -- Lifetime of the visualized trail
	AutoSetup = true -- Automatically creates a LocalScript and a RemoteEvent to establish a connection to the server, from the client.
}

local ScriptsHolder = script.Parent
if Settings.AutoSetup then
	require(ScriptsHolder.ClientConnection)(ClientCast)
end

ClientCast.Settings = Settings
ClientCast.InitiatedCasters = {}

local RunService = game:GetService('RunService')
local ReplicatedStorage = game:GetService('ReplicatedStorage')

local ReplicationRemote = ReplicatedStorage:FindFirstChild('ClientCast-Replication')
local PingRemote = ReplicatedStorage:FindFirstChild('ClientCast-Ping')

local Janitor = require(ScriptsHolder.Janitor)
local Signal = require(ScriptsHolder.Signal)
local Wait = require(ScriptsHolder.RBXWait)

function SafeRemoteInvoke(RemoteFunction, Player, MaxYield)
	local ThreadResumed = false
	local Thread = coroutine.running()

	coroutine.wrap(function()
		local TimestampStart = time()
		RemoteFunction:InvokeClient(Player)
		local TimestampEnd = time()
		ThreadResumed = true
		coroutine.resume(Thread, math.min(TimestampEnd - TimestampStart, MaxYield))
	end)()

	coroutine.wrap(function()
		Wait(MaxYield)
		if not ThreadResumed then
			ThreadResumed = true
			coroutine.resume(Thread, MaxYield)
		end
	end)()
	return coroutine.yield()
end

function SerializeParams(Params)
	return {
		FilterDescendantsInstances = Params.FilterDescendantsInstances,
		FilterType = Params.FilterType.Name,
		IgnoreWater = Params.IgnoreWater,
		CollisionGroup = Params.CollisionGroup
	}
end
function IsA(Object, Type)
	return typeof(Object) == Type
end
function IsValid(SerializedResult)
	if not IsA(SerializedResult, 'table') then
		return false
	end

	return (SerializedResult.Instance == nil or SerializedResult.Instance:IsA('BasePart') or SerializedResult.Instance:IsA('Terrain')) and
		   IsA(SerializedResult.Position, 'Vector3') and
		   IsA(SerializedResult.Material, 'EnumItem') and
		   IsA(SerializedResult.Normal, 'Vector3')
end

local Replication = {}
local ReplicationBase = {}
ReplicationBase.__index = ReplicationBase

function ReplicationBase:Connect()
	if IsA(self.Owner, 'Instance') and self.Owner:IsA('Player') then
		ReplicationRemote:FireClient(self.Owner, 'Connect', {
			Owner = self.Owner,
			Object = self.Object,
			RaycastParams = SerializeParams(self.RaycastParams),
			Id = self.Caster._UniqueId
		})
		self.Connected = true
		self.Connection = ReplicationRemote.OnServerEvent:Connect(function(Player, Code, RaycastResult, Humanoid)
			if Player == self.Owner and IsValid(RaycastResult) and (Code == 'Any' or Code == 'Humanoid') then
				Humanoid = Code == 'Humanoid' and Humanoid or nil
				for Event in next, self.Caster._CollidedEvents[Code] do
					Event:Invoke(RaycastResult, Humanoid)
				end
			end
		end)
	end
end
function ReplicationBase:Disconnect()
	if IsA(self.Owner, 'Instance') and self.Owner:IsA('Player') then
		ReplicationRemote:FireClient(self.Owner, 'Disconnect', {
			Owner = self.Owner,
			Object = self.Object,
			Id = self.Caster._UniqueId
		})
	end
	self.Connected = false
	if self.Connection then
		self.Connection:Disconnect()
		self.Connection = nil
	end
end
function ReplicationBase:Destroy()
	self:Disconnect()
end

function Replication.new(Player, Object, RaycastParameters, Caster)
	return setmetatable({
		Owner = Player,
		Object = Object,
		RaycastParams = RaycastParameters,
		Connected = false,
		Caster = Caster
	}, ReplicationBase)
end

function AssertType(Object, ExpectedType, Message)
	if not IsA(Object, ExpectedType) then
		error(string.format(Message, ExpectedType, typeof(Object)), 4)
	end
end
function AssertClass(Object, ExpectedClass, Message)
	AssertType(Object, 'Instance', Message)
	if not Object:IsA(ExpectedClass) then
		error(string.format(Message, ExpectedClass, Object.Class), 4)
	end
end
function AssertNaN(Object, Message)
	if Object ~= Object then
		error(string.format(Message, 'number', typeof(Object)), 4)
	end
end
function IsValidOwner(Value)
	local IsInstance = IsA(Value, 'Instance')
	if not IsInstance and Value ~= nil then
		error('Unable to cast value to Object', 4)
	elseif IsInstance and not Value:IsA('Player') then
		error('SetOwner only takes player or \'nil\' instance as an argument.', 4)
	end
end

local ClientCaster = {}
local DebugObject = {}

local VisualizedAttachments = {}
local TrailTransparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0),
	NumberSequenceKeypoint.new(0.5, 0.5),
	NumberSequenceKeypoint.new(1, 1)
})

function DebugObject:Disable(Attachment)
	local SavedAttachment = VisualizedAttachments[Attachment]
	if SavedAttachment then
		SavedAttachment.Trail.Enabled = false
	end
end
function DebugObject:Visualize(CasterDebug, Attachment)
	local SavedAttachment = VisualizedAttachments[Attachment]

	if (Settings.DebugMode or CasterDebug) and not SavedAttachment then
		local Trail = Instance.new('Trail')
		local TrailAttachment = Instance.new('Attachment')

		TrailAttachment.Name = 'DebugAttachment'
		TrailAttachment.Position = Attachment.Position - Vector3.new(0, 0, 0.1)

		Trail.Color = ColorSequence.new(Settings.DebugColor)
		Trail.LightEmission = 1
		Trail.Transparency = TrailTransparency
		Trail.FaceCamera = true
		Trail.Lifetime = Settings.DebugLifetime

		Trail.Attachment0 = Attachment
		Trail.Attachment1 = TrailAttachment

		Trail.Parent = TrailAttachment
		TrailAttachment.Parent = Attachment.Parent

		VisualizedAttachments[Attachment] = TrailAttachment
	elseif SavedAttachment then
		if not Settings.DebugMode and not CasterDebug then
			SavedAttachment:Destroy()
			VisualizedAttachments[Attachment] = nil
		elseif not SavedAttachment.Trail.Enabled then
			SavedAttachment.Trail.Enabled = true
		end
	end
end

local CollisionBaseName = {
	Collided = 'Any',
	HumanoidCollided = 'Humanoid'
}

function ClientCaster:Start()
	if self._ReplicationConnection and not self._ReplicationConnection.Connected then
		self._ReplicationConnection:Connect()
	end
	ClientCast.InitiatedCasters[self] = {}
end
function ClientCaster:Destroy()
	if self._ReplicationConnection then
		self._ReplicationConnection:Destroy()
	end
	ClientCast.InitiatedCasters[self] = nil
	self.RaycastParams = nil
	self.Object = nil

	self._Janitor:Destroy()
end
function ClientCaster:Stop()
	local OldConn = self._ReplicationConnection
	if OldConn then
		OldConn:Destroy()
	end

	ClientCast.InitiatedCasters[self] = nil
end
function ClientCaster:SetOwner(NewOwner)
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
			ReplConn:Connect()
		end
	end
	for _, Attachment in next, self.Object:GetChildren() do
		if Attachment.ClassName == 'Attachment' and Attachment.Name == Settings.AttachmentName then
			DebugObject:Disable(Attachment)
		end
	end
end
function ClientCaster:GetOwner()
	return self.Owner
end
function ClientCaster:SetMaxPingExhaustion(Time)
	AssertType(Time, 'number', 'Unexpected argument #1 to \'ClientCaster.SetMaxPingExhaustion\' (%s expected, got %s)')
	AssertNaN(Time, 'Unexpected argument #1 to \'ClientCaster.SetMaxPingExhaustion\' (%s expected, got NaN)')
	if Time < 0.1 then
		error('The max ping exhaustion time passed to \'ClientCaster.SetMaxPingExhaustion\' must be longer than 0.1', 3)
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
	AssertClass(Object, 'BasePart', 'Unexpected argument #1 to \'ClientCaster:SetObject\' (%s expected, got %s)')

	self.Object = Object
	ClientCaster:SetOwner(self.Owner)
end
function ClientCaster:GetObject()
	return self.Object
end
function ClientCaster:EditRaycastParams(RaycastParameters)
	self.RaycastParams = RaycastParameters
	ClientCaster:SetOwner(self.Owner)
end
function ClientCaster:SetDebug(Bool)
	self._Debug = Bool
	ClientCaster:SetOwner(self.Owner)
end
function ClientCaster:GetDebug()
	return self._Debug
end

function ClientCaster:__index(Index)
	local CollisionIndex = CollisionBaseName[Index]
	if CollisionIndex then
		local CollisionEvent = Signal.new()
		self._CollidedEvents[CollisionIndex][CollisionEvent] = true

		return CollisionEvent.Invoked
	end

	local Value = ClientCaster[Index]
	return (type(Value) == 'function' and not Settings.FunctionDebug) and coroutine.wrap(Value) or Value
end

local UniqueId = 0
function GenerateId()
	UniqueId += 1
	return UniqueId
end
function ClientCast.new(Object, RaycastParameters, NetworkOwner)
	IsValidOwner(NetworkOwner)
	AssertType(Object, 'Instance', 'Unexpected argument #2 to \'CastObject.new\' (%s expected, got %s)')
	AssertType(RaycastParameters, 'RaycastParams', 'Unexpected argument #3 to \'CastObject.new\' (%s expected, got %s)')

	local JanitorObject = Janitor.new()
	local CasterObject = setmetatable({
		RaycastParams = RaycastParameters,
		Object = Object,
		Owner = NetworkOwner,

		_CollidedEvents = {
			Humanoid = {},
			Any = {}
		},
		_ToClean = {},
		_Janitor = JanitorObject,
		_ReplicationConnection = false,
		_Debug = false,
		_ExhaustionTime = 1,
		_UniqueId = GenerateId()
	}, ClientCaster)
	CasterObject._ReplicationConnection = NetworkOwner ~= nil and Replication.new(NetworkOwner, Object, RaycastParameters, CasterObject)

	JanitorObject:Add(CasterObject)
	return CasterObject
end

function UpdateCasterEvents(Caster, RaycastResult)
	if RaycastResult then
		for CollisionEvent in next, Caster._CollidedEvents.Any do
			CollisionEvent:Invoke(RaycastResult)
		end

		local ModelAncestor = RaycastResult.Instance:FindFirstAncestorOfClass('Model')
		local Humanoid = ModelAncestor and ModelAncestor:FindFirstChildOfClass('Humanoid')
		if Humanoid then
			for HumanoidEvent in next, Caster._CollidedEvents.Humanoid do
				HumanoidEvent:Invoke(RaycastResult, Humanoid)
			end
		end
	end
end
function UpdateAttachment(Attachment, Caster, LastPositions)
	if Attachment.ClassName == 'Attachment' and Attachment.Name == Settings.AttachmentName then
		local CurrentPosition = Attachment.WorldPosition
		local LastPosition = LastPositions[Attachment] or CurrentPosition

		if CurrentPosition ~= LastPosition then
			local RaycastResult = workspace:Raycast(CurrentPosition, CurrentPosition - LastPosition, Caster.RaycastParams)

			UpdateCasterEvents(Caster, RaycastResult)
			DebugObject:Visualize(Caster._Debug, Attachment)
		end

		LastPositions[Attachment] = CurrentPosition
	end
end
RunService.Heartbeat:Connect(function()
	for Caster, LastPositions in next, ClientCast.InitiatedCasters do
		if Caster.Owner == nil then
			for _, Attachment in next, Caster.Object:GetChildren() do
				UpdateAttachment(Attachment, Caster, LastPositions)
			end
		end
	end
end)

return ClientCast