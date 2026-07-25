# LuluFluffy's Trailmakers Mod Engine — Design Reference

This document is the authoritative design reference for LuluFluffy's Trailmakers Mod Engine (LFTME). It is written for two audiences at once: modders who will read it to learn the public API, and contributors who will read it to implement and extend that API. Where the two audiences need different detail, the modder-facing description comes first and the contributor-facing notes follow in the same section.

## 1. Project overview

LFTME is a proxy and abstraction layer that sits on top of the Trailmakers `tm.*` modding API. The goal is to give modders a surface that feels like writing Roblox Studio scripts rather than wrestling with the host API directly. A modder who has never read the Trailmakers documentation should still be able to spawn objects, listen for chat, react to players joining, and persist data without ever typing `tm.`.

The Roblox-Studio feel is not cosmetic. It is the load-bearing design choice: PascalCase services and methods, colon-call style for instance methods, dot-access for property reads, `.new` constructors on data types, namespaced enums under a single `Enum` table, and a signal/connection event model. The engine deliberately copies the parts of that style that travel well to Lua-on-Trailmakers and deliberately drops the parts that do not — there is no Instance tree, no `workspace`, no `Parent` field, no `RemoteEvent`, no `Humanoid`. Section 11 lists what is intentionally absent and why.

The intended user is a hobbyist mod author who wants to ship a working gameplay mod in an afternoon. The engine therefore optimises for discoverable APIs, chainable builders, helpful error messages, and absorbing the host's awkward edges (chat echo, fuzzy prefab names, per-player cleanup) so user code stays small and focused.

## 2. Entry point and singleton model

A mod boots by constructing the engine exactly once. The engine is a singleton within the current Lua runtime / mod environment: a second construction attempt is a programmer error. If the host loads multiple mods into the same Lua state, those mods share the same LFTME singleton; if each mod runs in its own Lua state, each gets its own.

```lua
local engine = LuluFluffysTrailmakersModEngine.New()
```

The short alias `LFTME` points at the same constructor:

```lua
local engine = LFTME.New()
```

Both names are reachable as globals. They are the only globals the engine creates. Everything else — data types, the enum table, the namespace-level builders, the patterns registry — is reached through the namespace or through the engine instance.

`LFTME.New()` creates the singleton if none exists. A second call errors with the standard error format documented in section 4. Library code that does not own the engine lifecycle should not call `New()` at all; it should call `LFTME.Get()`:

```lua
local engine, err = LFTME.Get()
if not engine then
    error(err)
end
```

`LFTME.Get()` returns the existing instance, or `nil, err` if the engine has not yet been constructed. It never throws. This makes `Get()` safe to call from library code, deferred callbacks, or mod-internal modules that may load before or after the engine boots. When a `Logger` is not yet available in the example context — as in the boot sequence above — `error(err)` is the simplest correct handling. In contexts where a logger or `print` is available, the equivalent pattern is to log and return:

```lua
local engine, err = LFTME.Get()
if not engine then
    print(err)
    return
end
```

The one pattern to avoid in beginner-facing examples is the silent `return` without any reporting, because copy-paste tends to spread silent failures.

Services are obtained from the engine instance using `:GetService("ServiceName")`, mirroring Roblox style:

```lua
local Players = engine:GetService("Players")
local Chat = engine:GetService("Chat")
local ObjectSpawner = engine:GetService("ObjectSpawner")
```

Services are singletons within the single engine instance. Two `:GetService` calls for the same name return the same table. There is no per-mod sandboxing because there is no second engine. Internally, services may share a host event router (one subscription to `tm.players.OnPlayerJoined` that fans out to engine signals), but that is an implementation detail and not part of the public contract.

In examples throughout this document, the engine instance variable is always called `engine`. The full namespace name `LuluFluffysTrailmakersModEngine` is used for namespaced references (`LuluFluffysTrailmakersModEngine.Patterns:Register`, `LuluFluffysTrailmakersModEngine.MarkupText.new`). The short `LFTME` alias appears only at the construction site, because once the instance is in a local variable, the namespace name no longer appears in user code.

### Module loading

Mods that split their code across multiple files use `engine:LoadModules({"core", "tags", ...})` to load them in order. Each name is passed to the host's `tm.os.DoFile` and must return a non-nil value (typically a table containing the module's public interface):

```lua
local modules = engine:LoadModules({"core", "helpers", "items"})
local core = modules.core
local helpers = modules.helpers
local items = modules.items
```

Modules must be flat files in `data_static/`. No subfolders. The engine does not discover modules — you must explicitly list them. Files are loaded synchronously, so you can declare dependencies by listing them in dependency order.

**Failure behaviour — fail-fast aborts.** If any module fails to parse, throws an error, or returns `nil`, LoadModules immediately aborts the entire call: a FATAL line is logged through `Logger:Error`, an error is broadcast through `Chat:BroadcastToAll` so the failure is visible in-game, and the whole `LoadModules` call raises an error. The remaining modules on your list are never attempted. This fail-fast design makes broken module chains impossible to ignore — a mod that fails to load a required module will not start with half its dependencies missing.

The LoadModules call returns a table keyed by the module names you passed, in the order you listed them, only if all modules load successfully. If any module is missing from your list or fails to load, callers should wrap the call in a `pcall` if they want to recover from the error; otherwise the error propagates up and stops mod execution.

**When the host's `tm.os.DoFile` is unavailable** (some Trailmakers builds or test harnesses), LoadModules logs a warning and returns an empty table. This is a graceful degradation for tools that don't have a file loader, not a silent failure — you will see the warning in logs.

## 3. Naming and casing conventions

The engine uses four casing styles, each with a single dedicated role. Mixing them on purpose is how a reader tells public surface from internal state at a glance.

`PascalCase` is the public surface. Services (`Players`, `Chat`, `ObjectSpawner`), classes (`Signal`, `Connection`, `TaskManager`, `Player`), public methods (`SendMessage`, `BroadcastToAll`, `Teleport`, `Kick`), public properties (`Name`, `Id`, `Connected`), and signal names (`PlayerJoinedServer`, `MessageReceived`) are all PascalCase. Constructors are `.new` on data types (`Vector3.new`, `Color3.fromRGB`, `MarkupText.new`) to match Roblox idiom.

`camelCase` is local variable names, function parameters, and short-lived scratch values inside method bodies:

```lua
local deltaTime = 0
local playerName = player.Name
for _, p in ipairs(Players:GetPlayers()) do
    local pos = p:GetPosition()
end
```

`_camelCase` (leading underscore) is private fields on engine-internal tables. The convention is consistent across every class:

```lua
self._connections = {}
self._playerCache = {}
self._isDestroyed = false
```

The engine does not metatable-trap access to `_` fields. Lua's "tables are open" culture is preserved deliberately — strict `__index` privacy makes debugging harder, complicates inheritance, costs a metamethod call per lookup, and fights introspection tools. Privacy is convention plus tests, not runtime enforcement.

`LOUD_SNAKE_CASE` is module-level constants:

```lua
local MAX_CHAT_LINES = 6
local DEFAULT_INTRUSIVE_DURATION = 5
local ECHO_SUPPRESSION_TTL = 0.25
```

The contrast against PascalCase public APIs and camelCase locals makes constants visually obvious in source. Do not use `kMaxChatLines` (less idiomatic in Lua), and do not use `PascalCase` for constants (they read as exported public surface).

## 4. Engine-wide patterns

A handful of patterns recur across every service. Learning them once is enough to predict the shape of any method in the engine.

### Chainable builders

Any method that configures an object or action returns `self` so the next configuration call can be appended with a dot. Mutators chain, queries do not, constructors do not. The full rule:

- Mutators (setters, configurators, state-changing actions like `Teleport`, `Kick`, `Eject`) return `self`.
- Queries (`GetPosition`, `GetPlayers`, `FindByName`, `HasFlag`, `IsAlive`) return the requested value.
- Constructors (`.new`) return the freshly built instance, not `self` from a chain.

A spawn chain reads as a single thought:

