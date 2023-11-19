local SharedFolder = script.Parent

local Settings = require(SharedFolder.Settings)
local CasterDebugger = require(SharedFolder.CasterDebugger)

local CasterBase = {}
CasterBase.__index = CasterBase

--[[
function CasterBase:StartDebug()
	self.Debugger:Start(self._Attachments)
end
function CasterBase:StopDebug()
	self.Debugger:Stop()
end
function CasterBase:Start()

end
function CasterBase:Stop()

end
function CasterBase:SetObject()

end
function CasterBase:Destroy()
	self.Debugger:Stop()
end

function CasterBase:_Collided(RaycastResult)

end
function CasterBase:_HumanoidCollided(Humanoid, RaycastResult)

end
]]

local function AddAttachments(Caster)
	for _, Attachment in Caster.Object:GetDescendants() do
		if Attachment:IsA("Attachment") and Attachment.Name == Settings.AttachmentName then
			Caster._Attachments[Attachment] = Caster.Object == Attachment.Parent
		end
	end
end
function CasterBase.new(Object, RaycastParams, CasterId)
	local Caster = setmetatable({
		Object = Object,
		RaycastParams = RaycastParams,
		Recursive = false,
		Debug = false,
		Owner = nil,
		Id = CasterId,
		Debugger = CasterDebugger.new(),
		_Attachments = {},
	}, CasterBase)
	AddAttachments(Caster)

	return Caster
end

return CasterBase