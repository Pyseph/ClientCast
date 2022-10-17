local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

local ToggleUI = Instance.new("ScreenGui")

local ToggleButton = Instance.new("TextButton")
ToggleButton.Size = UDim2.new(0, 100, 0, 50)
ToggleButton.Position = UDim2.new(0, 0, 0, 0)
ToggleButton.Text = "Toggle"
ToggleButton.TextColor3 = Color3.new(1, 0, 0)
ToggleButton.TextScaled = true
ToggleButton.Parent = ToggleUI

ToggleUI.Parent = PlayerGui

local Remote = ReplicatedStorage:WaitForChild("RemoteEvent")
local Enabled = false
ToggleButton.MouseButton1Click:Connect(function()
	Enabled = not Enabled
	ToggleButton.TextColor3 = Enabled and Color3.new(0, 1, 0) or Color3.new(1, 0, 0)
	Remote:FireServer()
end)