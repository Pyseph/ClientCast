local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local ReplicationRemote = ReplicatedStorage:WaitForChild("ClientCast-Replication")
local PingRemote = ReplicatedStorage:WaitForChild("ClientCast-Ping")

task.defer(function()
	local ThisScript = script -- script.Parent = x makes selene mad :Z
	ThisScript.Parent = Players.LocalPlayer:FindFirstChildOfClass("PlayerScripts")
end)

PingRemote.OnClientInvoke = function() end

local ClientCast = {}
local Settings = {
	AttachmentName = "DmgPoint", -- The name of the attachment that this network will raycast from
	DebugAttachmentName = "ClientCast-Debug", -- The name of the debug trail attachment

	DebugMode = false, -- DebugMode visualizes the rays, from last to current position
	DebugColor = Color3.new(1, 0, 0), -- The color of the visualized ray
	DebugLifetime = 1, -- Lifetime of the visualized trail
}

ClientCast.Settings = Settings
ClientCast.InitiatedCasters = {}

local TrailTransparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0),
	NumberSequenceKeypoint.new(0.5, 0),
	NumberSequenceKeypoint.new(1, 1)
})
local AttachmentOffset = Vector3.new(0, 0, 0.1)

local Signal = require(script.Signal)

local function AssertType(Object, ExpectedType, Message)
	if typeof(Object) ~= ExpectedType then
		error(string.format(Message, ExpectedType, typeof(Object)), 3)
	end
end

local ClientCaster = {}

function ClientCaster:DisableDebug()
	self._Debug = false
	for Trail in next, self._DebugTrails do
		Trail.Enabled = false
	end
end
function ClientCaster:StartDebug()
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
	ClientCast.InitiatedCasters[self] = {}

	if self._Debug then
		self:StartDebug()
	end
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
	end

	for _, Descendant in next, Object:GetDescendants() do
		self._OnDamagePointAdded(Descendant)
	end

	self._DescendantConnection = Object.DescendantAdded:Connect(self._OnDamagePointAdded)
end
function ClientCaster:Destroy()
	self.Disabled = true
	ClientCast.InitiatedCasters[self] = nil

	self._DescendantConnection:Disconnect()

	for _, EventsHolder in next, self._CollidedEvents do
		for Event in next, EventsHolder do
			Event:Destroy()
		end
	end
	for _, DebugAttachment in next, self._DebugTrails do
		DebugAttachment:Destroy()
	end
end
function ClientCaster:Stop()
	self.Disabled = true
	ClientCast.InitiatedCasters[self] = nil

	local DescendantConnection = self._DescendantConnection
	if DescendantConnection then
		DescendantConnection:Disconnect()
		self._DescendantConnection = nil
	end

	local LocalizedState = self._Debug
	self:DisableDebug()
	self._Debug = LocalizedState
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
	AssertType(Object, "Instance", "Unexpected argument #1 to 'CastObject.new' (%s expected, got %s)")
	local CasterObject

	local DebugTrails = {}
	local DamagePoints = {}

	local function OnDamagePointAdded(Attachment)
		if Attachment.ClassName == "Attachment" and Attachment.Name == Settings.AttachmentName and not DamagePoints[Attachment] then
			local DirectChild = Attachment.Parent == CasterObject.Object
			DamagePoints[Attachment] = DirectChild

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
	CasterObject = setmetatable({
		RaycastParams = RaycastParameters,
		Object = Object,
		Disabled = true,
		Recursive = false,

		_CollidedEvents = {
			Humanoid = {},
			Any = {}
		},
		_DamagePoints = DamagePoints,
		_Debug = false,
		_ToClean = {},
		_DebugTrails = DebugTrails,
		_OnDamagePointAdded = OnDamagePointAdded
	}, ClientCaster)

	for _, Descendant in next, Object:GetDescendants() do
		OnDamagePointAdded(Descendant)
	end

	CasterObject._DescendantConnection = Object.DescendantAdded:Connect(OnDamagePointAdded)
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
		if Key == "FilterType" then
			Value = Enum.RaycastFilterType[Value]
		end
		Params[Key] = Value
	end

	return Params
end
local function UpdateCasterEvents(RaycastResult)
	if RaycastResult then
		ReplicationRemote:FireServer("Any", SerializeResult(RaycastResult))

		local ModelAncestor = RaycastResult.Instance:FindFirstAncestorOfClass("Model")
		local Humanoid = ModelAncestor and ModelAncestor:FindFirstChildOfClass("Humanoid")
		if Humanoid then
			ReplicationRemote:FireServer("Humanoid", SerializeResult(RaycastResult))
		end
	end
end
local function UpdateAttachment(Attachment, Caster, LastPositions)
	local CurrentPosition = Attachment.WorldPosition
	local LastPosition = LastPositions[Attachment] or CurrentPosition

	if CurrentPosition ~= LastPosition then
		local RaycastResult = workspace:Raycast(CurrentPosition, LastPosition - CurrentPosition, Caster.RaycastParams)

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

		local RecursiveCaster = Caster.Recursive

		for Attachment, DirectChild in next, Caster._DamagePoints do
			if DirectChild or RecursiveCaster then
				UpdateAttachment(Attachment, Caster, LastPositions)
			end
		end
	end
end)

local function CreateCaster(Data)
	local Caster = ClientCast.new(Data.Object, DeserializeParams(Data.RaycastParams))

	ClientCasters[Data.Id] = Caster
	Caster._Debug = Data.Debug

	return Caster
end

ReplicationRemote.OnClientEvent:Connect(function(Status, Data, AdditionalData)
	if Status == "Start" then
		local Caster = ClientCasters[Data.Id] or CreateCaster(Data)
		Caster:Start()
	elseif Status == "Destroy" then
		local Caster = ClientCasters[Data.Id]

		if Caster then
			Caster:Destroy()
			Caster = nil
			ClientCasters[Data.Id] = nil
		end
	elseif Status == "Stop" then
		local Caster = ClientCasters[Data.Id]

		if Caster then
			Caster:Stop()
		end
	elseif Status == "Update" then
		local Caster = ClientCasters[Data.Id] or CreateCaster(Data)

		for Name, Value in next, AdditionalData do
			if Name == "Object" then
				Caster:SetObject(Value)
			elseif Name == "Debug" then
				Caster[(Value and "Start" or "Disable") .. "Debug"](Caster)
			else
				Caster[Name] = Value
			end
		end
	end
end)