```lua
ObjectSpawner:SpawnObject("PFB_Metal_Crate"):Position(0, 310, 0):Scale(1, 1, 1):Rotation(0, 45, 0)
```

A popup builder reads the same way:

```lua
Chat:BroadcastToAll():Header("Warning"):Body("Server restarting"):Duration(10)
```

Player mutator chains work too, but only across true mutators. Because `SpawnObjectNearby` returns the spawned object rather than the player, it is the natural terminus when present:

```lua
local player = Players:FindByName("Player123"):Teleport(0, 310, 0):Eject()
local crate = player:SpawnObjectNearby("PFB_Metal_Crate"):Scale(2, 2, 2)
```

The first line is a pure player-mutator chain that ends with a `Player`. The second line hands off to the spawned crate and chains a single mutator on it. The terminal call returns the configured object, so the chain ends naturally when the user stops typing dots. Single-call uses still work — `ObjectSpawner:SpawnObject("PFB_Metal_Crate")` is a valid expression that spawns at the default position and returns a `SpawnedObject`. Two-or-fewer positional arguments stay positional and unchained when that reads more naturally; chained setters are reserved for cases with a real configuration surface.

Spawn semantics are eager. The host call (`tm.physics.SpawnObject` under the hood) fires on the first method in the chain, and chained setters mutate the live object in place. The engine guarantees that all chained setters in a single statement run before the next physics step, so the object never visibly appears at the origin then teleports. There is no "pop" between initial spawn and final configuration. This is a documented guarantee, not best-effort.

### Signals and connections

Events use the Roblox `RBXScriptSignal` pattern. Each host `tm.*.OnX` event is wrapped once at engine boot into an engine-owned `Signal` exposed on the relevant service.

```lua
local conn = Players.PlayerJoinedServer:Connect(function(player)
    print(player.Name .. " joined")
end)
```

`Signal:Connect(fn)` returns a `Connection` with `:Disconnect()` and a `Connected` boolean. `Signal:Once(fn)` fires the handler exactly once and disconnects automatically. `Signal:Wait()` yields the current coroutine until the next fire and returns the fire arguments. Signal callbacks are isolated with `pcall`: a thrown error in one handler does not stop the rest of the dispatch, and the error is reported through `Logger:Error` (and optionally `tm.os.Log`).

### Yield rules

Yielding is documented on every public method. The two yielding primitives the engine exposes are `Signal:Wait()` and `task.wait(seconds)`. Both yield via `coroutine.yield` and are resumed by the engine scheduler driven from `UpdateService.OnUpdate`. The engine never busy-waits on `tm.os.GetTime`; busy-waiting would freeze the mod frame.

Runtime enforcement is light but covers the two yielding primitives symmetrically. The engine asserts when either `task.wait` or `Signal:Wait` is called outside a scheduler-managed coroutine, because in both cases the yield would never be resumed by the engine and the calling code would silently stall in production. Other methods are documented as yielding or non-yielding but not wrapped in guards. Wrapping every method to enforce annotations would add overhead without proportional safety.

The guard error uses the runtime-failure template. For example:

```text
Signal:Wait(main.lua:34) cannot yield from an unmanaged coroutine. Use task.spawn(function() ... end).
```

The `task.wait` form is identical except for the method name in the prefix.

### Error handling

The engine uses two error conventions, picked by category. Programmer errors throw with `error(...)`. Expected failures return `nil, err`.

A programmer error is something only a code bug can cause: passing the wrong type, passing `nil` where a value is required, double-destroying an object. The engine throws because the call site is unrecoverable and the programmer needs the traceback. An expected failure is something that depends on runtime state: a player not currently online, a prefab name that doesn't match anything, a storage key that hasn't been written. The engine returns `nil, err` because the caller is expected to handle that case.

Every engine error message follows one of two closely related templates, picked by the kind of failure. The two templates share the same prefix so messages always start with the same shape — `<ClassOrService>:<Method>(<file>:<line>)` — and diverge only in the trailing detail.

The **type-error template** is used for parameter typechecks, where the failure can be expressed as "wrong type for this parameter":

```text
<ClassOrService>:<Method>(<file>:<line>) expected <expectedType> for parameter "<paramName>", got <actualType> <actualValue>
```

Concrete examples:

```text
Player:Teleport(main.lua:123) expected Vector3 for parameter "position", got string "not a Vector3"
```

```text
Chat:SendMessage(main.lua:45) expected string for parameter "message", got nil
```

```text
ObjectSpawner:SpawnObject(main.lua:88) expected string or Enum.Block for parameter "prefab", got table
```

The **runtime-failure template** is used for everything else — failures that depend on runtime state rather than parameter shape: a prefab name that does not resolve, an engine that already exists, a player that is offline, a storage key that is missing. The template carries a free-form message after the prefix:

```text
<ClassOrService>:<Method>(<file>:<line>) <message>
```

Concrete examples:

```text
ObjectSpawner:SpawnObject(main.lua:52) could not resolve prefab "metal".
```

```text
ObjectSpawner:SpawnObject(main.lua:52) prefab name "crate" is ambiguous.
```

```text
LFTME.New(main.lua:12) engine instance already exists.
```

```text
Players:FindByName(main.lua:30) no player matched "Player123".
```

The prefab-resolution examples later in section 6 use this second template; they are not exceptions to a one-size-fits-all format but instances of the runtime-failure pattern. Contributors picking between templates should default to the type-error form whenever the failure is "wrong type for parameter X" and to the runtime-failure form otherwise. Both flow through `util/Typecheck.lua` so the prefix stays consistent.

The file and line come from `debug.getinfo(level, "Sl")` walked back to the user's call site. String values are quoted (`got string "Metal_Crate"`). Large tables are not dumped wholesale — they are summarised as `got table 0x123456` or `got table with keys {Name, Position}` to keep messages readable. Numbers, booleans, and `nil` are printed verbatim.

The same format is used for the `nil, err` path, with `err` being a plain string the caller can log:

```lua
local player, err = Players:FindByName("Player123")
if not player then
    Logger:Warn(err)
    return
end
```

Signal callback errors are isolated. A user handler that throws is caught with `pcall`, logged through `Logger:Error`, and the remaining handlers still run. The signal dispatch is never aborted by a user bug.

## 5. DataTypes

The engine ships three value types. They are immutable from the modder's perspective — methods return new instances rather than mutating `self`.

### Vector3

`Vector3` represents a position, direction, or scale in 3D space. The constructor is `Vector3.new(x, y, z)`:

```lua
local Vector3 = LFTME.Vector3
local origin = Vector3.new(0, 310, 0)
local up = Vector3.new(0, 1, 0)
```

Public surface includes `X`, `Y`, `Z` properties, arithmetic via metamethods (`v1 + v2`, `v1 - v2`, `v * scalar`), `:Magnitude()`, `:Unit()`, `:Dot(other)`, `:Cross(other)`, and `:Lerp(other, alpha)`. The class is value-equal: two `Vector3`s with the same components compare equal under `==`.

### Color3

`Color3` represents an RGB colour. Two constructors:

```lua
local Color3 = LFTME.Color3
local red = Color3.new(1, 0, 0)
local blue = Color3.fromRGB(0, 0, 255)
```

Public surface includes `R`, `G`, `B` properties (always normalised 0..1), `:Lerp(other, alpha)`, and `:ToHex()`. Like `Vector3`, `Color3` is value-equal.

### MarkupText

`MarkupText` is a chainable builder for the HTML-style formatting tags that intrusive popups support. The constructor takes a raw inner string; chained methods wrap that string in tags from the inside out.

```lua
local MarkupText = LuluFluffysTrailmakersModEngine.MarkupText
local label = MarkupText.new("Hello Everyone"):Bold():Italic()
```

That value stringifies via `__tostring` to `<i><b>Hello Everyone</b></i>` and can be passed directly anywhere an intrusive message accepts text. The first method becomes the innermost tag. Supported chained methods mirror the supported tags: `:Bold()` and `:Strong()`, `:Italic()` and `:Em()`, `:Mark()`, `:Small()`. The builder is pure — each chained call returns a new `MarkupText` so partially-built fragments can be reused without aliasing surprises.

