local SharedFolder = script.Parent

local Settings = require(SharedFolder.Settings)
local CasterHitbox = require(SharedFolder.CasterHitbox)
local CasterBase = require(SharedFolder.CasterBase)

local CasterClient = {}
CasterClient.__index = CasterClient

function CasterClient.new(Object, RaycastParameters, CasterId)
	local Caster = setmetatable(CasterBase.new(Object, RaycastParameters, CasterId), CasterClient)
	Caster._Hitbox = CasterHitbox.new(Caster)

	return Caster
end

return CasterClient