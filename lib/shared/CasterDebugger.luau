local SharedFolder = script.Parent
local Settings = require(SharedFolder.Settings)

local CasterDebugger = {}
CasterDebugger.__index = CasterDebugger

function CasterDebugger:Start(Attachments)
	self.Active = true
	for Attachment in Attachments do
		local Trail = Instance.new("Trail")
		local TrailAttachment = Instance.new("Attachment")

		TrailAttachment.Name = Settings.DebugAttachmentName
		TrailAttachment.Position = Attachment.Position - Vector3.new(0, 0, Settings.DebugLineThickness)

		Trail.Color = ColorSequence.new(Settings.DebugColor)
		Trail.LightEmission = 1
		Trail.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.5, 0),
			NumberSequenceKeypoint.new(1, 1),
		})
		Trail.FaceCamera = true
		Trail.Lifetime = Settings.DebugLifetime

		Trail.Attachment0 = Attachment
		Trail.Attachment1 = TrailAttachment

		Trail.Parent = TrailAttachment
		TrailAttachment.Parent = Attachment.Parent

		self.DebugLines[Attachment] = Trail
	end
end
function CasterDebugger:Stop()
	self.Active = false
	for Attachment, Trail in self.DebugLines do
		Trail.Attachment1:Destroy()
		Trail:Destroy()
		self.DebugLines[Attachment] = nil
	end

	table.clear(self.DebugLines)
end

function CasterDebugger.new()
	local Debugger = setmetatable({
		Active = false,
		DebugLines = {},
	}, CasterDebugger)

	return Debugger
end

return CasterDebugger