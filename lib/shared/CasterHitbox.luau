local CasterHitbox = {}
CasterHitbox.__index = CasterHitbox

local function UpdateCasterEvents(Caster, RaycastResult)
	if RaycastResult then
		Caster:_Collided(RaycastResult)

		local ModelAncestor = RaycastResult.Instance:FindFirstAncestorOfClass("Model")
		local Humanoid = ModelAncestor and ModelAncestor:FindFirstChildOfClass("Humanoid")
		if Humanoid then
			Caster:_HumanoidCollided(RaycastResult, Humanoid)
		end
	end
end

local function Raycast(StartPosition, Direction, Caster)
	local RaycastParams = Caster.RaycastParams
	local RaycastResult = workspace:Raycast(StartPosition, Direction, RaycastParams)

	return RaycastResult
end
local function UpdateAttachment(Attachment, Caster, LastAttachmentPositions)
	local CurrentPosition = Attachment.WorldPosition
	local LastPosition = LastAttachmentPositions[Attachment] or CurrentPosition

	if CurrentPosition ~= LastPosition then
		local Direction = CurrentPosition - LastPosition
		local RaycastResult = Raycast(LastPosition, Direction, Caster)

		UpdateCasterEvents(Caster, RaycastResult)
	end

	LastAttachmentPositions[Attachment] = CurrentPosition
end

function CasterHitbox:Update()
	local Caster = self.Caster
	local Object = Caster.Object
	if not Object then
		return
	end

	local RecursiveCaster = Caster.Recursive

	local LastAttachmentPositions = self._LastAttachmentPositions

	for Attachment, DirectChild in Caster._Attachments do
		if DirectChild or RecursiveCaster then
			UpdateAttachment(Attachment, Caster, LastAttachmentPositions)
		end
	end
end
function CasterHitbox:Stop()
	table.clear(self._LastAttachmentPositions)
end
function CasterHitbox:Destroy()
	self:Stop()
end

function CasterHitbox.new(Caster)
	local Hitbox = setmetatable({
		Caster = Caster,
		_LastAttachmentPositions = {},
	}, CasterHitbox)

	return Hitbox
end

return CasterHitbox