Raw HTML-style tags are always accepted by `Chat:BroadcastToAll`, so the builder is convenience, not policy:

```lua
Chat:BroadcastToAll("Alert", "<b>Server</b> restarting")
```

works without any builder involvement. Chat panel lines (`Chat:SendMessage`) do not support formatting tags — the host renders them as plain text — and the engine documents this rather than silently stripping or converting.

Because intrusive popups pass tags through, any user-supplied substring — most commonly a player name — is interpolated raw and may produce accidental formatting if it happens to contain markup-like characters. The engine ships a small escape helper for the common case:

```lua
local safeName = MarkupText.escape(player.Name)
local greeting = MarkupText.new("Welcome, " .. safeName):Bold()
Chat:BroadcastToAll("Greeting", tostring(greeting))
```

`MarkupText.escape(text)` returns a new string with HTML-like characters (`<`, `>`, `&`, `"`, `'`) replaced by their entity equivalents, so the result is safe to splice into a popup body. Raw strings passed without `escape` are not filtered by either `MarkupText.new` or `Chat:BroadcastToAll`; the engine is deliberately a thin layer over the host's markup surface and trusts the caller to escape untrusted text.

## 6. Services

Services are the main public surface. Every service is obtained the same way (`engine:GetService("Name")`) and follows the conventions in section 4. The sections below describe each service's behaviour, signals, and important quirks.

### Players

`Players` represents the live set of human players in the session. Two signals fire on lifecycle changes:

```lua
Players.PlayerJoinedServer:Connect(function(player)
    print(player.Name .. " joined")
end)

Players.PlayerLeftServer:Connect(function(player)
    print(player.Name .. " left")
end)
```

The event names are deliberately Trailmakers-clear rather than strict Roblox tense (`PlayerAdded`/`PlayerRemoving`). The Trailmakers session model is "a server with players joining and leaving", and the names should say exactly that. `PlayerLeftServer` fires after the host reports the disconnect, but the wrapped `Player` object is still queryable for `Name`, `Id`, and any engine-cached state for the duration of the dispatch. After the dispatch returns, the engine drops its references to that player.

Each `Player` object exposes `Name`, `Id`, mutator methods (`Teleport(x, y, z)` or `Teleport(Vector3)`, `Kick(reason)`, `Kill()`, `Eject()`, `SetTeam(n)`, `SetInvincible(bool)`, `SetJetpackEnabled(bool)`, `SpawnObjectNearby(prefab, offset?)`), and query methods (`GetPosition()`, `IsInSeat()`). Mutators return `self` for chaining; queries return values. `Teleport` accepts either three positional numbers or a single `Vector3`. `SpawnObjectNearby` is sugar that reads the player position, applies an optional local offset, and routes through `ObjectSpawner:SpawnObject`. Unlike the other player mutators it returns the spawned object handle rather than the player, because the spawned object is almost always the value the caller actually needs next. Treat `SpawnObjectNearby` as a factory helper hung off the player rather than as a chainable player mutator; if the player itself is still needed, hold a local reference to the player before calling it. `Kick(reason)` accepts a reason string for the modder's convenience, but the host call `tm.players.Kick(playerId)` does not deliver the reason to the kicked player — the value is logged engine-side via `Logger:Info` and then discarded. Treat the reason as an audit-log message, not a user-facing notice. Each `Player` also owns a `TaskManager` instance at `player.TaskManager`, automatically created by `Players` when the player joins and automatically destroyed when the player leaves. Section 7 covers `TaskManager` in detail.

Lookup methods on the service:

- `Players:GetPlayers()` returns an array of `Player` objects. The canonical iteration form.
- `Players:FindByName(name)` returns a single `Player` matched fuzzily on display name, or `nil, err` if there is no unique match.
- `Players:FindById(id)` returns the player with that host id, or `nil, err`.
- `Players:Iterate()` returns a stateful iterator function suitable for `for player in Players:Iterate() do` without allocating an intermediate array. Documented for advanced use, not in beginner examples.

Ghost-player detection: A player pid can stay in the roster while their character is gone (e.g., when a nuke + leave crashes the leave event). Any mod running per-player ticks then re-polls a dead pid every frame, feeding Trailmakers' `Failed to find player: N` warning spam and climbing memory usage. The engine provides two tools to detect and clean up this state:

- `Player:Exists()` — Probes character existence via `tm.players.GetPlayerTransform`. Returns three values: `exists` (boolean, true only if probe succeeded), `canProbe` (boolean, false only if host function is absent), and `error` (string/nil, non-nil only if probe threw). When `canProbe` is false, existence is unknown and the player is treated as alive — missing evidence is not death. Useful for point-in-time checks when you hold a Player object.
- `Players:VerifyExists(id)` — Continuous ghost detection with automatic periodic sweep. The engine runs this automatically every 1 second via `UpdateService:Every`, checking all players and sweeping any that have failed 4 consecutive probes (across different ticks). Failure counter resets to zero on any probe success. Same-tick dedupe prevents multiple calls in one tick from accumulating; missing probe (canProbe=false) resets failures to 0. Mods can call this on-demand for immediate checks, but do not need to hand-roll a polling loop.

When a player is ruled a ghost:

- `Players.PlayerGhosted` signal fires, passing the `Player` object. Unlike `PlayerLeftServer`, this signal indicates an unclean state where the character vanished without an event. Handlers can react, clean up, or log for debugging.
- The player's `TaskManager` is destroyed automatically, which stops any per-player ticking the mod had registered.
- The pid is removed from the roster (`_byId`), so a late `OnPlayerLeft` event (if it arrives) is a harmless no-op.

The sweep is idempotent and does not throw. The distinction between `PlayerLeftServer` (clean leave) and `PlayerGhosted` (unclean disappearance) lets mods tell the two cases apart and react accordingly.

### Chat

The chat service has two methods, mapped to two distinct host UI elements. The split is by intent: a panel line attributed to a sender, or an intrusive centre-screen popup.

```lua
Chat:SendMessage("Welcome!")
```

calls `tm.playerUI.SendChatMessage` under the hood and produces a chat-panel line. Trailmakers has no per-player chat surface: `SendChatMessage` always broadcasts, attributed to the configured sender name. The engine states that in the signature rather than hiding it — `SendMessage` takes only the message, so it cannot imply a targeting that the host does not provide. The chat panel renders at most six lines at a time; older lines are dropped as new ones arrive. Mods should treat chat as ephemeral and lossy rather than as a transcript.

`Chat:SendMessageTo(player, message)` is the older name for the same call and still works, but it is **deprecated**. It accepted a `player` argument it could never honour, which led callers to loop over players and send N copies of every line. It now drops the `player` argument, logs a one-shot deprecation warning, and forwards to `SendMessage`. Existing mods keep running unchanged; new code should use `SendMessage`.

```lua
Chat:BroadcastToAll("Warning", "Server restarting in 10 seconds")
```

calls `tm.playerUI.ShowIntrusiveMessageForAllPlayers` and produces a centre-screen popup with a header and a duration. The builder form is also supported:

```lua
Chat:BroadcastToAll():Header("Warning"):Body("Server restarting"):Duration(10)
```

Intrusive popups accept HTML-style formatting tags (`<b>`, `<i>`, `<mark>`, `<small>`) inside both header and message, paired and explicit. Chat panel lines do not. The engine does not silently strip or convert between the two surfaces.

Inbound chat fires the `MessageReceived` signal on the service, not on the player object — this keeps the "player as actor" reading consistent:

```lua
Chat.MessageReceived:Connect(function(player, msg)
    print(player.Name .. " said: " .. msg)
end)
```

Echo suppression is built in. The host's `OnChatMessage` callback fires for messages the engine itself sent via `SendChatMessage`, which would otherwise produce a feedback loop. The engine maintains an internal `_echoMap` so user code never sees the echo. It counts rather than flags: each outbound send bumps a per-(sender, message) counter, and each matching inbound line consumes one count, so exactly as many copies as the engine sent are suppressed. A player who happens to type the same text as a recent server message is still delivered. The TTL on each entry exists only to discard counts whose echo never arrived. This is one of the principal pain points the engine absorbs.

