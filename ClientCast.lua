local ClientCast = {}
local Settings = {
	AttachmentName = 'DmgPoint', -- The name of the attachment that this network will raycast from

	DebugMode = true, -- DebugMode visualizes the rays, from last to current position
	DebugColor = Color3.new(1, 0, 0), -- The color of the visualized ray
	DebugLifetime = 1, -- Lifetime of the visualized trail
	AutoSetup = true -- Automatically creates a LocalScript and a RemoteEvent to establish a connection to the server, from the client.
}

if Settings.AutoSetup then
	require(script.Parent.ClientConnection)(ClientCast)
end

ClientCast.Settings = Settings
ClientCast.InitiatedCasters = {}

local RunService = game:GetService('RunService')
local ReplicatedStorage = game:GetService('ReplicatedStorage')

local ReplicationRemote = ReplicatedStorage:FindFirstChild('ClientCast-Replication')

local Maid = require(script.Parent.Maid)
local Connection = require(script.Parent.Connection)

function SerializeParams(Params)
	return {
		FilterDescendantsInstances = {},
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

	return (SerializedResult.Instance:IsA('BasePart') or SerializedResult.Instance:IsA('Terrain')) and
			IsA(SerializedResult.Position, 'Vector3') and
			IsA(SerializedResult.Material, 'EnumItem') and
			IsA(SerializedResult.Normal, 'Vector3')
end

local Replication = {}
local ReplicationBase = {}
ReplicationBase.__index = ReplicationBase

function ReplicationBase:Connect()
	ReplicationRemote:FireClient(self.Owner, 'Connect', {
		Owner = self.Owner, 
		Object = self.Object,
		RaycastParams = SerializeParams(self.RaycastParams)
	})
	self.Connected = true
	self.Connection = ReplicationRemote.OnServerEvent:Connect(function(Player, Code, RaycastResult, Humanoid)
		print(1)
		if IsValid(RaycastResult) and (Code == 'Any' or Code == 'Humanoid') then
			print(2)
			Humanoid = Code == 'Humanoid' and Humanoid or nil
			for Event in next, self.Caster._CollidedEvents[Code] do
				Event:Invoke(RaycastResult, Humanoid)
			end
		end
	end)
end
function ReplicationBase:Disconnect()
	ReplicationRemote:FireClient(self.Owner, 'Disconnect', {
		Owner = self.Owner, 
		Object = self.Object
	})
	self.Connected = false
	if self.Connection then
		self.Connection:Disconnect()
		self.Connection = nil
	end
end
function ReplicationBase:Destroy() self.Connected = false end

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
	if typeof(Object) ~= ExpectedType then
		error(string.format(Message, ExpectedType, typeof(Object)), 4)
	end
end
function AssertClass(Object, ExpectedClass, Message)
	AssertType(Object, 'Instance', Message)
	if not Object:IsA(ExpectedClass) then
		error(string.format(Message, ExpectedClass, Object.Class), 4)
	end
end

local ClientCaster = {}
local DebugObject = {}

local VisualizedAttachments = {}
local TrailTransparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0),
	NumberSequenceKeypoint.new(0.5, 0),
	NumberSequenceKeypoint.new(1, 1)
})
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
	elseif not Settings.DebugMode and not CasterDebug and SavedAttachment then
		SavedAttachment:Destroy()
		VisualizedAttachments[Attachment] = nil
	end
end

local CollisionBaseName = {
	Collided = 'Any',
	HumanoidCollided = 'Humanoid'
}

function ClientCaster:Initialize()
	self._ReplicationConnection:Connect()
	ClientCast.InitiatedCasters[self] = {}
end
function ClientCaster:Destroy()
	self._ReplicationConnection:Disconnect()
	ClientCast.InitiatedCasters[self] = nil
	self.RaycastParams = nil
	self.Object = nil

	self._Maid:Destroy()
end
function ClientCaster:Stop()
	ClientCast.InitiatedCasters[self] = nil
end
function ClientCaster:Debug(Bool)
	self.Debug = Bool
end
function ClientCaster:__index(Index)
	local CollisionIndex = CollisionBaseName[Index]
	if CollisionIndex then
		local CollisionEvent = Connection.new()
		self._CollidedEvents[CollisionIndex][CollisionEvent] = true

		return CollisionEvent.Invoked
	end

	return ClientCaster[Index]
end

function ClientCast.new(NetworkOwner, Object, RaycastParameters)
	if NetworkOwner ~= 'Any' then
		AssertClass(NetworkOwner, 'Player', 'Unexpected argument #1 to \'CastObject.new\' (%s expected, got %s)')
	end
	AssertType(Object, 'Instance', 'Unexpected argument #2 to \'CastObject.new\' (%s expected, got %s)')
	AssertType(RaycastParameters, 'RaycastParams', 'Unexpected argument #3 to \'CastObject.new\' (%s expected, got %s)')

	local MaidObject = Maid.new()
	local CasterObject = setmetatable({
		RaycastParams = RaycastParameters,
		Object = Object,
		Debug = false,
		Owner = NetworkOwner,

		_CollidedEvents = {
			Humanoid = {},
			Any = {}
		},
		_ToClean = {},
		_Maid = MaidObject,
		_ReplicationConnection = false
	}, ClientCaster)
	print(NetworkOwner ~= 'Any')
	CasterObject._ReplicationConnection = NetworkOwner ~= 'Any' and Replication.new(NetworkOwner, Object, RaycastParameters, CasterObject) or nil

	MaidObject:GiveTask(CasterObject)
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
			DebugObject:Visualize(Caster.Debug, Attachment)
		end

		LastPositions[Attachment] = CurrentPosition
	end
end
RunService.Heartbeat:Connect(function()
	for Caster, LastPositions in next, ClientCast.InitiatedCasters do
		if Caster.Owner == 'Any' then
			for _, Attachment in next, Caster.Object:GetChildren() do
				UpdateAttachment(Attachment, Caster, LastPositions)
			end
		end
	end
end)

return ClientCast
