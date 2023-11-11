local RunService = game:GetService("RunService")

local SharedFolder = script.Parent

local Settings = require(SharedFolder.Settings)
local CasterDebugger = require(SharedFolder.CasterDebugger)

local Module = {}
Module.ActiveCasters = {}

local CasterBase = {}
CasterBase.__index = CasterBase

function CasterBase:StartDebug()
	error("CasterBase:StartDebug() must be overridden")
	--self.Debugger:Start(self._Attachments)
end
function CasterBase:StopDebug()
	error("CasterBase:StopDebug() must be overridden")
	--self.Debugger:Stop()
end
function CasterBase:Start()
	error("CasterBase:Start() must be overridden")
end
function CasterBase:Stop()
	error("CasterBase:Stop() must be overridden")
end
function CasterBase:SetObject()
	error("CasterBase:SetObject() must be overridden")
end
function CasterBase:Destroy()
	self.Debugger:Stop()
end

function CasterBase:_Collided(RaycastResult)
	error("CasterBase:_Collided() must be overridden")
end
function CasterBase:_HumanoidCollided(Humanoid, RaycastResult)
	error("CasterBase:_HumanoidCollided() must be overridden")
end

local function AddAttachments(Caster)
	for _, Attachment in Caster.Object:GetDescendants() do
		if Attachment:IsA("Attachment") and Attachment.Name == Settings.AttachmentName then
			Caster._Attachments[Attachment] = true
		end
	end
end
function CasterBase.new(Object, RaycastParameters, CasterId)
	local Caster = setmetatable({
		Object = Object,
		RaycastParameters = RaycastParameters,
		Id = CasterId,
		_Attachments = {},
		_Hitbox = nil,
		Debugger = CasterDebugger.new(),
	}, CasterBase)
	AddAttachments(Caster)
end

return Module