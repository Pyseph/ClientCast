# ClientCast

Hitboxes for melee weapons, fists, projectiles and anything else that moves. A caster sweeps rays (or spheres, or a part's own shape) from where its points were last frame to where they are now, and fires `Hit` once for each target it touches.

Make the caster on the server and give it to a player: their client computes the hits, so a swing lands where they saw it land whatever their ping, and the server gets told what was hit.

## Setup

Put the `ClientCast` module in `ReplicatedStorage`. That's all: a script inside it starts ClientCast on every client, and there is no other setup or remote to make.

- **Rojo:** use this repository's `default.project.json` as a nested project, or build a model with `rojo build -o ClientCast.rbxm`.
- **Wally:** the package manifest is in `wally.toml` (`pyseph/clientcast`).

## Example

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ClientCast = require(ReplicatedStorage.ClientCast)

-- in a tool's server script, once the player has it
local Caster = ClientCast.new(Tool.Handle, { Owner = Player })

Caster.Hit:Connect(function(Hit)
	if Hit.Humanoid then
		Hit.Humanoid:TakeDamage(10)
	end
end)

-- on each swing
Caster:Start()
task.wait(0.4)
Caster:Stop()
```

Put attachments named `DmgPoint` in the handle where the blade is; every one sweeps a ray as the handle moves.

## How it casts

- **Points** are the `Attachment`s and `Bone`s under the object that are named `DmgPoint` or tagged `DmgPoint`. Bones follow their animation. Tagging is how you use bones you can't rename.
- With `Radius`, each point sweeps a sphere instead of a ray, so a few points cover a whole blade. A point's own `Radius` attribute overrides it.
- A part with no points sweeps **its own shape**: balls as spheres, everything else as its box (and as its real shape once Roblox enables Shapecast's start position).
- **`Hit` fires once per target per activation**, an activation being one `Start` to its `Stop`. A model with a humanoid is one target, whichever part (or accessory) the cast touched; anything else is its own target.
- Characters that were hit stop blocking: later sweeps go through them, so one swing cuts through a crowd. Walls and other parts still block.
- Casts always leave out the object itself and the model holding it, so a sword never hits its wielder.
- Points are found again on every `Start`, so you can add or remove them between swings.
- Only movement casts: a hitbox that stands still hits nothing (use `GetPartBoundsInBox` and friends for that). Jumps over 100 studs in one frame, like teleports, aren't swept.

## API

### `ClientCast.new(Object, Options?) -> Caster`

`Object` is the part, model or tool to cast from. `Options` is optional, and every field in it is too:

| Option | Type | |
|---|---|---|
| `Owner` | `Player?` | The player whose client casts this and reports the hits. Server only. Without it, the caster casts on the machine that made it. |
| `Points` | `string?` | Name or tag of the points to cast from. `"DmgPoint"` by default. Give two casters on one character different points for a left and a right hand. |
| `Params` | `RaycastParams?` | What the casts can hit. All of it is copied, newer fields like `Margin` included where the engine has them. |
| `Radius` | `number?` | Sweep spheres this wide instead of rays. |
| `Debug` | `boolean?` | Draw this caster's casts. |

### `Caster`

| | |
|---|---|
| `Caster.Hit` | Signal, fires with a `Hit` (below). |
| `Caster:Start()` | Starts an activation. Starting again starts a fresh one, which can hit the same targets again. |
| `Caster:Stop()` | Ends it. |
| `Caster:Destroy()` | Stops it for good. A caster is also destroyed with its object. |
| `Caster:SetOwner(Player?)` | Hands it to a player's client, or back to this machine with `nil`. |
| `Caster:SetObject(Instance?)` | Casts from another object. |
| `Caster:SetParams(RaycastParams?)` | Changes what it can hit. |
| `Caster:SetDebug(boolean)` | Draws its casts, or stops. |
| `Caster.Active`, `Caster.Object`, `Caster.Owner` | Read them, don't set them. |

### `Hit`

| Field | |
|---|---|
| `Instance` | The part (or `Terrain`) that was hit. |
| `Position`, `Normal`, `Material` | Where it was hit, as a `RaycastResult` has them. |
| `Humanoid` | The humanoid of the model the part belongs to, if there is one. |
| `Point` | The point whose sweep hit, or `nil` when a part swept its own shape. |

### `ClientCast.Get(Object, Points?) -> Caster?`

Finds a caster on `Object`. On a client this gets the copy of a caster the server gave that player (see below).

## Casting on the client

With an `Owner`, the server's caster doesn't cast. Its `Start` and `Stop` go to the owner's client, which casts and sends each hit back, and the server's `Hit` fires when it arrives.

Ping doesn't lose hits: after `Stop`, the server keeps taking the owner's hits from that activation until the owner says it's done (or 2 seconds pass), so a hit from a player with 300 ms of ping still counts, and fast combos with several swings in flight are told apart.

The owner's client has a copy of the caster, and its `Hit` fires right when the client's own cast hits, which is the place for hit sounds and effects. That copy can also be started and stopped by the client itself, to skip the round trip before a swing begins:

```lua
-- LocalScript
local Caster = ClientCast.Get(Tool.Handle)

Tool.Activated:Connect(function()
	SwingRemote:FireServer() -- the server checks the swing is allowed and calls Caster:Start()
	if Caster then
		Caster:Start() -- cast right away instead of when the server's Start arrives
		task.wait(0.4)
		Caster:Stop()
	end
end)
```

Once the client starts or stops its copy itself, it decides when to cast, and the server's `Start` and `Stop` only decide which hits count: each server `Start` allows one activation, which the client has to begin before the server's `Stop` or within 2 seconds after it.

The server checks what a client reports (it's the player who hit, the parts are real and in the world, the values aren't NaN), and counts every target once per activation, but it can't know whether the hit was possible. Check that yourself, for example by distance:

```lua
Caster.Hit:Connect(function(Hit)
	local Reach = 8 + Player:GetNetworkPing() * 30 -- what a swing reaches, plus how far a target moves in the ping
	if (Hit.Position - Tool.Handle.Position).Magnitude > Reach then
		return
	end
	-- ...
end)
```

## Debugging

`Debug` (or `Caster:SetDebug(true)`) draws a caster's sweeps in red, the sweeps that hit in green, and a cross with the target's name where each hit landed. Everything fades out after a second.

To draw every caster at once, set the `Debug` attribute on the ClientCast module. It counts on the machine it's set on, so during a play test set it in the server's view to see server casters, or on a client to see that client's. A settings menu can set it on a player's own client so they see only their own hitboxes.

Casts are drawn where they run: a caster with an `Owner` on its owner's client, any other where it was made. The server marks the hits it accepts too.

## Coming from version 1

| Version 1 | Now |
|---|---|
| `ClientCast.new(Object, Params, Owner)` | `ClientCast.new(Object, { Params = Params, Owner = Owner })` |
| `Collided`, `HumanoidCollided` | `Hit`, once per target per activation; check `Hit.Humanoid` |
| your own debounce tables | not needed |
| `SetRecursive(true)` | always: points are found anywhere under the object |
| `StartDebug()`, `DisableDebug()` | `SetDebug(true)`, `SetDebug(false)` |
| `GetOwner()`, `GetObject()`, `Disabled` | `Owner`, `Object`, `not Active` |
| `EditRaycastParams` | `SetParams` |
| `Settings` in two scripts | the options, and the `Debug` attribute |
| module in ServerStorage | module in ReplicatedStorage |

## Testing

`testing.project.json` builds a place with a spinning hazard and a sword for every player. The `Debug` attribute is on, and the button on screen swings.
