## Table of Contents
- [Introduction](https://pysephwasntavailable.github.io/ClientCast#introduction)
- [Example Usage](https://pysephwasntavailable.github.io/ClientCast#example-usage)
- [Setup](https://pysephwasntavailable.github.io/ClientCast#setup)
- [Links](https://pysephwasntavailable.github.io/ClientCast#links)

## Introduction
ClientCast is a simple and elegant solution to handling weapon hitboxes. This module is written with efficiency, simplicity and customizability in mind. This module is meant to be bareboned. ClientCast relies solely on raycasts to provide with hitbox data, and as such is not only extremely efficient, but also provides detailed information on where and when it hit an object. If you would like to get extra data or add your own functions, the best solution would be to simply wrap the object and add your own methods onto it.

The main forte of ClientCast lies in the fact that you can easily communicate with the client, letting the client handle all the calculations and then have the server be notified whenever the client intersects something. This allows the server to have to calculate way less and also take into account for a player's ping or delay, providing all players a lag-free experience.

## Example Usage
### Making a part kill players
Simply parent the ClientCast folder to ServerStorage and run this script on the server:
```lua
local ClientCast = require(game.ServerStorage.ClientCast)

local KillPart = Instance.new('Part')
KillPart.Anchored = true
KillPart.CanCollide = false
KillPart.CFrame = CFrame.new(0, 1, 0)
KillPart.Parent = workspace

function GenerateAttachment(Position)
	local Attachment = Instance.new('Attachment')
	Attachment.Name = 'DmgPoint'
	Attachment.Position = Position
	Attachment.Parent = KillPart
end

for X = -2, 2 do
	GenerateAttachment(Vector3.new(X, Y, Z))
end

local ClientCaster = ClientCast.new(KillPart, RaycastParams.new())
local Debounce = {}
ClientCaster.HumanoidCollided:Connect(function(RaycastResult, HitHumanoid)
	if Debounce[HitHumanoid] then
		return
	end
	Debounce[HitHumanoid] = true
	print('Ow!')
	HitHumanoid:TakeDamage(10)
	
	wait(0.5)
	Debounce[HitHumanoid] = false
end)
ClientCaster:Start()
```
### Note: This will not work until the part starts moving around.
[![asciicast](https://cdn.discordapp.com/attachments/623866531138371612/781248496979804220/unknown.png)](https://cdn.discordapp.com/attachments/623866531138371612/781247798589915166/bqa6Y6hmbN.mp4)

## Setup

To start using this module, simply put attachments called ``DmgPoint`` (name is customizable in the ``Settings`` table at the top of the ``ClientCast`` ModuleScript) inside the object, and then create a ClientCaster object, with it's ``Object`` set to your hitbox.
Example:
```lua
-- Call module
local ClientCast = require(PATH.ClientCast)
-- Create ClientCaster object
local Caster = ClientCast.new(workspace.Part, RaycastParams.new())

-- Connect callback to 'Collided' event
Caster.Collided:Connect(print)
-- Set owner of ClientCaster, who will be the one to calculate collisions.
-- You can skip this if you want the server to be the owner.
Caster:SetOwner(Player)
-- Start detecting collisions
Caster:Start()
```

## Links

- [Example Usage](https://pysephwasntavailable.github.io/ClientCast#example-usage)
- [Setup](https://pysephwasntavailable.github.io/ClientCast#setup)
- [ClientCast API](https://pysephwasntavailable.github.io/ClientCast/api/ClientCast)