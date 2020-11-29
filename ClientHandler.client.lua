wait()
script.Parent = game:GetService('Players').LocalPlayer:FindFirstChildOfClass('PlayerScripts')

local ReplicatedStorage = game:GetService('ReplicatedStorage')
local RunService = game:GetService('RunService')

local ReplicationRemote = ReplicatedStorage:WaitForChild('ClientCast-Replication')

local ClientCast = {}
local Settings = {
	AttachmentName = 'DmgPoint', -- The name of the attachment that this network will raycast from

	DebugMode = true, -- DebugMode visualizes the rays, from last to current position
	DebugColor = Color3.new(1, 0, 0), -- The color of the visualized ray
	DebugLifetime = 1, -- Lifetime of the visualized trail
}

ClientCast.Settings = Settings
ClientCast.InitiatedCasters = {}

local Maid = require(script.Maid)
local Connection = require(script.Connection)

function AssertType(Object, ExpectedType, Message)
	if typeof(Object) ~= ExpectedType then
		error(string.format(Message, ExpectedType, typeof(Object)), 3)
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
	ClientCast.InitiatedCasters[self] = {}
end
function ClientCaster:Destroy()
	ClientCast.InitiatedCasters[self] = nil
	
	for HolderName, EventsHolder in next, self._CollidedEvents do
		for Event in next, EventsHolder do
			Event:Destroy()
		end
	end
	for Idx, Child in next, self.Object:GetChildren() do
		if Child:IsA('Attachment') and Child.Name == Settings.AttachmentName then
			DebugObject:Disable(Child)
		end
	end

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

	return rawget(ClientCaster, Index)
end

function ClientCast.new(Object, RaycastParameters)
	AssertType(Object, 'Instance', 'Unexpected argument #1 to \'CastObject.new\' (%s expected, got %s)')

	local MaidObject = Maid.new()
	local CasterObject = setmetatable({
		RaycastParams = RaycastParameters,
		Object = Object,
		Debug = false,

		_CollidedEvents = {
			Humanoid = {},
			Any = {}
		},
		_ToClean = {},
		_Maid = MaidObject
	}, ClientCaster)

	MaidObject:GiveTask(CasterObject)
	return CasterObject
end

function SerializeResult(Result)
	return {
		Instance = Result.Instance,
		Position = Result.Position,
		Material = Result.Material,
		Normal = Result.Normal
	}
end
function DeserializeParams(Input)
	local Params = RaycastParams.new()
	for Key, Value in next, Input do
		if Key == 'FilterType' then
			Value = Enum['RaycastFilterType'][Value]
		end
		Params[Key] = Value
	end
	
	return Params
end
function UpdateCasterEvents(RaycastResult)
	if RaycastResult then
		ReplicationRemote:FireServer('Any', SerializeResult(RaycastResult))

		local ModelAncestor = RaycastResult.Instance:FindFirstAncestorOfClass('Model')
		local Humanoid = ModelAncestor and ModelAncestor:FindFirstChildOfClass('Humanoid')
		if Humanoid then
			ReplicationRemote:FireServer('Humanoid', SerializeResult(RaycastResult), Humanoid)
		end
	end
end
function UpdateAttachment(Attachment, Caster, LastPositions)
	if Caster and Caster.Object and Attachment.ClassName == 'Attachment' and Attachment.Name == Settings.AttachmentName then
		local CurrentPosition = Attachment.WorldPosition
		local LastPosition = LastPositions[Attachment] or CurrentPosition

		if CurrentPosition ~= LastPosition then
			local RaycastResult = workspace:Raycast(CurrentPosition, CurrentPosition - LastPosition, Caster.RaycastParams)

			UpdateCasterEvents(RaycastResult)
			DebugObject:Visualize(Caster.Debug, Attachment)
		end

		LastPositions[Attachment] = CurrentPosition
	end
end

local ClientCasters = {}
RunService.Heartbeat:Connect(function()
	for Caster, LastPositions in next, ClientCast.InitiatedCasters do
		local Object = Caster.Object
		if not Object then
			continue
		end
		for _, Attachment in next, Object:GetChildren() do
			UpdateAttachment(Attachment, Caster, LastPositions)
		end
	end
end)

ReplicationRemote.OnClientEvent:Connect(function(Status, Data)
	if Status == 'Connect' then
		local Caster = ClientCast.new(Data.Object, DeserializeParams(Data.RaycastParams))
		ClientCasters[Data.Id] = Caster
		Caster:Start()
	elseif Status == 'Disconnect' then
		local Caster = ClientCasters[Data.Id]
		if Caster then
			Caster:Destroy()
			Caster = nil
			ClientCasters[Data.Id] = nil
		end
	end
end)
