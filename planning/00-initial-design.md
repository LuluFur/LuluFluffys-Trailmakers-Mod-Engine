# LFTME — Initial Design Notes

## Project shape

LuluFluffy's Trailmakers Mod Engine (LFTME) is a proxy / abstraction layer that sits on top of the Trailmakers `tm.*` modding API. The goal is to give modders a surface that feels like writing Roblox Studio scripts rather than wrestling with the host `tm.*` API directly. Modders never call `tm.*` if they don't want to; everything they need is reached through the engine instance.

## Public surface — entry point

The engine is instance-based. A user mod boots with the canonical constructor:

```lua
local engine = LuluFluffysTrailmakersModEngine.New()
```

or with the short alias `local engine = LFTME.New()`. Both names point at the same constructor. From there, subsystems are obtained via `engine:GetService("ServiceName")` in Roblox style — `GetService` is the canonical lookup, with very few lowercase shortcuts allowed for hot subsystems if at all.

## Style — Roblox-like

The engine deliberately mirrors Roblox Studio conventions because they are widely known and approachable. PascalCase across the public surface (services, classes, methods, properties, events). Colon-call style for any method that operates on an object (`player:Kick(reason)`, `Signal:Connect(fn)`). Dot for property access and value constructors. DataType constructors use `.new` (`Vector3.new(x, y, z)`, `Color3.fromRGB(r, g, b)`). Enums are namespaced under a single `Enum` global (`Enum.SpawnPattern.Circle`).

## Signals — event model

Events use Roblox's `RBXScriptSignal` pattern. Each host `tm.*.OnX` event is wrapped once at engine boot into an engine-owned `Signal` exposed on the relevant service (e.g. `Players.PlayerAdded`). `Signal:Connect(fn)` returns a `Connection` with `:Disconnect()` and a `Connected` boolean. `:Once(fn)` fires a handler exactly once. `:Wait()` yields the current coroutine until the next fire. `task.wait(seconds)` and `task.spawn(fn)` are ported because they are core Roblox idioms; both are driven by an internal frame loop on top of `tm.os.GetTime` or the host update tick.

## ChatService — confirmed mapping

The chat surface has two methods, mapped to two distinct host UI elements. `Chat:SendMessageTo(player, msg)` calls `tm.playerUI.SendChatMessage` under the hood — this is the in-game chat panel, lower priority than intrusive popups, attributed to a sender name. The chat panel renders at most six lines at any time; older lines are dropped as new ones arrive, so the engine should treat chat as ephemeral and lossy rather than as a transcript. `Chat:BroadcastToAll(header, msg)` calls `tm.playerUI.ShowIntrusiveMessageForAllPlayers` — this is the center-screen intrusive popup, high priority, with a header and a duration. The engine hides the host-API quirk that `SendChatMessage` is technically broadcast-attributed-to-sender; the caller does not need to know.

## Boundary rule — service vs player object

Methods on a service (`Chat`, `Physics`, `Players`, `ModStorage`, `Logger`) represent the engine acting on behalf of the user. Methods on a player object (`player:Kick`, `player:Teleport`, `player:GetPosition`) represent the player as the actor or the data source. This split avoids the awkward reading of `player:SendChatMessage(...)`, which sounds like the player is doing the chatting. Inbound events also live on the relevant service, not on the player:

```lua
Chat.MessageReceived:Connect(function(player, msg) ... end)
```

## Things we deliberately do not port from Roblox

There is no Instance tree, no `workspace`, no `Parent` assignment. There is no `RemoteEvent` because Trailmakers has no client / server split exposed to mods. There is no `Humanoid` or `player.Character` because a Trailmakers player is a controller, not an avatar. Persistence is named `ModStorage`, never `DataStoreService`, because we cannot honor cloud durability guarantees. `task.wait` precision is documented honestly against the actual host tick rate rather than implying Roblox's ~60 Hz Heartbeat.

## Pain points the engine absorbs