### ObjectSpawner

`ObjectSpawner` owns spawn calls, the spawn registry, prefab name resolution, pattern helpers, and the chainable builders returned by spawn methods. There are two entry points:

```lua
ObjectSpawner:SpawnObject("PFB_Metal_Crate"):Position(0, 310, 0)
```

returns a single `SpawnedObject` with chainable mutators (`Position`, `Scale`, `Rotation`) and a `Destroy()` terminal.

```lua
ObjectSpawner:SpawnGroup("PFB_Metal_Crate"):Grid(4, 4, 2):Position(0, 310, 0)
```

returns a `SpawnedGroup`, a collection of `SpawnedObject`s that itself supports the chainable mutator surface. Mutators on a group apply to every member, with the group origin used as the reference for relative positioning. `Position`, `Scale`, and `Rotation` on a group set the group transform; pattern methods (section 9) lay out members relative to that transform. `SpawnedGroup:Each(fn)` is the escape hatch for per-member tweaks.

Prefab name resolution is intentionally forgiving. All of the following resolve to `"PFB_Metal_Crate"`:

```lua
ObjectSpawner:SpawnObject("PFB_Metal_Crate")
ObjectSpawner:SpawnObject("Metal_Crate")
ObjectSpawner:SpawnObject("MetalCrate")
ObjectSpawner:SpawnObject("metal crate")
ObjectSpawner:SpawnObject("metalcrate")
ObjectSpawner:SpawnObject(Enum.Block.MetalCrate)
```

The resolution order is fixed:

1. exact `Enum.Block.*` value
2. exact canonical prefab name, e.g. `"PFB_Metal_Crate"`
3. exact registered alias, e.g. `"MetalCrate"`
4. normalised match — case-insensitive, ignoring spaces, underscores, hyphens, and an optional leading `PFB_` or `PFB-`
5. fuzzy match if there is exactly one strong candidate
6. fail with suggestions if ambiguous or unknown

Failure messages are explicit:

```text
ObjectSpawner:SpawnObject(main.lua:52) could not resolve prefab "metal".
Did you mean "MetalCrate", "MetalBeam", or "MetalWall"?
```

```text
ObjectSpawner:SpawnObject(main.lua:52) prefab name "crate" is ambiguous.
Matches: "MetalCrate", "WoodenCrate", "ExplosiveCrate".
Use the full enum or canonical name.
```

The engine does not warn on raw prefab strings by default. Raw `PFB_*` names are legitimate Trailmakers concepts, not bad code. An opt-in setting is available for authors who want stricter discipline:

```lua
engine.Settings.WarnOnRawPrefabStrings = true
```

A helper method exposes the resolver without committing to a spawn:

```lua
local canonicalName, err = ObjectSpawner:ResolvePrefab("metal crate")
if not canonicalName then
    Logger:Warn(err)
    return
end
ObjectSpawner:SpawnObject(canonicalName)
```

In Phase 1, `ResolvePrefab` returns exactly two values: the canonical prefab name string on success, or `nil` plus an error string on failure. The LuaLS shape is `function ObjectSpawner:ResolvePrefab(name): (string?, string?)` — `canonicalName: string?` on success, `err: string?` on failure. The return shape is intentionally narrow — a single string is easy to pass straight back into `SpawnObject`, and the two-value contract avoids the trap of "second return value sometimes means enum, sometimes means error". A richer return value — a small descriptor table carrying canonical name, enum value, and display name — is reserved for a later phase, when the enum catalogue is broad enough for the extra fields to be worth the API surface.

### World

`World` owns ambient world-level state — anything that is not tied to a single spawned object. Gravity, time scale, time of day, wind, and the current map name all live here:

```lua
local World = engine:GetService("World")
World:SetGravity(Vector3.new(0, -20, 0))
World:SetTimeScale(0.5)
World:SetTimeOfDay(75)
local mapName = World:GetMapName()
```

`SetTimeOfDay` takes a value on the in-game slider scale — `0` to `100`, where `50` is midday. The dial wraps: `100` loops back to `0`, so values outside the range are accepted and reduced modulo `100`. Negative values wrap the same way:

```lua
World:SetTimeOfDay(-10)  -- becomes 90
World:SetTimeOfDay(125)  -- becomes 25
```

The engine passes the final modulo'd value through to `tm.world.SetTimeOfDay` without unit conversion; if you want to think in 24-hour clock terms, write the conversion yourself (`hour / 24 * 100`) rather than expecting `World:SetTimeOfDayHour` sugar in Phase 1.

The split between `World`, `ObjectSpawner`, and `Physics` is the engine's main correction to the host's `tm.physics` namespace, which bundles all three concerns. `World` is for state that is not about any particular object.

### Physics

`Physics` is reserved for genuine physics queries — raycasts, overlap checks, and similar — when and if the host exposes them. In Phase 1 the surface is minimal because the host does not yet expose a stable raycast API to mods. The name is held back deliberately so it does not get misused for spawn calls; most spawned Trailmakers objects are static and calling them "Physics objects" would be misleading.

### Logger

`Logger` is the engine's leveled logging service. It writes to a `logs.txt` file in the mod directory, never to the chat panel. The chat panel only renders six lines at a time, so using it for logs would burn the budget for any real player-visible message.

The logger maintains an in-memory ring buffer capped at 200 lines by default. Since Trailmakers only exposes full-file writes (`tm.os.WriteAllText_Dynamic`), the logger cannot append a single line; instead, it maintains the ring buffer in memory and writes the bounded buffer to disk on a throttled schedule (~1 second between writes). Error-level messages bypass the throttle and flush immediately, ensuring the final log line before a crash is never lost.

This design caps memory growth: even a long-running mod that logs thousands of messages over many hours will keep only the most recent 200 lines in memory (tunable via `Logger:SetBufferSize(n)`). The trade-off is that `logs.txt` is not a complete session record — only the last 200 lines are retained. For mods that need more history, `SetBufferSize` can raise the cap; for mods that log lightly, it can be lowered to reduce memory use.

```lua
Logger:Debug("scheduler tick")
Logger:Info("Player123 joined")
Logger:Warn("prefab resolution fell back to fuzzy match")
Logger:Error("teleport failed: " .. err)
Logger:SetBufferSize(500)    -- increase retention to 500 lines
Logger:SetFlushInterval(2.0) -- throttle writes to every 2 seconds
Logger:Flush()               -- force a write right now
```

The four logging methods are `Debug`, `Info`, `Warn`, `Error`. Each accepts a single message string and optional formatting arguments. The logger may additionally call `tm.os.Log` for console parity, but `logs.txt` is the source of truth. Engine-internal callback errors (from `Signal` `pcall` isolation) are routed through `Logger:Error` automatically. Public mutators include `SetPath`, `SetMinLevel`, `SetBufferSize`, `SetFlushInterval`, and `Clear`. The `Flush()` method forces an immediate write of the buffer to disk.

### ModStorage

`ModStorage` is the file-backed persistence service. The name is deliberate: not `DataStoreService`, because the engine cannot honour the cloud durability guarantees that name implies.

```lua
local ModStorage = engine:GetService("ModStorage")
ModStorage:Set("highScore", 12345)
local score = ModStorage:Get("highScore")
```

`Get(key)` returns the stored value or `nil` if the key has not been written. `Set(key, value)` writes synchronously through to the mod-local storage file. Values are serialised through a small JSON-equivalent codec. The service documents honestly that durability is whatever the host filesystem gives — a corrupted save file or a crash during write can lose the last value. Mods that need transactional guarantees must implement their own write-ahead pattern on top.

`Set` is synchronous in Phase 1 and performs a real file write on each call. Do not call it from every `OnUpdate` tick or from any other hot loop — the stutter from rewriting the storage file at frame rate will be visible. Cache frequently-changing values in memory and flush to `ModStorage` on a coarse interval (`UpdateService:Every(10, ...)` is a common pattern) or on shutdown. A future phase may add a debounced `Set` or an explicit `Flush` method; until then, batching is the caller's responsibility.

