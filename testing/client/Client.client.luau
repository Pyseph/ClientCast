-- Swings this player's sword: the button tells the server, and the client starts its copy of the caster right away
-- and animates the swing itself.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local ClientCast = require(ReplicatedStorage:WaitForChild("ClientCast"))
local Swing = ReplicatedStorage:WaitForChild("Swing")
local Player = Players.LocalPlayer

local Gui = Instance.new("ScreenGui")
Gui.ResetOnSpawn = false
local Button = Instance.new("TextButton")
Button.Size = UDim2.fromOffset(120, 48)
Button.Position = UDim2.new(0.5, -60, 1, -80)
Button.Text = "Swing"
Button.TextScaled = true
Button.Parent = Gui
Gui.Parent = Player:WaitForChild("PlayerGui")

local Swinging = false
local function SwingSword()
	local Sword = Player.Character and Player.Character:FindFirstChild("Sword")
	local Grip = Sword and Sword:FindFirstChild("Grip")
	if Swinging or not Grip then
		return
	end
	Swinging = true
	Swing:FireServer()
	local Caster = ClientCast.Get(Sword)
	if Caster then
		Caster:Start()
	end
	-- a flat swing from the right to the left, 0.35 seconds long
	local Started = os.clock()
	while os.clock() - Started < 0.35 do
		local Alpha = (os.clock() - Started) / 0.35
		Grip.Transform = CFrame.Angles(0, math.rad(80 - 220 * Alpha), 0)
		RunService.PreSimulation:Wait()
	end
	Grip.Transform = CFrame.identity
	if Caster then
		Caster:Stop()
	end
	task.wait(0.2)
	Swinging = false
end

Button.Activated:Connect(SwingSword)

-- the client's copy fires Hit as soon as its own cast lands, before the server hears of it
local Watched = {}
RunService.Heartbeat:Connect(function()
	local Sword = Player.Character and Player.Character:FindFirstChild("Sword")
	local Caster = Sword and ClientCast.Get(Sword)
	if Caster and not Watched[Caster] then
		Watched[Caster] = true
		Caster.Hit:Connect(function(Hit)
			Button.Text = if Hit.Humanoid then `Hit {Hit.Humanoid.Parent.Name}` else "Swing"
		end)
	end
end)
