--!strict
--[[
	How a caster casts on this machine. Sweep.new finds the caster's points and returns what sweeps them every frame,
	each from where it was last frame to where it is now; casters make a fresh one on every Start.

	A part with no points sweeps its own shape. A sweep that hits a humanoid goes on past it, the rest of the
	activation's casts leave it out, and anything else stops the sweep.
]]
local Workspace = game:GetService("Workspace")

local Filter = require(script.Parent.Filter)
local Visualizer = require(script.Parent.Visualizer)

local MaxStep = 100 -- longer sweeps are teleports or removed points, not swings
local Pierce = 4 -- how many humanoids one sweep goes through in a frame

local Sweep = {}
local Warned: { [Instance]: true } = setmetatable({}, { __mode = "k" }) :: any

-- The humanoid a part belongs to and the model that holds it
function Sweep.Resolve(Part: Instance): (Humanoid?, Model?)
	local Model = if Part:IsA("Model") then Part else Part:FindFirstAncestorOfClass("Model")
	while Model do
		local Humanoid = Model:FindFirstChildOfClass("Humanoid")
		if Humanoid then
			return Humanoid, Model :: Model
		end
		Model = Model:FindFirstAncestorOfClass("Model")
	end
	return nil, nil
end

-- Shapecast can't start from a given CFrame on every engine yet, so until it can, anything but a ball sweeps as its box
local ShapecastFrom: boolean? = nil
local function Shapecast(Part: BasePart, From: CFrame, Delta: Vector3, Params: RaycastParams): RaycastResult?
	local Shape = if Part:IsA("Part") then (Part :: Part).Shape else nil
	if Shape == Enum.PartType.Ball then
		return Workspace:Spherecast(From.Position, Part.Size.X / 2, Delta, Params)
	elseif Shape ~= Enum.PartType.Block and ShapecastFrom ~= false then
		local Ok, Result = pcall((Workspace :: any).Shapecast, Workspace, Part, Delta, Params, From)
		ShapecastFrom = Ok
		if Ok then
			return Result
		end
	end
	return Workspace:Blockcast(From, Part.Size, Delta, Params)
end

local function Idle() end

-- Returns the caster's sweep. It reads the caster's Object, Points, Radius, Debug, Active, _Filter and _Targets, and
-- hands hits to its _Register, which returns a newly hit humanoid's model for the sweep to go through.
function Sweep.new(Caster: any): () -> ()
	local Object: Instance? = Caster.Object
	if not Object then
		return Idle -- a copy whose object hasn't streamed in yet
	end
	local Points, Radii, Bones, Last = {}, {}, {}, {}
	for _, Point in Object:QueryDescendants(`Attachment#{Caster.Points}, Attachment.{Caster.Points}`) do
		local Radius = Point:GetAttribute("Radius")
		table.insert(Points, Point :: Attachment)
		table.insert(Radii, if type(Radius) == "number" then Radius else Caster.Radius)
		table.insert(Bones, Point:IsA("Bone"))
	end
	local Shape = if #Points == 0 and Object:IsA("BasePart") then Object else nil
	if #Points == 0 and not Shape then
		if not Warned[Object] then
			Warned[Object] = true
			warn(`ClientCast: {Object:GetFullName()} has no {Caster.Points} attachments or bones to cast from`)
		end
		return Idle
	end

	-- The casts leave out the object, whoever holds it and the humanoids this activation already hit
	local Exclude = table.clone(Caster._Filter.Exclude)
	local _, Holder = Sweep.Resolve(Object)
	table.insert(Exclude, Object)
	if Holder then
		table.insert(Exclude, Holder)
	end
	for Target in Caster._Targets do
		if Target:IsA("Model") then
			table.insert(Exclude, Target)
		end
	end
	local Params: any = Filter.Build(Caster._Filter, Exclude)

	-- Counts a cast's hit. Returns whether the sweep goes on past it.
	local function Hit(Result: RaycastResult, Point: Attachment?): boolean
		local Through = Caster:_Register(Result.Instance, Result.Position, Result.Normal, Result.Material, Point)
		if Through then
			table.insert(Exclude, Through)
			Params.ExcludeInstances = Exclude
		end
		return Through ~= nil and Caster.Active
	end

	local From: CFrame? = nil
	return function()
		local Draw = Caster.Debug or Visualizer.Enabled
		for Index, Point in Points do
			local Position = if Bones[Index]
				then (Point :: Bone).TransformedWorldCFrame.Position
				else Point.WorldPosition
			local Start = Last[Index]
			Last[Index] = Position
			local Length = if Start then (Position - Start).Magnitude else 0
			if Start and Length > 0 and Length < MaxStep then
				local Radius = Radii[Index]
				for _ = 1, Pierce do
					local Delta = Position - Start
					local Result = if Radius > 0
						then Workspace:Spherecast(Start, Radius, Delta, Params)
						else Workspace:Raycast(Start, Delta, Params)
					if Draw then
						Visualizer.Sweep(Start, Position, Radius, Result ~= nil)
					end
					if not (Result and Hit(Result, Point)) then
						break
					end
					Start += Delta.Unit * Result.Distance
				end
				if not Caster.Active then
					return -- a Hit handler stopped it
				end
			end
		end

		if Shape then
			local At, Start = Shape.CFrame, From
			From = At
			local Length = if Start then (At.Position - Start.Position).Magnitude else 0
			if Start and Length > 0 and Length < MaxStep then
				for _ = 1, Pierce do
					local Delta = At.Position - Start.Position
					local Result = Shapecast(Shape, Start, Delta, Params)
					if Draw then
						Visualizer.Box(At, Shape.Size, Result ~= nil)
					end
					if not (Result and Hit(Result, nil)) then
						break
					end
					Start += Delta.Unit * Result.Distance
				end
			end
		end
	end
end

return Sweep