### UpdateService

`UpdateService` exposes the engine's frame loop. Phase 1 ships a single signal:

```lua
local UpdateService = engine:GetService("UpdateService")
UpdateService.OnUpdate:Connect(function(deltaTime)
    print("delta:", deltaTime)
end)
```

`OnUpdate` fires whenever the engine update loop is pumped, passing `deltaTime` in seconds. The guarantees are deliberately weaker than Roblox's `Heartbeat`. Specifically:

- `OnUpdate` is not guaranteed to fire at 60 Hz. It fires when the host pumps the mod update tick.
- It is not tied to rendering. There is no `RenderStepped`.
- It is not guaranteed to be pre-physics or post-physics unless the host exposes that distinction. Until it does, there is no `Stepped`.

`OnUpdate` is the canonical driver for `task.wait`, `task.spawn`, deferred callbacks, and any internal scheduling. The name is `UpdateService.OnUpdate` rather than `RunService.Heartbeat` because honesty about timing semantics beats Roblox-shaped familiarity in this one case.

The host backing is the Trailmakers global `update(dt)` callback that the host invokes every tick on every loaded mod. `UpdateService` installs a single `update` handler at engine boot, captures `dt`, and fans it out to `OnUpdate` listeners. There is no `tm.*` event for ticks — the global callback is the entire surface — so any frame-driven behaviour in the engine ultimately threads through here. This is also why `UpdateService` is a singleton inside the singleton engine: two engines registering competing `update` globals would be a host-level conflict.

Because `update` is a plain Lua global and may already be defined by user code, the engine has a concrete policy for the conflict case. At boot, `UpdateService` captures the existing `_G.update` (if any) into a local, and installs an `update` that calls the previous handler first and then pumps the engine:

```lua
local previousUpdate = _G.update

_G.update = function(dt)
    if previousUpdate then
        previousUpdate(dt)
    end
    engine:_Update(dt)
end
```

This means a user `update` defined **before** `LFTME.New()` keeps working — the engine simply wraps it. A user `update` defined **after** `LFTME.New()`, however, overwrites the engine's wrapper and breaks scheduling: `task.wait`, `task.spawn`, `UpdateService:After`, `UpdateService:Every`, and every signal that depends on `OnUpdate` will stop firing. The engine has no way to detect this after the fact without paying a per-tick cost it does not want to pay, so the rule is documented loudly: do not define a global `update` once the engine is constructed. Use `UpdateService.OnUpdate:Connect(...)` instead — it is the canonical surface for tick-driven behaviour and is immune to ordering hazards.

On top of `OnUpdate`, `UpdateService` ships a small set of time helpers for the common patterns. `UpdateService:After(seconds, fn)` runs `fn` once after at least `seconds` of accumulated tick time and returns a `TaskHandle` that can be cancelled before fire. `UpdateService:Every(seconds, fn)` runs `fn` on a repeating interval driven by the same accumulator and returns a `TaskHandle` that stops the interval when cancelled. Both helpers are sugar over `OnUpdate:Connect` with internal deadline tracking; they do not introduce new scheduling primitives. They return `TaskHandle` rather than `Connection` because the value handed back is a scheduled piece of work, not a subscription to a signal — keeping the two primitives semantically distinct prevents `Connection` from drifting into a catch-all. The Roblox-equivalent name `task.delay(seconds, fn)` is exposed as an alias for `UpdateService:After` so Roblox idioms work unmodified; it also returns a `TaskHandle`.

```lua
-- one-shot, cancellable
local handle = UpdateService:After(5, function()
    Logger:Info("five seconds elapsed")
end)
-- handle:Cancel()  -- cancels before fire

-- repeating interval
local ticker = UpdateService:Every(1, function()
    Logger:Debug("tick")
end)
-- ticker:Cancel()  -- stops the interval

-- Roblox alias, also returns a TaskHandle
task.delay(2, function() Logger:Info("two seconds elapsed") end)
```

The accumulator semantics matter: if the host is paused or slowed (low tick rate, the player tabbed out, debug freeze), `After(5, fn)` does not fire after five wall-clock seconds — it fires after five seconds of accumulated `OnUpdate` deltas. This is the same honesty principle that names the signal `OnUpdate` rather than `Heartbeat`.

## 7. Core primitives

A handful of small classes hold the engine together. Modders touch some of them directly (`TaskManager`, `Enum`) and others only indirectly (`Signal`, `Connection`).

### Signal

`Signal` is the engine's event class. Public surface:

- `Signal:Connect(fn) -> Connection` — registers `fn`, returns a `Connection`. Does not yield.
- `Signal:Once(fn) -> Connection` — same, but auto-disconnects after the first fire. Does not yield.
- `Signal:Wait() -> ...` — yields the calling coroutine until the next fire, returns the fire arguments.
- `Signal:Fire(...)` — fires the signal. Engine-internal; not part of the public modder surface.

User callbacks are isolated with `pcall`. Connection order is insertion order. Disconnecting a connection during dispatch is safe — the dispatch loop reads the connection list defensively.

### Connection

Returned by `Signal:Connect` and `Signal:Once`. Surface:

- `Connection.Connected` — boolean, true until `Disconnect` is called.
- `Connection:Disconnect()` — unregisters the handler. Idempotent. Does not yield.

### TaskHandle

`TaskHandle` is the engine's primitive for scheduled or background work — anything produced by `task.spawn`, `task.delay`, `UpdateService:After`, or `UpdateService:Every`. It exists to keep "a signal subscription" (`Connection`) and "a piece of scheduled work" (`TaskHandle`) semantically distinct, so each has one obvious cleanup verb and `TaskManager` can route either correctly. Public surface:

- `TaskHandle.Cancelled` — boolean, false until `Cancel` is called, true afterwards.
- `TaskHandle:Cancel()` — cancels the scheduled work. For `task.spawn` and `task.delay`, this prevents future resumes of the underlying coroutine. For `UpdateService:After`, this prevents the deferred `fn` from firing. For `UpdateService:Every`, this stops the repeating interval. Idempotent; calling `Cancel` on an already-cancelled handle is a no-op. Does not yield.

```lua
local handle = task.delay(5, function()
    Logger:Info("five seconds in")
end)

if shouldAbort then
    handle:Cancel()
end

if handle.Cancelled then
    Logger:Debug("deferred task aborted")
end
```

`TaskManager:Add(taskHandle)` registers a handle and calls `:Cancel()` on it during cleanup, the same way it calls `:Disconnect()` on a `Connection` or `:Destroy()` on an engine object.

### TaskManager

`TaskManager` is the engine's general cleanup primitive. It tracks heterogeneous "things that need releasing" and releases them all in one call. The earlier shape from Roblox is called `Maid`; the LFTME name is `TaskManager` because outside Roblox `Maid` is opaque.

```lua
local tasks = LFTME.TaskManager.new()
tasks:Add(connection)
tasks:Add(spawnedObject)
tasks:Add(function() print("cleanup") end)
tasks:Cleanup()
tasks:Destroy()
```

Public surface:

- `TaskManager.new() -> TaskManager` — constructor.
- `TaskManager:Add(task) -> token` — registers a task. Returns an opaque token usable with `Remove` and `CleanupTask`.
- `TaskManager:Remove(token)` — forgets the task without releasing it. The manager drops its reference; the caller takes ownership of cleanup from that point on.
- `TaskManager:CleanupTask(token)` — releases the specific task and removes it from the manager. Other tasks are untouched.
- `TaskManager:Cleanup()` — releases every registered task in reverse insertion order. The manager is reusable after `Cleanup`.
- `TaskManager:Destroy()` — calls `Cleanup` and marks the manager unusable; further calls error.

The task argument can be any of:

- a `Connection` — `:Disconnect()` is called
- a `TaskHandle` returned by `task.spawn`, `task.delay`, `UpdateService:After`, or `UpdateService:Every` — `:Cancel()` is called
- an engine object with a `:Destroy()` method (e.g. `SpawnedObject`) — `:Destroy()` is called
- a plain function — the function is called with no arguments

