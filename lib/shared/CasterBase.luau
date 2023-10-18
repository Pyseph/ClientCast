local RunService = game:GetService("RunService")

local SharedFolder = script.Parent
local Settings = require(SharedFolder.Settings)

local Module = {}
Module.ActiveCasters = {}

local CasterBase = {}
CasterBase.__index = CasterBase

function CasterBase:StartDebug()

end
function CasterBase:StopDebug()

end
function CasterBase:Start()

end
function CasterBase:Stop()

end
function CasterBase:SetObject()

end
function CasterBase:Destroy()

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
	}, CasterBase)
	AddAttachments(Caster)
end

return Module