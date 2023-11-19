local RunService = game:GetService("RunService")

local SharedFolder = script.Parent.Parent.shared

local Settings = require(SharedFolder.Settings)
local CasterHitbox = require(SharedFolder.CasterHitbox)
local CasterBase = require(SharedFolder.CasterBase)

local CasterClient = {}
CasterClient.__index = CasterClient

function CasterClient:StartDebug()
	self.Debugger:Start(self._Attachments)
end
function CasterClient:StopDebug()
	self.Debugger:Stop()
end

function CasterClient:Start()
	self.Active = true

	self._HitboxUpdateConnection = RunService.Heartbeat:Connect(function()
		self._Hitbox:Update()
	end)
end
function CasterClient:Stop()
	self.Active = false
	self._Hitbox:Stop()
	self._HitboxUpdateConnection:Disconnect()
	if self.Debugger.Active then
		self:StopDebug()
	end
end

function CasterClient.new(Object, RaycastParams, CasterId)
	local Caster = setmetatable(CasterBase.new(Object, RaycastParams, CasterId), CasterClient)
	Caster._Hitbox = CasterHitbox.new(Caster)

	return Caster
end

return CasterClient