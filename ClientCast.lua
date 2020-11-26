local ClientCast = {}
local Settings = {
	AttachmentName = 'DmgPoint', -- The name of the attachment that this network will raycast from

	DebugMode = true, -- DebugMode visualizes the rays, from last to current position
	DebugColor = Color3.new(1, 0, 0), -- The color of the visualized ray
	DebugLifetime = 1 -- Lifetime of the visualized trail
}

ClientCast.Settings = Settings
ClientCast.InitiatedCasters = {}

local RunService = game:GetService('RunService')
local Terrain = workspace:FindFirstChildOfClass('Terrain')

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
	ClientCast.InitiatedCasters[self] = {}
end
function ClientCaster:Destroy()
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

function ClientCast.new(Object, RaycastParameters)
	AssertType(Object, 'Instance', 'Unexpected argument #1 to \'CastObject.new\' (%s expected, got %s)')
	AssertType(RaycastParameters, 'RaycastParams', 'Unexpected argument #2 to \'CastObject.new\' (%s expected, got %s)')

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
		for _, Attachment in next, Caster.Object:GetChildren() do
			UpdateAttachment(Attachment, Catser, LastPositions)
		end
	end
end)

return ClientCast
