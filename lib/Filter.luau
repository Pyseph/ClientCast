--!strict
-- RaycastParams can't go through a remote, so a caster keeps its filter as a plain table and builds the params from
-- it where the casts run. The older FilterDescendantsInstances list is folded into the exclude or include list.

export type Filter = {
	Exclude: { Instance },
	Include: { Instance }?,
	[string]: any, -- the copied fields below
}

-- Copied as they are. Margin and SizeGradient only exist on newer engines, which is why every copy is guarded.
local Fields = { "IgnoreWater", "CollisionGroup", "RespectCanCollide", "BruteForceAllSlow", "Margin", "SizeGradient" }

local function Join(List: { Instance }?, More: { Instance }?): { Instance }?
	if not (List and More) then
		return List or More
	end
	local Joined = table.clone(List)
	table.move(More, 1, #More, #Joined + 1, Joined)
	return Joined
end

local Filter = {}

function Filter.From(Params: RaycastParams?): Filter
	local Copy: Filter = { Exclude = {} }
	if Params then
		for _, Field in Fields do
			pcall(function()
				Copy[Field] = (Params :: any)[Field]
			end)
		end
		local Legacy = Params.FilterDescendantsInstances
		local Including = Params.FilterType == Enum.RaycastFilterType.Include
		Copy.Exclude = Join(if Including then nil else Legacy, (Params :: any).ExcludeInstances) or {}
		Copy.Include = Join(if Including then Legacy else nil, (Params :: any).IncludeInstances)
	end
	return Copy
end

function Filter.Build(Copy: Filter, Exclude: { Instance }): RaycastParams
	local Params = RaycastParams.new()
	for _, Field in Fields do
		if Copy[Field] ~= nil then
			pcall(function()
				(Params :: any)[Field] = Copy[Field]
			end)
		end
	end
	local Raw: any = Params
	Raw.IncludeInstances = Copy.Include
	Raw.ExcludeInstances = Exclude
	return Params
end

return Filter