Phase 1 deliberately does not accept raw `coroutine.create` / `coroutine.wrap` handles. Plain Lua coroutines cannot be forcibly cancelled in a safe, host-portable way, and silently abandoning them leaves yielded frames and retained closures behind. Code that wants its background work to be cancellable through a `TaskManager` must go through `task.spawn` (or one of the other helpers above) so it gets back a real `TaskHandle`.

Per-player `TaskManager` instances are created automatically by `Players` when a player joins and reachable at `player.TaskManager`. The lifecycle around departure is precise: during `PlayerLeftServer` dispatch, `player.TaskManager` is still fully accessible — handlers may read it, add last-minute tasks, or invoke methods on it. After every `PlayerLeftServer` handler has finished, the engine calls `player.TaskManager:Destroy()`, which cleans up everything registered and marks the manager unusable. Last-minute additions made during the dispatch are released by that same `Destroy()` call, so they are useful for guaranteed-final cleanup but not for work that needs to outlive the dispatch. The common pattern is:

```lua
Players.PlayerJoinedServer:Connect(function(player)
    player.TaskManager:Add(Chat.MessageReceived:Connect(function(sender, msg)
        if sender == player then
            print(msg)
        end
    end))
end)
```

The connection is released automatically when the player leaves, with no explicit `Disconnect` in user code.

### Enum

`Enum` is the engine's namespaced enum table. Concrete enum members are reached as `Enum.Category.Member`:

```lua
local Enum = LFTME.Enum
local pattern = Enum.SpawnPattern.Circle
local crate = Enum.Block.MetalCrate
```

Each enum member is a singleton table with `Name`, `Value`, and an `EnumType` back-reference. Equality is identity (`Enum.Block.MetalCrate == Enum.Block.MetalCrate`). Stringification returns the fully qualified name (`Enum.Block.MetalCrate`). Phase 1 ships the enum infrastructure — the `Enum.<Category>.<Member>` access pattern, identity equality, and stringification — together with `Enum.SpawnPattern.*` and the small enums needed by ChatService and World. The `Enum.Block` table exists and the access pattern works, but Phase 1 does not ship the full block catalogue; only the members required by the examples and tests are populated. Mods that want to refer to a block whose enum member is not yet shipped should pass the canonical or fuzzy string instead — the resolver in `ObjectSpawner` handles both.

## 8. The task library

The engine ports the core Roblox task primitives: `task.wait`, `task.spawn`, and `task.delay`. All three are reached as `LFTME.task.*`, with the canonical local alias being `local task = LFTME.task`. `task.delay(seconds, fn)` is an alias for `UpdateService:After(seconds, fn)`; see section 6 for the accumulator semantics.

```lua
local task = LFTME.task

task.spawn(function()
    task.wait(2)
    print("two seconds later")
end)
```

`task.wait(seconds)` yields the current coroutine via `coroutine.yield` and schedules a resume after at least `seconds` seconds of accumulated `UpdateService.OnUpdate` deltas. The exact resume timing depends on host tick rate; the engine documents that the precision is not 60 Hz and not tied to rendering. The engine never busy-waits.

`task.spawn(fn, ...)` creates a new scheduler-managed coroutine, resumes it immediately with the trailing arguments, and returns a `TaskHandle`. The caller does not yield. If `fn` errors, the error is routed to `Logger:Error` rather than escaping silently. The returned handle exposes `:Cancel()` to stop the coroutine at its next yield point and a `Cancelled` boolean for inspection. Returning a handle is an LFTME extension over Roblox's `task.spawn`, which returns nothing useful; the extra surface is what makes `TaskManager` cleanup work cleanly for background tasks.

```lua
local handle = task.spawn(function()
    task.wait(10)
    Logger:Info("done")
end)

-- later:
handle:Cancel()
if handle.Cancelled then
    Logger:Info("cancelled the long wait")
end
```

Both functions integrate with the engine's `pcall` isolation for signal callbacks. A task that yields inside a callback works correctly because the engine resumes it from `UpdateService.OnUpdate` rather than from the signal dispatch.

Calling `task.wait` or `Signal:Wait` from a coroutine that the engine did not create — for example, a raw `coroutine.wrap` from user code — is the one place the engine actively enforces yield rules, because the yield would never be resumed otherwise. The call errors with the runtime-failure template pointing at the `task.wait` or `Signal:Wait` site (see section 4 for the format and the exact `Signal:Wait` example).

## 9. Patterns library

Spawn patterns are chainable methods on `SpawnedGroup` that lay out group members in a geometric arrangement. Built-ins ship with the engine and custom patterns can be registered.

### Built-ins

- `:Circle(radius, count)` — horizontal circle.
- `:Ring(radius, count, thickness)` — circle with optional radial jitter.
- `:Grid(rows, cols, spacing)` — 2D grid.
- `:Cube(side, count)` — volume fill.
- `:Sphere(radius, count)` — volume fill.
- `:Line(length, count)` — straight line along local X.
- `:Wall(width, height, spacing)` — vertical plane.

Each pattern places members and returns the group, so patterns themselves chain with the rest of the builder surface:

```lua
ObjectSpawner:SpawnGroup("PFB_Wall"):Wall(10, 4):Position(0, 0, 50):Rotation(0, 90, 0)
```

builds the wall, parks it, and faces it. Order matters: pattern methods compute member offsets at call time relative to the current group transform, so later `Position` or `Rotation` calls move the whole assembly together. Patterns are idempotent over their inputs and never read external state.

### Custom patterns

The patterns registry is reached through the namespace:

```lua
LuluFluffysTrailmakersModEngine.Patterns:Register("Spiral", function(group, radius, count, turns)
    for i = 1, count do
        local t = (i - 1) / count
        local theta = t * turns * 2 * math.pi
        local r = radius * t
        group:AddMember({ x = r * math.cos(theta), y = 0, z = r * math.sin(theta) })
    end
end)
```

Once registered, the pattern is available on every `SpawnedGroup` as a real method:

```lua
ObjectSpawner:SpawnGroup("PFB_Beam"):Spiral(10, 50, 3)
```

The pattern function receives `(group, ...args)` where `group` exposes the current origin, current rotation, the prefab name, and a `:AddMember(localOffset, localRotation?)` call. The function is responsible for calling `AddMember` once per desired position; the engine handles the actual host spawn calls and registry bookkeeping. Names that collide with built-ins are rejected. Patterns are scoped to the engine instance, which is a singleton, so registration is process-global by extension.

## 10. File layout and build

The engine is authored as per-class source files for clean diffs and tests, and shipped as a generated single-file bundle so modders only have to drop one file into their Trailmakers mod folder.

The source tree:

```text
src/
  init.lua
  Signal.lua
  Connection.lua
  TaskManager.lua
  datatypes/
    Vector3.lua
    Color3.lua
    MarkupText.lua
  services/
    Players.lua
    Chat.lua
    ObjectSpawner.lua
    World.lua
    Physics.lua
    Logger.lua
    ModStorage.lua
    UpdateService.lua
  util/
    Scheduler.lua
    Typecheck.lua
    Constants.lua
dist/
  LFTME.lua
  LFTME.d.lua
```

`src/init.lua` is the engine entry point, responsible for registering all services and exposing the `LuluFluffysTrailmakersModEngine` and `LFTME` globals. Per-class files are kept small (one class, one file). `util/Typecheck.lua` owns the standard error message formatter described in section 4; every service calls into it rather than hand-rolling messages.

The build step concatenates the `src/` tree into `dist/LFTME.lua`, the single file modders consume. It also emits `dist/LFTME.d.lua`, a LuaLS definition stub that IDE users can include for autocomplete and type checking without coupling the autocomplete to the runtime bundle. The bundle never relies on the host `require` semantics, because Trailmakers does not promise them.

LuaLS annotations on public API surface are mandatory in CI. A pull request that adds a public method without a matching annotation does not pass. Private helpers are not required to be annotated.

