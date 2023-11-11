local Module = {}

local function UpdateCasterEvents(Caster, RaycastResult)
	if RaycastResult then
		Caster:_Collided(RaycastResult)

		local ModelAncestor = RaycastResult.Instance:FindFirstAncestorOfClass("Model")
		local Humanoid = ModelAncestor and ModelAncestor:FindFirstChildOfClass("Humanoid")
		if Humanoid then
			Caster:_HumanoidCollided(Humanoid, RaycastResult)
		end
	end
end

local function Raycast(StartPosition, Direction, Caster)
	local RaycastParameters = Caster.RaycastParameters
	local RaycastResult = workspace:Raycast(StartPosition, Direction, RaycastParameters)

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

function Module.UpdateCaster(Caster, LastAttachmentPositions)
	local Object = Caster.Object
	if not Object then
		return
	end

	local RecursiveCaster = Caster.Recursive

	for Attachment, DirectChild in Caster._DamagePoints do
		if DirectChild or RecursiveCaster then
			UpdateAttachment(Attachment, Caster, LastAttachmentPositions)
		end
	end
end

return Module