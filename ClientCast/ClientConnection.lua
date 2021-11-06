return function()
	local StarterPlayer = game:GetService("StarterPlayer")
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local Players = game:GetService("Players")

	local function InitRemote(Class, Name)
		local Remote = Instance.new(Class)
		Remote.Name = "ClientCast-" .. Name
		Remote.Parent = ReplicatedStorage
	end
	InitRemote("RemoteEvent", "Replication")
	InitRemote("RemoteFunction", "Ping")

	local ScriptsHolder = script.Parent
	local ClientHandler = ScriptsHolder.ClientHandler

	local function CloneHandler(Parent)
		local ClonedHandler = ClientHandler:Clone()
		ScriptsHolder.Signal:Clone().Parent = ClonedHandler

		ClonedHandler.Parent = Parent
	end
	CloneHandler(StarterPlayer:FindFirstChildOfClass("StarterPlayerScripts"))

	for _, Player in next, Players:GetPlayers() do
		CloneHandler(Player:FindFirstChildOfClass("PlayerGui"))
	end
end