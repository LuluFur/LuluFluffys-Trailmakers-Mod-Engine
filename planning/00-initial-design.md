# LFTME — Initial Design Notes

## Project shape

LuluFluffy's Trailmakers Mod Engine (LFTME) is a proxy / abstraction layer that sits on top of the Trailmakers `tm.*` modding API. The goal is to give modders a surface that feels like writing Roblox Studio scripts rather than wrestling with the host `tm.*` API directly. Modders never call `tm.*` if they don't want to; everything they need is reached through the engine instance.

## Public surface — entry point

The engine is instance-based. A user mod boots with `local myMod = LuluFluffysTrailmakersModEngine.New()` (canonical) or `local myMod = LFTME.New()` (short alias). Both names point at the same constructor. From there, subsystems are obtained via `myMod:GetService("ServiceName")` in Roblox style — `GetService` is the canonical lookup, with very few lowercase shortcuts allowed for hot subsystems if at all.

## Style — Roblox-like

The engine deliberately mirrors Roblox Studio conventions because they are widely known and approachable. PascalCase across the public surface (services, classes, methods, properties, events). Colon-call style for any method that operates on an object (`player:Kick(reason)`, `Signal:Connect(fn)`). Dot for property access and value constructors. DataType constructors use `.new` (`Vector3.new(x, y, z)`, `Color3.fromRGB(r, g, b)`). Enums are namespaced under a single `Enum` global (`Enum.SpawnPattern.Circle`).

## Signals — event model

Events use Roblox's `RBXScriptSignal` pattern. Each host `tm.*.OnX` event is wrapped once at engine boot into an engine-owned `Signal` exposed on the relevant service (e.g. `Players.PlayerAdded`). `Signal:Connect(fn)` returns a `Connection` with `:Disconnect()` and a `Connected` boolean. `:Once(fn)` fires a handler exactly once. `:Wait()` yields the current coroutine until the next fire. `task.wait(seconds)` and `task.spawn(fn)` are ported because they are core Roblox idioms; both are driven by an internal frame loop on top of `tm.os.GetTime` or the host update tick.

## ChatService — confirmed mapping

The chat surface has two methods, mapped to two distinct host UI elements. `Chat:SendMessageTo(player, msg)` calls `tm.playerUI.SendChatMessage` under the hood — this is the in-game chat panel, lower priority than intrusive popups, attributed to a sender name. The chat panel renders at most six lines at any time; older lines are dropped as new ones arrive, so the engine should treat chat as ephemeral and lossy rather than as a transcript. `Chat:BroadcastToAll(header, msg)` calls `tm.playerUI.ShowIntrusiveMessageForAllPlayers` — this is the center-screen intrusive popup, high priority, with a header and a duration. The engine hides the host-API quirk that `SendChatMessage` is technically broadcast-attributed-to-sender; the caller does not need to know.

## Boundary rule — service vs player object

Methods on a service (`Chat`, `Physics`, `Players`, `ModStorage`, `Logger`) represent the engine acting on behalf of the user. Methods on a player object (`player:Kick`, `player:Teleport`, `player:GetPosition`) represent the player as the actor or the data source. This split avoids the awkward reading of `player:SendChatMessage(...)`, which sounds like the player is doing the chatting. Inbound events also live on the relevant service, not on the player — `Chat.MessageReceived:Connect(function(player, msg) ... end)`.

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
