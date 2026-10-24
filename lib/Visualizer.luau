--!strict
-- Draws casts on the machine that casts them: sweeps in red, sweeps that hit in green, and a cross with the target's
-- name where each hit landed. Everything fades out over Lifetime seconds.
local Workspace = game:GetService("Workspace")

local Visualizer = {
	Enabled = false, -- draw every caster on this machine, not only the ones with Debug on
	Lifetime = 1,
	SweepColor = Color3.fromRGB(255, 70, 70),
	HitColor = Color3.fromRGB(70, 255, 130),
}

-- Each fade step and colour gets its own adornment, set up once, so drawing never changes a property
local Shades = 4
local Capacity = 4096 -- lines kept at most; the oldest go first

local From: { Vector3 } = {}
local To: { Vector3 } = {}
local Born: { number } = {}
local Hits: { boolean } = {}
local First, Count = 1, 0
local Marks: { { Position: Vector3, Normal: Vector3, Label: string, Born: number } } = {}

local Canvases: { WireframeHandleAdornment }? = nil
local Buckets: { { Vector3 } } = {}
local Drawn = false

for Index = 1, Shades * 2 do
	Buckets[Index] = {}
end

local function Create(): { WireframeHandleAdornment }
	local List = {}
	for Index = 1, Shades * 2 do
		local Canvas = Instance.new("WireframeHandleAdornment")
		Canvas.Name = "ClientCastDebug"
		Canvas.Adornee = Workspace.Terrain
		Canvas.AlwaysOnTop = true
		Canvas.AdornCullingMode = Enum.AdornCullingMode.Never
		Canvas.Color3 = if Index > Shades then Visualizer.HitColor else Visualizer.SweepColor
		Canvas.Transparency = (Index - 1) % Shades / Shades
		Canvas.Parent = Workspace.Terrain
		List[Index] = Canvas
	end
	return List
end

local function Line(A: Vector3, B: Vector3, Hit: boolean)
	local Index = (First + Count - 1) % Capacity + 1
	if Count == Capacity then
		First = First % Capacity + 1
	else
		Count += 1
	end
	From[Index], To[Index], Born[Index], Hits[Index] = A, B, os.clock(), Hit
end

-- A point's sweep; sphere sweeps get a cross at the end as wide as the sphere
function Visualizer.Sweep(A: Vector3, B: Vector3, Radius: number, Hit: boolean)
	Line(A, B, Hit)
	if Radius > 0 then
		Line(B - Vector3.xAxis * Radius, B + Vector3.xAxis * Radius, Hit)
		Line(B - Vector3.yAxis * Radius, B + Vector3.yAxis * Radius, Hit)
		Line(B - Vector3.zAxis * Radius, B + Vector3.zAxis * Radius, Hit)
	end
end

-- A part that swept its own shape, drawn as its box where it ended up
local Axes = { 1, 2, 4 }
function Visualizer.Box(At: CFrame, Size: Vector3, Hit: boolean)
	local Corners = {}
	for Index = 0, 7 do
		local Sign = Vector3.new(Index % 2 * 2 - 1, Index // 2 % 2 * 2 - 1, Index // 4 * 2 - 1)
		Corners[Index] = At * (Size / 2 * Sign)
	end
	for Index = 0, 7 do
		for _, Axis in Axes do
			if Index // Axis % 2 == 0 then
				Line(Corners[Index], Corners[Index + Axis], Hit)
			end
		end
	end
end

function Visualizer.Mark(Position: Vector3, Normal: Vector3, Label: string)
	table.insert(Marks, { Position = Position, Normal = Normal, Label = Label, Born = os.clock() })
end

-- Called once a frame, after the casters stepped
function Visualizer.Render()
	local Now, Lifetime = os.clock(), Visualizer.Lifetime
	while Count > 0 and Now - Born[First] > Lifetime do
		First = First % Capacity + 1
		Count -= 1
	end
	while Marks[1] and Now - Marks[1].Born > Lifetime do
		table.remove(Marks, 1)
	end
	if Count == 0 and #Marks == 0 then
		if Drawn and Canvases then
			for _, Canvas in Canvases do
				Canvas:Clear()
			end
			Drawn = false
		end
		return
	end

	local List: { WireframeHandleAdornment } = Canvases or Create()
	Canvases = List
	for _, Bucket in Buckets do
		table.clear(Bucket)
	end
	local Index = First
	for _ = 1, Count do
		local Shade = math.min(Shades, (Now - Born[Index]) * Shades // Lifetime + 1)
		local Bucket = Buckets[if Hits[Index] then Shade + Shades else Shade]
		table.insert(Bucket, From[Index])
		table.insert(Bucket, To[Index])
		Index = Index % Capacity + 1
	end
	for Bucket, Canvas in List do
		Canvas:Clear()
		if #Buckets[Bucket] > 0 then
			Canvas:AddLines(Buckets[Bucket])
		end
	end

	local Canvas = List[Shades + 1]
	for _, Mark in Marks do
		local At = Mark.Position
		Canvas:AddLines({
			At - Vector3.xAxis * 0.3,
			At + Vector3.xAxis * 0.3,
			At - Vector3.yAxis * 0.3,
			At + Vector3.yAxis * 0.3,
			At - Vector3.zAxis * 0.3,
			At + Vector3.zAxis * 0.3,
			At,
			At + Mark.Normal,
		})
		Canvas:AddText(At + Vector3.yAxis * 0.6, Mark.Label, 14)
	end
	Drawn = true
end

return Visualizer