Chat echo suppression is built in — the sister AI Chat Mod hand-rolls a TTL `echoMap` to avoid `SendChatMessage` looping back through `OnChatMessage`; the engine eats this so user code never sees the echo. Spawn name resolution (`PFB_*` prefix, alias, catalog id, fuzzy match) becomes a single call. Spawn lifecycle is tracked automatically and exposed as `SpawnedObject:Destroy()`. Fuzzy player lookup, deferred / next-frame dispatch, leveled logging, vector and color shorthands, and a small spawn-pattern library (circle, grid, ring, sphere, etc.) are all engine-owned utilities, not user boilerplate.

## Phase 1 scope

Phase 1 lands the core: `LFTME.New()` with `:GetService`, the `Signal` and `Connection` classes, `task.wait` and `task.spawn` over a frame loop, the `Enum` skeleton, `Vector3` and `Color3` datatypes, `ChatService` with `SendMessageTo` and `BroadcastToAll`, and `PlayersService` with `Player` objects plus `PlayerAdded` / `PlayerRemoving` signals. Echo suppression for chat is hidden inside the chat wrapper. Later phases add `Physics`, spawn patterns, `ModStorage`, `Logger`, and the broader enum tables.

## Logger

The Logger service writes to a `logs.txt` file in the mod directory via `tm.os.WriteAllText_Dynamic` (or its append equivalent). It never writes to chat, because the chat panel only renders six lines at once and logs would immediately burn that budget for any real player-visible message. The Logger exposes leveled methods (`Logger:Debug`, `Logger:Info`, `Logger:Warn`, `Logger:Error`) and is decoupled from `tm.os.Log`, which the host treats as console-only; Logger may additionally call `tm.os.Log` for parity but the file is the source of truth.

## Intrusive message formatting

Intrusive popups support a subset of HTML-style formatting tags inside both `header` and `message` strings. Common tags: `<b>` or `<strong>` (bold), `<i>` or `<em>` (italics), `<mark>` (highlight), `<small>` (smaller text). Tags are paired — opening and closing required, e.g. `<b>Bold Text</b>`. The engine passes these through unmodified so callers retain full control. Chat lines (`Chat:SendMessageTo`) do not support these tags — the in-game chat panel renders plain text only, so the engine will document that formatting is intrusive-only and will not silently strip or convert tags between surfaces.
## MarkupText helper

Two valid styles for intrusive message formatting. Raw HTML-style tags are always accepted:

```lua
Chat:BroadcastToAll("Alert", "<b>Server</b> restarting")
```

works and the engine does nothing clever to it. For ergonomic and discoverable construction, the engine also exposes `LuluFluffysTrailmakersModEngine.MarkupText`, a chainable builder. The pattern:

```lua
LuluFluffysTrailmakersModEngine.MarkupText.new("Hello Everyone"):Bold():Italic()
```

wraps the inner text in tags from the inside out, producing `<i><b>Hello Everyone</b></i>`, and stringifies via `__tostring` so it can be passed directly to any service that accepts a string. Supported chained methods mirror the supported tags: `:Bold()` / `:Strong()`, `:Italic()` / `:Em()`, `:Mark()`, `:Small()`. Calls compose in order — the first method becomes the innermost tag. The builder is pure and immutable; each chained call returns a new MarkupText so partially-built fragments can be reused. Raw strings and MarkupText instances are interchangeable wherever an intrusive message accepts text.
## Chainable builders instead of option tables

Engine-wide convention: any method that configures an object or action uses chained setters that return `self`, not an options table. Example:

```lua
Physics:SpawnObject("PFB_Metal_Crate"):Position(0, 310, 0):Scale(1, 1, 1):Rotation(0, 45, 0)
```

The terminal call returns the configured object (the SpawnedObject in this case), so the chain ends naturally when the user stops typing dots. Single-call uses still work: `Physics:SpawnObject("PFB_Metal_Crate")` is valid and spawns at the default position. Two-or-fewer args stay positional and unchained when that reads more naturally; chained setters are reserved for cases where there is a real configuration surface with multiple optional knobs.

Spawn semantics are eager: the host call (`tm.physics.SpawnObject`) fires on the first `SpawnObject` call and the chain mutates the live object in place. The engine guarantees that all chained setters run before the next physics step, so the object never visibly appears at the origin then teleports — there is no "pop" between the initial spawn and the final configuration. This is a documented guarantee, not best-effort.