## 11. What we deliberately don't port from Roblox

LFTME is Roblox-style on purpose, but the engine drops several Roblox concepts because they do not map honestly onto Trailmakers.

There is no Instance tree, no `workspace`, no `Parent` assignment. The Trailmakers world is not a hierarchy of nameable instances rooted at a service container; it is a flat set of spawned objects plus a small number of world-level knobs. Inventing a hierarchy that does not exist in the host would mislead modders about what they can query and reparent.

There is no `RemoteEvent`, `RemoteFunction`, or any other client/server boundary primitive. Trailmakers does not expose a client/server split to mods — the mod runs in one place. Pretending otherwise would invite security and consistency assumptions the engine cannot deliver on.

There is no `Humanoid` and no `player.Character`. A Trailmakers player is a controller of vehicles, not an avatar with a body, animations, health pool, and rig. The `Player` object exposes the controls and queries that actually make sense in Trailmakers (`Teleport`, `GetPosition`, `Kick`, `Kill`, `Eject`, `SetInvincible`, `SetJetpackEnabled`) and does not pretend to have a character.

The persistence service is called `ModStorage`, never `DataStoreService`. The Roblox name carries strong durability and consistency guarantees that the local-file backing on a player's machine cannot honour. Naming it `ModStorage` keeps expectations honest.

`task.wait` precision is documented against the actual host tick rate. The engine does not claim ~60 Hz precision. `UpdateService` exposes a single `OnUpdate` signal rather than `Heartbeat`, `Stepped`, and `RenderStepped`, because the host does not currently give the engine the information to distinguish those phases. When and if it does, additional signals will land on `UpdateService` with names that describe the actual phase.

## 12. Iteration, error-message format, yield annotations

Three conventions show up in nearly every new method a contributor will write. They are gathered here in a copy-paste-ready form.

### Iteration

The canonical documented iteration form is `ipairs` over the array returned by a `Get*` method:

```lua
for _, p in ipairs(Players:GetPlayers()) do
    print(p.Name)
end
```

Every beginner-facing example uses this form. The allocation cost is real but small (one array per call) and the readability dominates.

The advanced form is the iterator function returned by `:Iterate()`:

```lua
for p in Players:Iterate() do
    print(p.Name)
end
```

`Iterate` does not allocate an intermediate array. It is documented in the performance-sensitive sections of each service and in the LuaLS annotations, but is intentionally absent from the first-contact examples to keep the learning curve gentle.

### Error message format

Every error message — whether thrown for programmer errors or returned as the `err` half of `nil, err` — follows one of the two templates introduced in section 4. The type-error template is used for parameter typechecks:

```text
<ClassOrService>:<Method>(<file>:<line>) expected <expectedType> for parameter "<paramName>", got <actualType> <actualValue>
```

The runtime-failure template is used for state-dependent failures (prefab resolution, missing players, double-construction, etc.):

```text
<ClassOrService>:<Method>(<file>:<line>) <message>
```

When formatting `<actualValue>`:

- Strings are quoted: `got string "Metal_Crate"`.
- Numbers, booleans, and `nil` are printed verbatim.
- Large tables are summarised as `got table 0x123456` or `got table with keys {Name, Position}` rather than dumped.
- Engine objects print their class name and identity (`got SpawnedObject#42`).

The file and line come from `debug.getinfo(level, "Sl")` walked back to the user's call site. Contributors should always route through `util/Typecheck.lua`'s helpers rather than concatenating error strings by hand — otherwise the format drifts over time.

### Yield annotations

Every public method is annotated with whether it yields. The annotation lives in the LuaLS doc comment immediately above the function. Concrete examples a contributor can copy:

```lua
---@param fn fun(...): any
---@return LFTME.Connection
--- Does not yield.
function Signal:Connect(fn) end

--- Yields the current coroutine until the next fire. Returns the fire arguments.
function Signal:Wait() end

---@param seconds number
--- Yields the current coroutine for at least the given number of seconds.
function task.wait(seconds) end

---@param fn fun(...): any
--- Does not yield the caller.
function task.spawn(fn, ...) end
```

The annotation is documentation, not runtime enforcement. The only case the engine guards at runtime is `task.wait` outside a scheduler-managed coroutine — because that case is silent in production and would otherwise produce a wait that never resumes.

## 13. Phase 1 scope

Phase 1 ships the core surface that a real mod can be built against. It is deliberately small. Later phases extend the spawn library, the enum tables, and the persistence service, but Phase 1 has to be self-sufficient — a mod that targets Phase 1 should keep working untouched in Phase 2.

The Phase 1 deliverables are:

- `LFTME.New()` and `LFTME.Get()` with singleton enforcement. A second `New()` errors with the standard format. `Get()` returns `nil, err` before the engine is constructed.
- The `engine:GetService(name)` lookup and service singletons within the engine instance.
- `Signal` and `Connection` classes with `Connect`, `Once`, `Wait`, `Disconnect`, and `pcall` isolation of user callbacks.
- `TaskManager` with `Add`, `Remove`, `Cleanup`, `Destroy`. Per-player `player.TaskManager` created and destroyed automatically by `Players`.
- The `task` library: `task.wait(seconds)` and `task.spawn(fn, ...)`. Both driven by `UpdateService.OnUpdate`.
- `UpdateService` exposing `OnUpdate` (driven by the host global `update(dt)` callback) plus the time helpers `After`, `Every`, and the `task.delay` alias. Weaker-than-Roblox guarantees documented.
- The `Enum` skeleton with the categories needed by Phase 1 services (`Enum.SpawnPattern`, the small enums for chat and world).
- `Vector3` and `Color3` data types, with the operations listed in section 5.
- `MarkupText` chainable builder reachable as `LuluFluffysTrailmakersModEngine.MarkupText`.
- `Players` service with `PlayerJoinedServer`, `PlayerLeftServer`, `GetPlayers`, `FindByName`, `FindById`, `Iterate`. `Player` objects with `Name`, `Id`, `TaskManager`, `Teleport`, `Kick`, `Kill`, `Eject`, `SetTeam`, `SetInvincible`, `SetJetpackEnabled`, `SpawnObjectNearby`, `GetPosition`, `IsInSeat`.
- `Chat` service with `SendMessage` (plus the deprecated `SendMessageTo` alias), `BroadcastToAll` (positional and chainable builder forms), and the `MessageReceived` signal. Echo suppression hidden inside the wrapper. Six-line chat panel cap documented. HTML-style tags accepted only on intrusive popups.
- `ObjectSpawner` service with `SpawnObject`, `SpawnGroup`, `ResolvePrefab`, and the fuzzy resolution order from section 6. Built-in patterns: `Circle`, `Ring`, `Grid`, `Cube`, `Sphere`, `Line`, `Wall`. Custom pattern registration via `LuluFluffysTrailmakersModEngine.Patterns:Register`. Optional `engine.Settings.WarnOnRawPrefabStrings`.
- `World` service with gravity, time scale, time of day, wind, and map name accessors.
- `Logger` service writing to `logs.txt` via `tm.os.WriteAllText_Dynamic`, with `Debug`, `Info`, `Warn`, `Error` methods. Engine-internal callback errors routed through `Logger:Error`.
- `ModStorage` service with `Get` and `Set` against a local file backing.
- The standard error message formatter in `util/Typecheck.lua` and its use everywhere the engine raises or returns errors.
- The single-file bundle `dist/LFTME.lua` and the IDE definition stub `dist/LFTME.d.lua`.

Reserved for later phases: `Physics` raycasts and overlaps (waiting on host support), the broader `Enum.Block.*` catalogue beyond the members required by Phase 1 examples and tests, a descriptor-table return from `ObjectSpawner:ResolvePrefab` carrying canonical name, enum value, and display name, additional spawn patterns, a streaming `Logger` sink, and any pre-physics or post-physics signal on `UpdateService` that the host might eventually make distinguishable.

## Appendix A: Worked example — a small mod end to end

