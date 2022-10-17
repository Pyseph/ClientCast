local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ClientCast = require(ReplicatedStorage.ClientCast)

local RemoteEvent = Instance.new("RemoteEvent")
RemoteEvent.Parent = ReplicatedStorage

local TestPart = Instance.new("Part")
TestPart.Anchored = true
TestPart.CanCollide = false
TestPart.CFrame = CFrame.new(0, 2, 0)
TestPart.Parent = workspace

for X = -2, 2 do
    local Attachment = Instance.new("Attachment")
    Attachment.Name = "DmgPoint"
    Attachment.Position = Vector3.new(X, 0, 0)
    Attachment.Parent = TestPart
end

local Table = {} -- Player = Caster

local function StartCasting(Player)
	local CurrentCaster = Table[Player]
	if CurrentCaster.Disabled then
		CurrentCaster:Start()
	else
		CurrentCaster:Stop()
	end
end

Players.PlayerAdded:Connect(function(Player)
	Player.CharacterAdded:Connect(function(Character)
		local Humanoid = Character:WaitForChild("Humanoid", 1)

		local ClientCaster = ClientCast.new(TestPart, RaycastParams.new())
		ClientCaster:SetOwner(Player)
		ClientCaster._Debug = true

		ClientCaster.HumanoidCollided:Connect(function(_, HitHumanoid)
			print("Hit model:" .. HitHumanoid.Parent.Name)
		end)

		Table[Player] = ClientCaster

		Humanoid.Died:Connect(function()
			ClientCaster:Destroy()
			Table[Player] = nil
		end)
	end)
end)

RemoteEvent.OnServerEvent:Connect(StartCasting)