return function(ClientCast)
	local StarterPlayer = game:GetService('StarterPlayer')
	local ReplicatedStorage = game:GetService('ReplicatedStorage')
	local ReplicatedFirst = game:GetService('ReplicatedFirst')
	local Players = game:GetService('Players')

	local ReplicationRemote = Instance.new('RemoteEvent')
	ReplicationRemote.Name = 'ClientCast-Replication'
	ReplicationRemote.Parent = ReplicatedStorage

	local ScriptsHolder = script.Parent
	local ClientHandler = ScriptsHolder.ClientHandler

	local function CloneHandler()
		local Cloned = ClientHandler:Clone()
		ScriptsHolder.Maid:Clone().Parent = Cloned
		ScriptsHolder.Connection:Clone().Parent = Cloned

		return Cloned
	end
	CloneHandler().Parent = StarterPlayer:FindFirstChildOfClass('StarterPlayerScripts')

	for Idx, Player in next, Players:GetPlayers() do
		CloneHandler().Parent = Player:FindFirstChildOfClass('PlayerGui')
	end
end