The same pattern applies wherever it reads cleanly. `Chat:BroadcastToAll("Alert")` returns a popup handle with `:Header(text)`, `:Duration(seconds)`, `:Body(text)` chainable setters so the call:

```lua
Chat:BroadcastToAll():Header("Warning"):Body("Server restarting"):Duration(10)
```

works. Player mutator chains read well too:

```lua
Players:FindByName("Player123"):Teleport(v3):Heal(100)
```

Methods that return data (`player:GetPosition()`, `Players:GetPlayers()`) obviously do not chain — the return value is the data, not `self`.

Three rules govern when a method returns `self` versus a value. First, mutators (setters, configurators, state-changing actions like Teleport / Heal / Kick) return `self` to enable chaining. Second, queries (getters, lookups, predicates) return the requested value. Third, constructors (`.new`) return the new instance, never `self` from a chain. The naming convention reinforces this: setter-style verbs (`Position`, `Scale`, `Header`) chain; query-style verbs (`Get*`, `Find*`, `Has*`, `Is*`) do not.
## ObjectSpawner, World, Physics — splitting tm.physics

The host `tm.physics` namespace bundles three unrelated concerns: object spawning, world-level state (gravity, time scale, time of day, wind, map name), and physics queries. The engine splits these into three services so each name describes what it actually does. `ObjectSpawner` owns spawn calls, the spawn registry, name resolution (`PFB_*` / alias / catalog / fuzzy), pattern helpers, and the chainable builders returned by spawn. `World` owns ambient world state — gravity, time scale, time of day, wind, map name — anything that is not tied to a single spawned object. `Physics` is reserved for genuine physics queries such as raycasts and overlaps if and when the host exposes them. The naming is honest because most spawned objects are static and have no physics applied; calling them "Physics objects" would mislead modders.

## Single vs group spawns

`ObjectSpawner:SpawnObject("PFB_Metal_Crate")` spawns one object and returns a SpawnedObject. `ObjectSpawner:SpawnGroup("PFB_Metal_Crate")` is the pattern-driven entry point and returns a SpawnedGroup, a collection of SpawnedObjects that itself supports the chainable mutator surface — mutators on a group apply to every member, with the group origin used as the reference for relative positioning. `Position`, `Scale`, and `Rotation` on a group set the group transform; pattern methods lay out members relative to that transform. A `SpawnedGroup:Each(fn)` escape hatch hands each member to the callback for per-object tweaks.

## Built-in spawn patterns

Patterns are chainable methods on SpawnedGroup. Built-ins ship with the engine: `:Circle(radius, count)` lays members around a horizontal circle; `:Ring(radius, count, thickness)` is a circle with optional radial jitter; `:Grid(rows, cols, spacing)` lays a 2D grid; `:Cube(side, count)` and `:Sphere(radius, count)` fill volumes; `:Line(length, count)` runs a straight line along the local X axis; `:Wall(width, height, spacing)` tiles a vertical plane. Each pattern places members and returns the group, so patterns themselves chain — the example:

```lua
ObjectSpawner:SpawnGroup("PFB_Wall"):Wall(10, 4):Position(0, 0, 50):Rotation(0, 90, 0)
```

builds a wall, parks it, faces it. Order matters: pattern methods compute member offsets at call time relative to the current group transform, so later `Position`/`Rotation` moves the whole assembly. Patterns are idempotent over their inputs and never read external state.

## Registering custom patterns

The call:

```lua
LuluFluffysTrailmakersModEngine.Patterns:Register(name, fn)
```

adds a new pattern method to the SpawnedGroup builder. The pattern function receives `(group, ...args)` where `group` exposes the current origin, current rotation, the prefab name, and a `:AddMember(localOffset, localRotation?)` call. The function is responsible for calling `AddMember` once per desired position; the engine handles the actual host spawn calls and registry bookkeeping. Once registered, the pattern is available on every SpawnedGroup as a real method — registering a Spiral:

```lua
LuluFluffysTrailmakersModEngine.Patterns:Register("Spiral", function(group, radius, count, turns) ... end)
```

enables:

```lua
ObjectSpawner:SpawnGroup("PFB_X"):Spiral(10, 50, 3)
```

Names collide with built-ins are rejected; patterns are scoped to the engine instance so two mods cannot stomp on each other.

