wait() -- Necessary wait because the Parent property is locked for a split moment
local ThisScript = script -- script.Parent = x makes selene mad :Z
ThisScript.Parent = game:GetService('Players').LocalPlayer:FindFirstChildOfClass('PlayerScripts')

local ReplicatedStorage = game:GetService('ReplicatedStorage')
local RunService = game:GetService('RunService')

local ReplicationRemote = ReplicatedStorage:WaitForChild('ClientCast-Replication')
local PingRemote = ReplicatedStorage:WaitForChild('ClientCast-Ping')

PingRemote.OnClientInvoke = function() end

local ClientCast = {}
local Settings = {
	AttachmentName = 'DmgPoint', -- The name of the attachment that this network will raycast from

	DebugMode = true, -- DebugMode visualizes the rays, from last to current position
	DebugColor = Color3.new(1, 0, 0), -- The color of the visualized ray
	DebugLifetime = 1, -- Lifetime of the visualized trail
}

ClientCast.Settings = Settings
ClientCast.InitiatedCasters = {}

local Signal = require(script.Signal)

local function AssertType(Object, ExpectedType, Message)
	if typeof(Object) ~= ExpectedType then
		error(string.format(Message, ExpectedType, typeof(Object)), 3)
	end
end

local ClientCaster = {}

function ClientCaster:DisableDebug()
	for _, Trail in next, self._DebugTrails do
		Trail.Enabled = false
	end
end
function ClientCaster:StartDebug()
	for _, Trail in next, self._DebugTrails do
		Trail.Enabled = true
	end
end

local CollisionBaseName = {
	Collided = 'Any',
	HumanoidCollided = 'Humanoid'
}

function ClientCaster:Start()
	self.Disabled = false
	ClientCast.InitiatedCasters[self] = {}

	if self._Debug then
		self:StartDebug()
	end
end
function ClientCaster:Destroy()
	self.Disabled = true
	ClientCast.InitiatedCasters[self] = nil

	for _, EventsHolder in next, self._CollidedEvents do
		for Event in next, EventsHolder do
			Event:Destroy()
		end
	end
	self:DisableDebug()
end
function ClientCaster:Stop()
	self.Disabled = true
	ClientCast.InitiatedCasters[self] = nil
	self:DisableDebug()
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

function ClientCast.new(Object, RaycastParameters)
	AssertType(Object, 'Instance', 'Unexpected argument #1 to \'CastObject.new\' (%s expected, got %s)')

	local DebugTrails = {}
	local DamagePoints = {}
	local CasterObject = setmetatable({
		RaycastParams = RaycastParameters,
		Object = Object,
		Disabled = true,

		_CollidedEvents = {
			Humanoid = {},
			Any = {}
		},
		DamagePoints = DamagePoints,
		_Debug = false,
		_ToClean = {},
		_DebugTrails = DebugTrails
	}, ClientCaster)

	for _, Attachment in next, Object:GetChildren() do
		if Attachment.ClassName == 'Attachment' and Attachment.Name == 'ClientCast-Debug' then
			table.insert(DamagePoints, Attachment)
			table.insert(DebugTrails, Attachment.Trail)
		end
	end

	return CasterObject
end

local function SerializeResult(Result)
	return {
		Instance = Result.Instance,
		Position = Result.Position,
		Material = Result.Material,
		Normal = Result.Normal
	}
end
local function DeserializeParams(Input)
	local Params = RaycastParams.new()
	for Key, Value in next, Input do
		if Key == 'FilterType' then
			Value = Enum.RaycastFilterType[Value]
		end
		Params[Key] = Value
	end

	return Params
end
local function UpdateCasterEvents(RaycastResult)
	if RaycastResult then
		ReplicationRemote:FireServer('Any', SerializeResult(RaycastResult))

		local ModelAncestor = RaycastResult.Instance:FindFirstAncestorOfClass('Model')
		local Humanoid = ModelAncestor and ModelAncestor:FindFirstChildOfClass('Humanoid')
		if Humanoid then
			ReplicationRemote:FireServer('Humanoid', SerializeResult(RaycastResult), Humanoid)
		end
	end
end
local function UpdateAttachment(Attachment, Caster, LastPositions)
	local CurrentPosition = Attachment.WorldPosition
	local LastPosition = LastPositions[Attachment] or CurrentPosition

	if CurrentPosition ~= LastPosition then
		local RaycastResult = workspace:Raycast(CurrentPosition, CurrentPosition - LastPosition, Caster.RaycastParams)

		UpdateCasterEvents(RaycastResult)
	end

	LastPositions[Attachment] = CurrentPosition
end

local ClientCasters = {}
RunService.Heartbeat:Connect(function()
	for Caster, LastPositions in next, ClientCast.InitiatedCasters do
		local Object = Caster.Object
		if not Object then
			continue
		end

		for _, Attachment in next, Caster.DamagePoints do
			UpdateAttachment(Attachment, Caster, LastPositions)
		end
	end
end)

ReplicationRemote.OnClientEvent:Connect(function(Status, Data)
	if Status == 'Start' then
		local Caster = ClientCasters[Data.Id]
		if not Caster then
			Caster = ClientCast.new(Data.Object, DeserializeParams(Data.RaycastParams))
			ClientCasters[Data.Id] = Caster
			Caster._Debug = Data.Debug
		end
		Caster:Start()
	elseif Status == 'Destroy' then
		local Caster = ClientCasters[Data.Id]
		if Caster then
			Caster:Destroy()
			Caster = nil
			ClientCasters[Data.Id] = nil
		end
	elseif Status == 'Stop' then
		local Caster = ClientCasters[Data.Id]
		if Caster then
			Caster:Stop()
		end
	end
end)