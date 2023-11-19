local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local TestingPlayer = Players:GetPlayers()[1] or Players.PlayerAdded:Wait()

local ClientCast = require(ReplicatedStorage.ClientCast):: {}

local KillPart = Instance.new("Part")
KillPart.Anchored = true
KillPart.CanCollide = false
KillPart.CFrame = CFrame.new(0, 1, 0)
KillPart.Parent = workspace

local function GenerateAttachment(Position)
    local Attachment = Instance.new("Attachment")
    Attachment.Name = "DmgPoint"
    Attachment.Position = Position
    Attachment.Parent = KillPart
end

for X = -2, 2 do
    GenerateAttachment(Vector3.new(X, 0, 0))
end

local ClientCaster = ClientCast.new(KillPart, RaycastParams.new(), TestingPlayer)

local Debounce = {}
ClientCaster.HumanoidCollided:Connect(function(_, HitHumanoid)
    if Debounce[HitHumanoid] then
        return
    end
    Debounce[HitHumanoid] = true
    print("Ow!")
    HitHumanoid:TakeDamage(10)

    wait(0.5)
    Debounce[HitHumanoid] = false
end)
ClientCaster:Start()
ClientCaster:StartDebug()