A short worked example helps tie the previous sections together. The mod below welcomes each joining player by name, drops a small ring of crates above their head as a greeting, listens for a `!leave` chat command to kick the speaker, and logs everything to `logs.txt`. It uses every Phase 1 service and shows the canonical idioms in one place.

```lua
local engine = LFTME.New()

local Players = engine:GetService("Players")
local Chat = engine:GetService("Chat")
local ObjectSpawner = engine:GetService("ObjectSpawner")
local Logger = engine:GetService("Logger")
local UpdateService = engine:GetService("UpdateService")

local Vector3 = LFTME.Vector3
local MarkupText = LuluFluffysTrailmakersModEngine.MarkupText
local task = LFTME.task
```

The opening block constructs the singleton, fetches every service the mod uses, and pulls local aliases for the namespace-level helpers. The aliases at the top of the file are the canonical idiom — they are short, they document the surface in use, and they avoid scattering `LFTME.` and `LuluFluffysTrailmakersModEngine.` across the body.

```lua
Players.PlayerJoinedServer:Connect(function(player)
    Logger:Info(player.Name .. " joined")

    local greeting = MarkupText.new("Welcome, " .. player.Name .. "!"):Bold()
    Chat:BroadcastToAll("Greeting", tostring(greeting))

    local position = player:GetPosition() + Vector3.new(0, 5, 0)
    local group = ObjectSpawner:SpawnGroup("PFB_Metal_Crate")
        :Circle(3, 6)
        :Position(position.X, position.Y, position.Z)

    player.TaskManager:Add(group)
end)
```

The handler does four things in order. First, it logs the join through `Logger:Info`. Second, it builds a styled intrusive popup using `MarkupText` and broadcasts it. Third, it spawns a six-crate horizontal ring three units across, parked five units above the player's head, using `SpawnGroup` with the `Circle` pattern. Fourth — and this is the load-bearing line — it adds the spawned group to `player.TaskManager`. When the player leaves, the engine releases the `TaskManager`, which calls `Destroy` on the group, which removes every crate. No leak, no manual cleanup, no `PlayerLeftServer` handler needed for this resource.

```lua
Chat.MessageReceived:Connect(function(player, msg)
    if msg == "!leave" then
        Logger:Info(player.Name .. " requested kick")
        player:Kick("you asked nicely")
    end
end)
```

The chat handler is intentionally minimal. It matches a literal command string and calls `player:Kick(reason)`. The mutator-returns-self rule applies — `Kick` returns `self` — but the chain terminates here because there is nothing else to chain on a player that is being kicked. Note that the `MessageReceived` signal handler does not see the engine's own `Chat:SendMessage` calls: echo suppression in the chat service eats them so user code does not have to.

```lua
local elapsed = 0
UpdateService.OnUpdate:Connect(function(deltaTime)
    elapsed = elapsed + deltaTime
    if elapsed >= 30 then
        elapsed = 0
        Logger:Debug("heartbeat — " .. #Players:GetPlayers() .. " players online")
    end
end)
```

The final block uses `UpdateService.OnUpdate` to log a heartbeat every thirty seconds of accumulated tick time. The deliberate phrasing is "thirty seconds of accumulated tick time" rather than "every thirty seconds" — `OnUpdate` is honest about not being a 60 Hz wall clock. If the host is paused or slowed, the heartbeat slows with it.

That is the entire mod. There is no boilerplate cleanup, no `tm.*` call, no manual `Disconnect` chain, no echo suppression, no prefab resolver. The engine absorbs all of it.

## Appendix B: Boundary rule — service versus player object

The split between methods on a service and methods on a player object is worth restating because it shows up in nearly every API discussion. Methods on a service (`Chat:SendMessage`, `Players:FindByName`, `ObjectSpawner:SpawnObject`) represent the engine acting on the world or the caller asking the engine for information. Methods on a player object (`player:Kick`, `player:Teleport`, `player:GetPosition`) represent the player as the actor or the data source.

The rule shapes API design in two places. First, inbound chat fires on the service (`Chat.MessageReceived`), not on the player object, because `player.MessageReceived` would read as "the player has a message received event" — which they do not; the chat panel does. Second, the spawn API is on `ObjectSpawner` rather than on the player even when spawning happens near a player, because the actor is the engine, not the player.

The same reasoning is why `player:SendChatMessage(text)` would be wrong. It would suggest the player is doing the chatting, when in fact the engine is sending a chat panel line attributed to the configured sender name. The actual API is `Chat:SendMessage(text)` — the engine is the actor and the chat panel is the surface.

There is no player on either side of that call, and that is the second half of the rule: a parameter should only exist if the host can honour it. The deprecated `Chat:SendMessageTo(player, text)` took a `player` argument purely because the shape looked symmetrical with the rest of the API, but Trailmakers only broadcasts, so the argument was decorative. A parameter the engine silently ignores is worse than no parameter at all — it teaches callers a targeting model that does not exist.

## Appendix C: Settings table

The engine exposes a small `engine.Settings` table for opt-in policy. It is documented here as a single reference. Reading from it is always safe; writing should happen once during mod startup before any other engine calls.

- `engine.Settings.WarnOnRawPrefabStrings` (boolean, default `false`) — when true, the engine emits a `Logger:Warn` for every raw prefab string passed to `ObjectSpawner:SpawnObject` or `SpawnGroup`. Useful for authors enforcing strict enum-only discipline; intentionally noisy.
- `engine.Settings.LogLevel` (string, default `"Info"`) — the minimum `Logger` level that is written. Accepts `"Debug"`, `"Info"`, `"Warn"`, `"Error"`. Calls below the threshold are dropped before any file I/O.
- `engine.Settings.ChatEchoSuppressionTTL` (number, default `0.25`) — the time-to-live in seconds for entries in the chat echo suppression map. Lower values reduce memory pressure on chat-heavy servers; higher values are safer against laggy host echoes. Tuned conservatively by default.

Future phases may add more settings; the contract is that adding a new setting with a sensible default is not a breaking change, and that removing or renaming one is.

## Appendix D: Contributor checklist for adding a new public method

A short checklist contributors can run through when adding a new public method to any service or class. The list is the working set of conventions from the rest of this document, gathered into one place.

The method name follows the PascalCase / `Get*` / `Find*` / `Has*` / `Is*` conventions from section 3. Setter-style verbs chain by returning `self`; query-style verbs return their result. Constructors are `.new` on the relevant class and return the new instance.

Every parameter is type-checked through `util/Typecheck.lua` rather than by hand. The check produces the standard error message from section 4 on failure. Programmer errors throw; expected runtime failures return `nil, err`. The error string includes the file and line of the user's call site via `debug.getinfo`.

The LuaLS annotation block above the function declares parameter types, return types, and the yield/no-yield documentation line. The annotation is mandatory in CI for public surface. Private helpers are encouraged but not required to be annotated.

If the method does any work that can outlive the call (a connection, a spawned object, a deferred task), it either returns a handle the caller can release, or it accepts a `TaskManager` to register against. The engine does not silently retain user-visible resources.

If the method is a signal handler entry point (a `Connect` callback the user supplies), the dispatch site wraps it in `pcall` and routes thrown errors to `Logger:Error`. One bad handler never aborts the dispatch.

If the method touches the host `tm.*` API, it does so through the appropriate service's private wrapper rather than reaching out directly. The boundary between engine and host is one place in the source per host call, which makes future host changes a localised edit.

Tests live next to the source file as `<ClassName>_test.lua`. The test suite exercises the happy path, every documented error path with its exact error string, and the yield/no-yield behaviour where it differs from the obvious default. When asserting against error strings, tests should match the message body exactly but allow the file and line portion of the prefix to vary, unless the test injects a stable callsite (for example by calling through a fixture function at a known location). Pinning the literal `<file>:<line>` of every error in tests makes the suite brittle to unrelated edits in the file under test and is not the intent of the standard format; the standard format exists so users see useful callsites, not so tests can hash them.

The change ships with a doc update either in this design document (for new public conventions) or in the per-service section that owns the method (for a new method on an existing service). A pull request that adds a method without a doc update does not pass review.
