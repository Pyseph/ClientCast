--!strict
--[[
	ClientCast: hitboxes that sweep rays, spheres or a part's own shape between frames, and fire Hit once per target.
	A caster made on the server can be given to a player, whose client then computes the hits and sends them back,
	so swings feel right on their screen whatever their ping.

	Keep ClientCast in ReplicatedStorage. Its Client script starts it on every client, so there is nothing to set up
	there. Set the Debug attribute on this module to draw every caster on the machine it's set on.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Caster = require(script.Caster)
local Visualizer = require(script.Visualizer)

export type Caster = Caster.Caster
export type Hit = Caster.Hit
export type Options = Caster.Options

local Remote = script:WaitForChild("Remote") :: RemoteEvent
Caster.Remote = Remote
if not RunService:IsServer() then
	Caster.OwnerError = "only the server can give a caster an Owner"
	Remote.OnClientEvent:Connect(Caster.FromServer)
else
	if not (script:IsDescendantOf(ReplicatedStorage) or script:IsDescendantOf(Workspace)) then
		Caster.OwnerError =
			"clients can't reach ClientCast here, so casters can't have an Owner; put it in ReplicatedStorage"
	end
	Remote.OnServerEvent:Connect(Caster.FromOwner)
end

local function SyncDebug()
	Visualizer.Enabled = script:GetAttribute("Debug") == true
end
script:GetAttributeChangedSignal("Debug"):Connect(SyncDebug)
SyncDebug()

local ClientCast = {}

function ClientCast.new(Object: Instance, Options: Options?): Caster
	if Options and Options.Owner and Caster.OwnerError then
		error(`ClientCast: {Caster.OwnerError}`, 2)
	end
	return Caster.new(Object, Options)
end

-- Finds a caster on Object, optionally the one casting from Points. On a client, this is how the owner gets the copy
-- of a caster the server gave it, to start and stop it right away instead of a round trip later.
function ClientCast.Get(Object: Instance, Points: string?): Caster?
	return Caster.Find(Object, Points)
end

return ClientCast
