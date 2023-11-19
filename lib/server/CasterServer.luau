local RunService = game:GetService("RunService")

local Library = script.Parent.Parent
local Packages = Library.Packages
local SharedFolder = Library.shared

local Settings = require(SharedFolder.Settings)
local CasterHitbox = require(SharedFolder.CasterHitbox)
local CasterBase = require(SharedFolder.CasterBase)
local ReplicationBridge = require(SharedFolder.ReplicationBridge)

local Signal = require(Packages.Signal)

local CasterServer = {}
CasterServer.__index = CasterServer

function CasterServer:SetObject()

end
function CasterServer:Destroy()
	self.Debugger:Stop()
	self._ReplicationBridge:Destroy()
	self._Hitbox:Destroy()
end

function CasterServer:StartDebug()
	self.Debugger:Start(self._Attachments)
end
function CasterServer:StopDebug()
	self.Debugger:Stop()
end

function CasterServer:Start()
	self.Active = true

	self._HitboxUpdateConnection = RunService.Heartbeat:Connect(function()
		self._Hitbox:Update()
	end)
end
function CasterServer:Stop()
	self.Active = false
	self._Hitbox:Stop()
	self._HitboxUpdateConnection:Disconnect()
	if self.Debugger.Active then
		self:StopDebug()
	end
end

function CasterServer:SetOwner(Player: Player?)
	self.Owner = Player
	self._ReplicationBridge:SetOwner(Player)
end

function CasterServer:_Collided(RaycastResult)
	self.Collided:Fire(RaycastResult)
end
function CasterServer:_HumanoidCollided(RaycastResult, Humanoid)
	self.HumanoidCollided:Fire(RaycastResult, Humanoid)
end

local IdCounter = 0
local function GenerateId()
	IdCounter += 1
	return IdCounter
end

function CasterServer.new(Object, RaycastParams, Owner)
	local Caster = setmetatable(CasterBase.new(Object, RaycastParams, GenerateId()), CasterServer)
	Caster._Hitbox = CasterHitbox.new(Caster)
	Caster.Collided = Signal.new()
	Caster.HumanoidCollided = Signal.new()
	--Caster._ReplicationBridge = ReplicationBridge.new(Caster)

	if Owner then
		-- TODO
		--Caster:SetOwner(Owner)
	end

	return Caster
end

return CasterServer