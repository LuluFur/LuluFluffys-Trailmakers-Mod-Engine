--------------------------------------------------------------------------------
-- LuluFluffy's Trailmakers Mod Engine (LFTME)
--
-- This file is a friendly wrapper around Trailmakers' built-in modding
-- API (the `tm.*` functions). Trailmakers' raw API works, but it is a
-- bit bare. LFTME reshapes it into something that looks and feels like
-- Roblox Studio scripting, so you can spawn objects, listen for chat,
-- react to players joining, and save data without ever typing `tm.`
-- yourself.
--
-- HOW YOUR MOD LOADS THIS FILE
--   Drop this file into your mod's `data_static/` folder. Then in your
--   own `main.lua`, load it once at the very top:
--
--       local LFTME = tm.os.DoFile("engine.lua")
--       local engine = LFTME.New()
--
--   `tm.os.DoFile` looks inside `data_static/` for the file. Trailmakers
--   does not support subfolders inside `data_static/`, so the engine is
--   one flat file -- everything you need is right here.
--
-- HOW THIS FILE IS LAID OUT
--   It reads top-to-bottom in the order things depend on each other.
--   Skim the section banners to find what you want:
--
--     1. Internal helpers (type checks, error formatting, debug helpers)
--     2. Signal / Connection (the event object every service uses)
--     3. Data types: Vector3, Color3, MarkupText
--     4. Logger (writes messages to a file, with severity levels)
--     5. Scheduler, the task library, and UpdateService
--     6. TaskManager (a tidy clean-these-things-up-later helper)
--     7. Players service (the Player object, join/leave events, lookups)
--     8. Chat service (chat lines + on-screen popups + inbound messages)
--     9. ObjectSpawner service (spawn props and move them around)
--    10. The Engine itself (LFTME.New / LFTME.Get / GetService)
--    11. Public type table (the data types you can use from your mod)
--    12. Globals + the value returned by this file
--
--   Names you use in your own code are PascalCase (`Vector3.new`,
--   `engine:GetService`). Names that start with `_` are private to the
--   engine -- do not touch them. Constants are LOUD_SNAKE_CASE.
--
-- A FEW GROUND RULES THE ENGINE FOLLOWS
--   * One engine per mod. Calling `LFTME.New()` twice is an error.
--   * If you make a mistake (wrong type, wrong arg), the engine throws
--     a clear error pointing at YOUR line of code. If something just
--     cannot be done right now (file missing, etc.) it returns `nil`
--     plus an error message instead of throwing.
--   * One broken event handler does not break the others -- the engine
--     catches errors per-handler so the rest still run.
--   * Vector3, Color3 and MarkupText are immutable. Doing math on them
--     gives you a brand-new value rather than changing the original.
--
-- For the full design write-up, see DESIGN.md.
--------------------------------------------------------------------------------

-- This is the one table the whole file fills in and hands back at the end.
-- Two global names (`LuluFluffysTrailmakersModEngine` and the short alias
-- `LFTME`) both point at this same table, set up near the bottom of the
-- file. Everything public lives on it.
local LFTME = {}

-- A local reference to Trailmakers' built-in `tm` table -- the underlying
-- modding API. We grab it once here so the engine has one consistent
-- handle. If we are running outside Trailmakers (for example a unit test
-- in plain Lua), `tm` may not exist -- in that case `rawget` returns nil
-- and the first time we try to call a `tm.*` function we get a clear
-- error instead of a silent crash.
local tm = rawget(_G, "tm")

-- A couple of variables that more than one section below needs to share.
-- They have to be declared up here because in Lua, a variable has to
-- exist (lexically) before any function further down the file can reach
-- into it. Think of these as engine-wide notepad entries.

-- A list of coroutines (paused/resumable Lua functions) that the engine
-- is in charge of resuming. `task.spawn` adds entries here; `task.wait`
-- and `Signal:Wait` check it before pausing, so they can give you a
-- helpful error if you try to pause from somewhere the engine cannot
-- resume you. The `__mode = "k"` bit tells Lua to forget entries whose
-- coroutine is garbage-collected, so this list cleans itself up.
local _managedCoroutines = setmetatable({}, { __mode = "k" })

-- The single UpdateService instance, once the engine has started up.
-- The `task` library (task.spawn / task.wait / task.delay) reads this
-- directly so you do not have to call `engine:GetService("UpdateService")`
-- yourself just to schedule a delay. Stays nil until you call
-- `LFTME.New()`, which builds UpdateService automatically.
local _updateServiceInstance = nil

--------------------------------------------------------------------------------
-- 1. Internal utilities
--
-- Small private helpers the rest of the engine uses: how it figures out
-- where in YOUR code an error happened, how it formats type errors, and
-- the registry where each service plugs itself in. You do not call any
-- of this directly from a mod -- but reading it explains why engine
-- errors look the way they do.
--------------------------------------------------------------------------------

-- Look up the place in your mod where the current engine call originated.
-- The engine itself sits in this file, so we walk up the call chain (the
-- stack of who-called-who) until we find a frame whose source is not
-- engine.lua -- that is your code.
--
-- Returns a short string like "main.lua:34". If debug info is not
-- available (some sandboxed setups strip it out), returns "?:?".
local function _userCallSite()
    if not debug or not debug.getinfo then
        return "?:?"
    end
    local engineSource = debug.getinfo(1, "S").source
    -- Start at level 2 (skip _userCallSite itself), walk up until we leave
    -- engine code. Cap at a reasonable depth so we never loop forever on a
    -- corrupted stack.
    for level = 2, 20 do
        local info = debug.getinfo(level, "Sl")
        if not info then
            break
        end
        if info.source ~= engineSource then
            return (info.short_src or "?") .. ":" .. tostring(info.currentline or "?")
        end
    end
    return "?:?"
end

-- Build the prefix that every engine error message starts with. It looks
-- like `Player:Teleport(main.lua:42)` -- the engine class and method that
-- you called, plus the place in your code you called it from. Designed
-- to make debugging painless.
local function _makePrefix(className, methodName)
    return tostring(className) .. ":" .. tostring(methodName) .. "(" .. _userCallSite() .. ")"
end

-- Turn any Lua value into a short readable description for an error
-- message. Strings are quoted, numbers/booleans/nil are printed as-is,
-- and tables get a short summary (we never dump a whole table -- they
-- can be huge).
local function _describeValue(value)
    local t = type(value)
    if t == "string" then
        return 'string "' .. value .. '"'
    elseif t == "number" or t == "boolean" or t == "nil" then
        return t .. " " .. tostring(value)
    elseif t == "table" then
        -- Prefer the engine's typed class name when present.
        local className = rawget(value, "_className")
        if className then
            return tostring(className)
        end
        local addr = tostring(value):match("0x%x+")
        return "table " .. (addr or "")
    else
        return t
    end
end

-- Throw an error explaining that an argument was the wrong type. Used
-- whenever the engine checks did you pass me a string here and the
-- answer is no.
local function _typeError(className, methodName, paramName, expectedType, actualValue)
    error(string.format(
        '%s expected %s for parameter "%s", got %s',
        _makePrefix(className, methodName),
        expectedType,
        paramName,
        _describeValue(actualValue)
    ), 0)
end

-- Build (but do not throw) a runtime-failure message. The caller chooses
-- whether to throw it (for a real bug) or return it alongside `nil`
-- (for an expected, recoverable failure -- like "file not found").
local function _runtimeError(className, methodName, message)
    return _makePrefix(className, methodName) .. " " .. message
end

-- A quick "is this a Vector3 / Color3 / Player / ..." check. Every engine
-- object has a `_className` field with its name; we just read that, which
-- is faster than asking Lua to walk metatables (Lua's mechanism for
-- attaching custom behavior to a table) and works even on copies.
local function _isInstanceOf(value, className)
    return type(value) == "table" and rawget(value, "_className") == className
end

-- Make sure an argument is a plain Lua type ("string", "number",
-- "boolean", "function", ...). If not, throw a clear error pointing at
-- where you called from.
local function _expectType(className, methodName, paramName, expected, value)
    if type(value) ~= expected then
        _typeError(className, methodName, paramName, expected, value)
    end
end

-- Make sure an argument is a specific engine object (like a Vector3 or
-- a Player). If not, throw a clear error pointing at where you called from.
local function _expectInstance(className, methodName, paramName, expected, value)
    if not _isInstanceOf(value, expected) then
        _typeError(className, methodName, paramName, expected, value)
    end
end

-- The list of services the engine knows how to build. Each entry is
-- something like "Players" mapped to a function that builds the Players
-- service the first time someone asks for it.
--
-- A "service" here means a long-lived helper like Players, Chat, or
-- Logger. The engine builds each one only when you first ask for it via
-- `engine:GetService("...")`, then re-uses that same instance forever.
--
-- This list lives way up here (not next to the Engine code lower down)
-- because some services register themselves the moment the file loads,
-- and that registration needs the registry to already exist.
local _serviceFactories = {}

-- Add a service to the registry. Each service section calls this when
-- the file loads, but the factory function does not actually run until
-- someone calls `engine:GetService("...")` for that service.
function LFTME._registerService(name, factory)
    _expectType("LFTME", "_registerService", "name", "string", name)
    _expectType("LFTME", "_registerService", "factory", "function", factory)
    _serviceFactories[name] = factory
end


--------------------------------------------------------------------------------
-- 2. Signal and Connection
--
-- A Signal is an "event" object: it lets you say "when X happens, run
-- this function". This is the same shape Roblox uses, so if you have
-- used `:Connect(fn)` there, this will feel familiar.
--
-- The four things you can do with a Signal:
--   conn = signal:Connect(fn)   -- run fn every time the event fires
--   conn = signal:Once(fn)      -- run fn once, then auto-unsubscribe
--   args = signal:Wait()        -- pause your task until the next fire
--   signal:Fire(...)            -- engine uses this; your mod does not
--
-- When you call `:Connect(fn)` you get back a Connection. Hold on to it
-- if you want to stop listening later (call `conn:Disconnect()`). The
-- Connection also has a `.Connected` field you can check.
--
-- If one of your event-handler functions throws an error, the engine
-- catches it so the other handlers on the same signal still run. The
-- error is sent to the Logger (or `print` if Logger is not set up yet).
--------------------------------------------------------------------------------

local Connection = {}
Connection.__index = Connection

-- Internal: build a new Connection. You never call this yourself -- you
-- get a Connection by calling `signal:Connect(fn)` or `signal:Once(fn)`.
-- The `_signal` and `_fn` fields are used by the engine when firing or
-- disconnecting; treat them as private.
local function _newConnection(signal, fn)
    return setmetatable({
        _className = "Connection",
        _signal = signal,
        _fn = fn,
        Connected = true,
    }, Connection)
end

-- Stop listening to the Signal. After this, the function you connected
-- will not run again. Safe to call more than once -- a second
-- `:Disconnect()` does nothing instead of erroring.
function Connection:Disconnect()
    if not self.Connected then
        return
    end
    self.Connected = false
    local handlers = self._signal._handlers
    for i = #handlers, 1, -1 do
        if handlers[i] == self then
            table.remove(handlers, i)
            break
        end
    end
    self._fn = nil
    self._signal = nil
end

local Signal = {}
Signal.__index = Signal

-- Internal: build a new Signal. Services create their own Signals when
-- they are first built, and expose them as fields like
-- `Players.PlayerJoinedServer`.
local function _newSignal(name)
    return setmetatable({
        _className = "Signal",
        _name = name or "Signal",
        _handlers = {},     -- array of Connection
        _waiters = {},      -- array of coroutine threads parked on Wait()
    }, Signal)
end

-- Run `fn` every time this Signal fires. Returns a Connection -- keep
-- it if you might want to stop listening later by calling
-- `connection:Disconnect()`. This is the bread-and-butter "listen for
-- an event" call.
function Signal:Connect(fn)
    _expectType("Signal", "Connect", "fn", "function", fn)
    local conn = _newConnection(self, fn)
    table.insert(self._handlers, conn)
    return conn
end

-- Run `fn` the very next time this Signal fires, then automatically
-- disconnect. Handy for one-shot things like "wait for the first player
-- to join, then run this once".
function Signal:Once(fn)
    _expectType("Signal", "Once", "fn", "function", fn)
    local conn
    conn = self:Connect(function(...)
        conn:Disconnect()
        fn(...)
    end)
    return conn
end

-- Pause the current task until the next time the Signal fires, then
-- return whatever arguments the signal fired with. You can only call
-- this from inside a `task.spawn(function() ... end)` -- a normal
-- top-level function has no way to pause and resume itself later, so
-- the engine throws a clear error if you try to call `:Wait()` from
-- the wrong place. (A "task" here means a coroutine -- a Lua function
-- the engine can pause and resume. `task.spawn` makes one for you.)
function Signal:Wait()
    local co, isMain = coroutine.running()
    if not co or isMain or _managedCoroutines[co] == nil then
        error(_runtimeError(
            "Signal", "Wait",
            "cannot yield from an unmanaged coroutine. Use task.spawn(function() ... end)."
        ), 0)
    end
    table.insert(self._waiters, co)
    return coroutine.yield()
end

-- Fire the signal -- call every connected function with the given args.
-- The engine uses this internally; your mod should not call `:Fire` on
-- a signal owned by a service like `Chat` or `Players`. Each handler
-- runs inside a safety wrapper, so if one throws an error the others
-- still run.
function Signal:Fire(...)
    -- Copy the handler list before looping over it. A handler is allowed
    -- to disconnect itself (or another handler) mid-fire, and if we
    -- iterated the original list directly that would shuffle entries
    -- under our feet and we could miss some.
    local snapshot = {}
    for i = 1, #self._handlers do
        snapshot[i] = self._handlers[i]
    end
    for i = 1, #snapshot do
        local conn = snapshot[i]
        if conn.Connected then
            local ok, err = pcall(conn._fn, ...)
            if not ok then
                -- Send the error to the Logger if one exists; otherwise
                -- fall back to the in-game console or plain `print`.
                local logger = LFTME._logger
                if logger then
                    logger:Error("Signal '" .. self._name .. "' handler error: " .. tostring(err))
                elseif tm and tm.os and tm.os.Log then
                    tm.os.Log("[LFTME] Signal '" .. self._name .. "' handler error: " .. tostring(err))
                else
                    print("[LFTME] Signal '" .. self._name .. "' handler error: " .. tostring(err))
                end
            end
        end
    end
    -- Wake up any tasks that called `signal:Wait()`. Each gets the same
    -- arguments the signal was fired with, just like a `:Connect`
    -- handler would.
    if #self._waiters > 0 then
        local waiters = self._waiters
        self._waiters = {}
        for i = 1, #waiters do
            local ok, err = coroutine.resume(waiters[i], ...)
            if not ok then
                local logger = LFTME._logger
                if logger then
                    logger:Error("Signal '" .. self._name .. "' Wait() resume error: " .. tostring(err))
                else
                    print("[LFTME] Signal '" .. self._name .. "' Wait() resume error: " .. tostring(err))
                end
            end
        end
    end
end

--------------------------------------------------------------------------------
-- 3. Data types
--
-- Three small value types you use throughout the engine:
--   * Vector3     -- a 3D point, direction, or size (X, Y, Z numbers)
--   * Color3      -- an RGB color (R, G, B as 0..1 numbers)
--   * MarkupText  -- a builder for HTML-style text in on-screen popups
--
-- These are immutable from a mod's perspective: adding two Vector3s, for
-- example, gives you a fresh Vector3 rather than changing either input.
-- They use Lua's metatables (Lua's way of giving a table custom behavior
-- like math operators), so you can write `a + b` for vectors and the
-- engine handles the rest.
--------------------------------------------------------------------------------

-- Vector3 -- a 3D point, direction, or size. Build one with Vector3.new(x, y, z).
local Vector3 = {}
Vector3.__index = Vector3

-- Make a new Vector3 with the given X, Y, Z. Any component you leave out
-- defaults to 0, so `Vector3.new()` is a zero vector and
-- `Vector3.new(0, 1, 0)` is a useful "up" vector.
function Vector3.new(x, y, z)
    return setmetatable({
        _className = "Vector3",
        X = x or 0,
        Y = y or 0,
        Z = z or 0,
    }, Vector3)
end

-- `a + b` for vectors -- returns a brand new Vector3 with the components
-- added together. Neither input is changed. Throws an error if you try
-- to add something that is not a Vector3.
function Vector3.__add(a, b)
    _expectInstance("Vector3", "__add", "rhs", "Vector3", b)
    return Vector3.new(a.X + b.X, a.Y + b.Y, a.Z + b.Z)
end

-- `a - b` for vectors -- returns a brand new Vector3 with the components
-- subtracted. Neither input is changed.
function Vector3.__sub(a, b)
    _expectInstance("Vector3", "__sub", "rhs", "Vector3", b)
    return Vector3.new(a.X - b.X, a.Y - b.Y, a.Z - b.Z)
end

-- Multiply a vector by a number -- scales all three components.
-- Both `v * 2` and `2 * v` work the same way.
function Vector3.__mul(a, b)
    if type(a) == "number" then
        return Vector3.new(b.X * a, b.Y * a, b.Z * a)
    elseif type(b) == "number" then
        return Vector3.new(a.X * b, a.Y * b, a.Z * b)
    else
        _typeError("Vector3", "__mul", "rhs", "number", b)
    end
end

-- `a == b` -- true only if all three components match exactly. Heads up:
-- two vectors that LOOK equal might not actually be `==` if one was
-- built from arithmetic, because floating-point math has tiny rounding
-- errors. If you care about "almost equal", compare with a small
-- tolerance.
function Vector3.__eq(a, b)
    return a.X == b.X and a.Y == b.Y and a.Z == b.Z
end

-- What `print(v)` and `tostring(v)` show -- e.g. `Vector3(1, 2, 3)`.
-- Trailing zeros are trimmed so it stays readable.
function Vector3.__tostring(v)
    return string.format("Vector3(%g, %g, %g)", v.X, v.Y, v.Z)
end

-- Length of the vector -- how far it is from (0, 0, 0). Useful for
-- distance checks: `(playerPos - targetPos):Magnitude()` gives you the
-- distance between two points.
function Vector3:Magnitude()
    return math.sqrt(self.X * self.X + self.Y * self.Y + self.Z * self.Z)
end

-- A vector pointing the same way but with length 1. Useful when you
-- want just a "direction" without a "distance". If the vector is
-- exactly zero (no direction at all), this returns (0, 0, 0) -- check
-- first if that matters to you.
function Vector3:Unit()
    local mag = self:Magnitude()
    if mag == 0 then
        return Vector3.new(0, 0, 0)
    end
    return Vector3.new(self.X / mag, self.Y / mag, self.Z / mag)
end

-- Dot product -- returns a single number. A quick way to ask "are these
-- two vectors pointing the same way?". Positive means roughly same
-- direction, zero means at right angles, negative means roughly opposite.
function Vector3:Dot(other)
    _expectInstance("Vector3", "Dot", "other", "Vector3", other)
    return self.X * other.X + self.Y * other.Y + self.Z * other.Z
end

-- Cross product -- returns a new Vector3 that points at right angles to
-- both inputs. Order matters: `a:Cross(b)` is the opposite of
-- `b:Cross(a)`. Common uses: figuring out which way a surface faces,
-- or whether one direction is to the "left" or "right" of another.
function Vector3:Cross(other)
    _expectInstance("Vector3", "Cross", "other", "Vector3", other)
    return Vector3.new(
        self.Y * other.Z - self.Z * other.Y,
        self.Z * other.X - self.X * other.Z,
        self.X * other.Y - self.Y * other.X
    )
end

-- Blend smoothly from this vector to `other`. `alpha = 0` gives you
-- self, `alpha = 1` gives you `other`, `alpha = 0.5` is halfway between.
-- Values outside 0..1 keep going past the endpoints.
function Vector3:Lerp(other, alpha)
    _expectInstance("Vector3", "Lerp", "other", "Vector3", other)
    _expectType("Vector3", "Lerp", "alpha", "number", alpha)
    return Vector3.new(
        self.X + (other.X - self.X) * alpha,
        self.Y + (other.Y - self.Y) * alpha,
        self.Z + (other.Z - self.Z) * alpha
    )
end

-- Color3 -- an RGB color. The R, G, B fields are each a number in the
-- range 0..1 (so half-red is 0.5, not 128).
local Color3 = {}
Color3.__index = Color3

-- Internal: keep a color component in the 0..1 range. We silently clamp
-- anything outside (rather than throwing an error) because color math
-- routinely produces tiny floating-point overshoots like 1.0000001, and
-- crashing on that would be obnoxious.
local function _clamp01(n)
    if n < 0 then return 0 end
    if n > 1 then return 1 end
    return n
end

-- Make a color from R, G, B values, each in the 0..1 range.
function Color3.new(r, g, b)
    return setmetatable({
        _className = "Color3",
        R = _clamp01(r or 0),
        G = _clamp01(g or 0),
        B = _clamp01(b or 0),
    }, Color3)
end

-- Make a color from R, G, B byte values in the 0..255 range. This is
-- the form you will usually paste in from a color picker or design tool.
function Color3.fromRGB(r, g, b)
    return Color3.new((r or 0) / 255, (g or 0) / 255, (b or 0) / 255)
end

-- `a == b` for colors -- true only if R, G, B all match exactly. Same
-- floating-point caveat as Vector3 equality: two colors that LOOK equal
-- may not be `==` if one came out of arithmetic.
function Color3.__eq(a, b)
    return a.R == b.R and a.G == b.G and a.B == b.B
end

-- What `print(c)` shows -- e.g. `Color3(1, 0.5, 0)`. Components are in
-- the 0..1 range, NOT 0..255.
function Color3.__tostring(c)
    return string.format("Color3(%g, %g, %g)", c.R, c.G, c.B)
end

-- Blend smoothly from this color to `other`. `alpha = 0` is self,
-- `alpha = 1` is `other`, `alpha = 0.5` is halfway. Handy for fading
-- between two colors over time.
function Color3:Lerp(other, alpha)
    _expectInstance("Color3", "Lerp", "other", "Color3", other)
    _expectType("Color3", "Lerp", "alpha", "number", alpha)
    return Color3.new(
        self.R + (other.R - self.R) * alpha,
        self.G + (other.G - self.G) * alpha,
        self.B + (other.B - self.B) * alpha
    )
end

-- Get the color as a "#RRGGBB" hex string. Handy when you want to log
-- the color or splice it into a chat message.
function Color3:ToHex()
    return string.format("#%02X%02X%02X",
        math.floor(self.R * 255 + 0.5),
        math.floor(self.G * 255 + 0.5),
        math.floor(self.B * 255 + 0.5)
    )
end

-- MarkupText -- a tiny builder for HTML-style formatting on the
-- intrusive popups Trailmakers shows. Start with `MarkupText.new("hi")`,
-- then chain tag methods like `:Bold()` or `:Italic()`. The first tag
-- you add becomes the inner tag; later ones wrap around it.
--
-- Each chained call returns a NEW MarkupText (the original is
-- unchanged), so you can reuse a partially-built piece in two places
-- without one modifying the other:
--
--   local greeting = MarkupText.new("Hello"):Bold()
--   local loud  = greeting:Italic()   -- <i><b>Hello</b></i>
--   local quiet = greeting:Small()    -- <small><b>Hello</b></small>
local MarkupText = {}
MarkupText.__index = MarkupText

-- Wrap a plain string in a MarkupText so you can chain tag methods on
-- it. The input is stored as-is, so if the text comes from a player
-- (chat input, names) run it through `MarkupText.escape` first to
-- stop HTML-like characters from breaking the formatting.
function MarkupText.new(text)
    _expectType("MarkupText", "new", "text", "string", text)
    return setmetatable({
        _className = "MarkupText",
        _text = text,
    }, MarkupText)
end

-- Returns the assembled string. Defining this means a MarkupText can be
-- used directly anywhere a string is expected -- string concatenation,
-- `print(...)`, and Trailmakers' own API all just work.
function MarkupText.__tostring(m)
    return m._text
end

-- Internal: wrap the current text in `<tag>...</tag>` and return a new
-- MarkupText. Each tag method (`:Bold`, `:Italic`, ...) is just a
-- one-liner that calls this with the right tag name.
local function _wrap(self, tag)
    return setmetatable({
        _className = "MarkupText",
        _text = "<" .. tag .. ">" .. self._text .. "</" .. tag .. ">",
    }, MarkupText)
end

-- Make the text bold. Returns a new MarkupText.
function MarkupText:Bold()    return _wrap(self, "b")      end
-- Same as Bold but uses the `<strong>` tag -- visually identical in
-- popups; pick whichever name reads better in your code.
function MarkupText:Strong()  return _wrap(self, "strong") end
-- Make the text italic. Returns a new MarkupText.
function MarkupText:Italic()  return _wrap(self, "i")      end
-- Same as Italic but uses the `<em>` tag -- pick whichever name reads
-- better in your code.
function MarkupText:Em()      return _wrap(self, "em")     end
-- Highlight the text (like a yellow marker). Returns a new MarkupText.
function MarkupText:Mark()    return _wrap(self, "mark")   end
-- Make the text smaller. Returns a new MarkupText.
function MarkupText:Small()   return _wrap(self, "small")  end

-- Escape special HTML characters (`<`, `>`, `&`, quotes) in a string so
-- they show up as plain text inside a popup instead of being treated
-- as formatting. ALWAYS run player-typed text or player names through
-- this before adding them to a popup body -- otherwise a player named
-- `<b>OOPS` would break your formatting.
function MarkupText.escape(text)
    _expectType("MarkupText", "escape", "text", "string", text)
    local out = text
    out = out:gsub("&", "&amp;")
    out = out:gsub("<", "&lt;")
    out = out:gsub(">", "&gt;")
    out = out:gsub('"', "&quot;")
    out = out:gsub("'", "&#39;")
    return out
end

--------------------------------------------------------------------------------
-- 4. Logger
--
-- Writes messages to `logs.txt` in your mod's dynamic storage folder
-- (`data_dynamic_willNotBeUploadedToWorkshop/`). Has four severity
-- levels, from least to most serious: Debug, Info, Warn, Error.
--
-- Get it like any other service:
--     local Logger = engine:GetService("Logger")
--     Logger:Info("hello, world")
--
-- HEADS UP: The in-memory buffer is capped at 200 lines by default
-- (see `Logger:SetBufferSize`). This means `logs.txt` holds only the
-- last 200 lines of your session, not the whole session history. For
-- a long-running session that logs heavily, raise the buffer size with
-- `Logger:SetBufferSize(n)`, or lower the minimum log level with
-- `Logger:SetMinLevel("Info")` to filter out Debug noise.
--
-- File writes are throttled to ~1 second intervals by default (see
-- `Logger:SetFlushInterval`). Error-level lines flush immediately to
-- prevent losing the last log line before a crash. Force a write
-- anytime with `Logger:Flush()`.
--
-- The very first Logger built also gets stashed in `LFTME._logger` so
-- the engine's internal error paths (like the Signal error catcher
-- in section 2) can find it without going through `GetService`.
--------------------------------------------------------------------------------

local Logger = {}
Logger.__index = Logger

-- Numeric values for each severity level. A message at a level lower
-- than `self._minLevel` is silently dropped (so you can tune chattiness).
local _LOG_LEVELS = { Debug = 1, Info = 2, Warn = 3, Error = 4 }

-- The default filename inside the mod's dynamic storage folder.
-- Trailmakers resolves these paths relative to that folder for us, so
-- just the filename is enough -- no folder prefix needed.
local DEFAULT_LOG_PATH = "logs.txt"

-- Internal: build a new Logger. You should not call this -- go through
-- `engine:GetService("Logger")` instead, which gives you the same
-- single Logger every time.
local function _newLogger()
    return setmetatable({
        _className = "Logger",
        _lines = {},        -- the ring buffer (pre-allocated to _bufferSize)
        _count = 0,         -- number of valid lines in the ring (0.._bufferSize)
        _pos = 1,           -- next write position (1.._bufferSize)
        _bufferSize = 200,  -- max lines to keep in memory
        _flushInterval = 1.0,  -- seconds between file writes
        _lastFlush = -math.huge,  -- ensure first write always flushes
        _path = DEFAULT_LOG_PATH,
        _minLevel = "Debug",
        _alsoConsole = true,  -- mirror each line to tm.os.Log for console parity
    }, Logger)
end

-- Change where the log file is written. Most mods leave this at the
-- default `logs.txt`; mainly useful for tests or if you want to split
-- log streams.
function Logger:SetPath(path)
    _expectType("Logger", "SetPath", "path", "string", path)
    self._path = path
    return self
end

-- Set the minimum severity that actually gets logged. Anything below
-- this level is silently dropped. Valid values: "Debug", "Info",
-- "Warn", "Error". Useful for cutting down chatter in finished mods.
function Logger:SetMinLevel(level)
    _expectType("Logger", "SetMinLevel", "level", "string", level)
    if not _LOG_LEVELS[level] then
        error(_runtimeError("Logger", "SetMinLevel",
            'unknown level "' .. level .. '". Expected Debug, Info, Warn, or Error.'), 0)
    end
    self._minLevel = level
    return self
end

-- Set the maximum number of lines to keep in the in-memory ring buffer.
-- Older lines are dropped when the buffer fills up. Default is 200.
-- If you are running a long session and logging heavily, raise this to
-- retain more history. Calling this method clears the existing buffer.
function Logger:SetBufferSize(n)
    _expectType("Logger", "SetBufferSize", "n", "number", n)
    if n < 1 or n ~= math.floor(n) then
        error(_runtimeError("Logger", "SetBufferSize",
            'buffer size must be a positive integer, got ' .. tostring(n)), 0)
    end
    self._bufferSize = n
    self._lines = {}
    self._count = 0
    self._pos = 1
    return self
end

-- Set the interval (in seconds) between file writes to `logs.txt`.
-- The logger writes only when (1) the throttle interval has passed,
-- or (2) an Error-level line is logged (which flushes immediately),
-- or (3) you call Flush() explicitly. Default is 1.0 second.
function Logger:SetFlushInterval(interval)
    _expectType("Logger", "SetFlushInterval", "interval", "number", interval)
    if interval < 0 then
        error(_runtimeError("Logger", "SetFlushInterval",
            'flush interval must be non-negative, got ' .. tostring(interval)), 0)
    end
    self._flushInterval = interval
    return self
end

-- Internal: get the current time from the game. Returns a valid time if
-- available, or nil if there is no clock. Used for flush throttling.
local function _getTime()
    if tm and tm.os and tm.os.GetTime then
        return tm.os.GetTime()
    end
    return nil
end

-- Internal: format a message with optional `string.format` args. We
-- catch formatting errors here (e.g. `%d` paired with a string) and tack
-- a `[format error: ...]` suffix onto the raw message instead of letting
-- the error bubble out of the logger and crash your mod.
local function _format(message, ...)
    if select("#", ...) == 0 then
        return message
    end
    local ok, formatted = pcall(string.format, message, ...)
    if ok then
        return formatted
    end
    return message .. " [format error: " .. tostring(formatted) .. "]"
end

-- Internal: build a single log line. Looks like
-- `[12.345] [INFO] hello, world`. The timestamp comes from Trailmakers
-- (seconds since the game started, three decimal places). If we are
-- running outside the game, the timestamp shows as `?`.
local function _renderLine(level, body)
    local t = _getTime()
    if t then
        t = string.format("%.3f", t)
    else
        t = "?"
    end
    return "[" .. t .. "] [" .. level .. "] " .. body
end

-- Internal: write the current ring buffer to disk. If the buffer is
-- empty, write a single space (since WriteAllText_Dynamic rejects empty
-- strings). Wrapped in pcall so a disk hiccup never crashes the mod.
function Logger:_doFlush()
    if not (tm and tm.os and tm.os.WriteAllText_Dynamic) then
        return
    end
    local content
    if self._count == 0 then
        content = " "
    else
        -- Build the output in order. If the buffer is not yet full, just
        -- concatenate positions 1 to _count. If it is full, concatenate
        -- from _pos (oldest) to _bufferSize, then 1 to _pos-1 (newest).
        local lines = {}
        if self._count < self._bufferSize then
            for i = 1, self._count do
                table.insert(lines, self._lines[i])
            end
        else
            for i = self._pos, self._bufferSize do
                table.insert(lines, self._lines[i])
            end
            for i = 1, self._pos - 1 do
                table.insert(lines, self._lines[i])
            end
        end
        content = table.concat(lines, "\n")
    end
    pcall(tm.os.WriteAllText_Dynamic, self._path, content)
    local now = _getTime()
    if now then
        self._lastFlush = now
    end
end

-- Force a write of the current buffer to disk right now, regardless of
-- the throttle interval.
function Logger:Flush()
    self:_doFlush()
    return self
end

-- Internal: write one message at the named level. The four public
-- methods (`Debug`, `Info`, `Warn`, `Error`) just call this with their
-- own level. Lines are appended to a ring buffer; the file is written
-- on a throttled schedule (unless the level is Error, which flushes
-- immediately).
function Logger:_emit(level, message, ...)
    if _LOG_LEVELS[level] < _LOG_LEVELS[self._minLevel] then
        return
    end
    local line = _renderLine(level, _format(message, ...))

    -- Add line to ring buffer at current position, then advance.
    self._lines[self._pos] = line
    if self._count < self._bufferSize then
        self._count = self._count + 1
    end
    self._pos = self._pos + 1
    if self._pos > self._bufferSize then
        self._pos = 1
    end

    -- Also send the line to the in-game log overlay so you can see it
    -- while playing without alt-tabbing to read the file.
    if self._alsoConsole and tm and tm.os and tm.os.Log then
        pcall(tm.os.Log, line)
    end

    -- Error-level lines flush immediately. If there is no game clock,
    -- flush every line (safer than never). Otherwise, throttle to the
    -- flush interval.
    if level == "Error" then
        self:_doFlush()
    else
        local now = _getTime()
        if not now then
            self:_doFlush()  -- no clock, flush immediately
        elseif now - self._lastFlush >= self._flushInterval then
            self:_doFlush()
        end
    end
end

-- Write a Debug-level message. Lowest priority. Use for chatty traces
-- that you would normally want filtered out in a release. Extras after
-- the message behave like `string.format` substitutions.
function Logger:Debug(message, ...) self:_emit("Debug", message, ...) end
-- Write an Info-level message. For normal "things are happening"
-- updates -- mod started, player joined, etc.
function Logger:Info(message, ...)  self:_emit("Info",  message, ...) end
-- Write a Warn-level message. For surprising-but-recoverable things --
-- a config value missing, a player tried to do something invalid, etc.
function Logger:Warn(message, ...)  self:_emit("Warn",  message, ...) end
-- Write an Error-level message. For real problems the mod cannot
-- recover from on its own.
function Logger:Error(message, ...) self:_emit("Error", message, ...) end

-- Throw away every line stored in memory so future log writes start
-- fresh. NOTE: this does not delete the file on disk yet. If you want
-- the file empty right now, follow `Clear()` with `Logger:Flush()`.
function Logger:Clear()
    self._count = 0
    self._pos = 1
    return self
end

-- Tell the engine how to build the Logger service. The Logger is not
-- created until you first call `engine:GetService("Logger")`. The
-- instance is also stashed in `LFTME._logger` so the engine's own
-- error paths can reach it without a circular service lookup.
LFTME._registerService("Logger", function(_engine)
    local logger = _newLogger()
    LFTME._logger = logger
    return logger
end)

--------------------------------------------------------------------------------
-- 5. Scheduler, the task library, and UpdateService
--
-- These three pieces are presented together because they really are one
-- thing: a list of "stuff to do later" plus the once-per-frame callback
-- Trailmakers calls (`update(dt)`) that walks the list. Splitting them
-- apart would just make you bounce between sections to follow one piece
-- of code.
--
-- The list lives on the UpdateService. Each entry is one of three kinds:
--
--   * "resume"  -- payload is a paused task; resume it at `deadline`.
--   * "after"   -- payload is a function; call it once at `deadline`.
--   * "every"   -- payload is a function; call it at `deadline`, then
--                  bump `deadline` by `interval` and keep the entry
--                  for the next loop.
--
-- All deadlines are in "engine time" -- the seconds the engine has been
-- running, which is the sum of every `dt` Trailmakers has handed us.
-- That means if the game pauses or you alt-tab out, scheduling pauses
-- too. (This is also why the public update event is called `OnUpdate`
-- rather than `Heartbeat`: precision is whatever the game gives us.)
--
-- TaskHandle is the cancel-token returned by everything in this section.
-- It is deliberately a different thing from a Connection: Connections
-- represent a signal subscription, TaskHandles represent a piece of
-- scheduled work. Having two distinct types lets TaskManager (next
-- section) call the right cleanup method automatically.
--------------------------------------------------------------------------------

-- TaskHandle ---------------------------------------------------------------

local TaskHandle = {}
TaskHandle.__index = TaskHandle

-- Internal: build a new TaskHandle. You never call this yourself -- you
-- get a TaskHandle back from `task.spawn`, `task.delay`,
-- `UpdateService:After`, or `UpdateService:Every`.
local function _newTaskHandle()
    return setmetatable({
        _className = "TaskHandle",
        Cancelled = false,
    }, TaskHandle)
end

-- Cancel this scheduled work so it does not run (or, for repeating
-- "every" tasks, so it stops repeating). Safe to call more than once.
--
-- Cancel is "lazy" -- it just marks the handle, and the next time the
-- engine walks the scheduled list it skips anything marked cancelled.
-- This is faster than removing the entry immediately, especially since
-- most TaskHandles are never cancelled at all.
function TaskHandle:Cancel()
    if self.Cancelled then
        return
    end
    self.Cancelled = true
end

-- UpdateService ------------------------------------------------------------

local UpdateService = {}
UpdateService.__index = UpdateService

-- Internal: send an error message to the Logger if one exists, otherwise
-- to the in-game log overlay, otherwise to `print`. The scheduler wraps
-- every user callback in a safety net so a thrown error in one task
-- does not stop the engine's update loop from running the others.
local function _logSchedulerError(message)
    local logger = LFTME._logger
    if logger then
        logger:Error(message)
    elseif tm and tm.os and tm.os.Log then
        tm.os.Log("[LFTME] " .. message)
    else
        print("[LFTME] " .. message)
    end
end

-- Internal: build the UpdateService and install the global `update(dt)`
-- hook that Trailmakers will call every frame. Used by the service
-- factory below.
local function _newUpdateService()
    local self = setmetatable({
        _className = "UpdateService",
        _clock = 0,                -- accumulated tick time, seconds
        _queue = {},               -- array of pending scheduler entries
        _previousUpdate = nil,     -- captured `_G.update` from before boot
        OnUpdate = _newSignal("UpdateService.OnUpdate"),
    }, UpdateService)

    -- If the mod already defined its own `update(dt)` BEFORE calling
    -- `LFTME.New()`, save it so we can still call it -- we wrap the
    -- engine's version around theirs. GOTCHA: if you define `update`
    -- AFTER `LFTME.New()`, your function will overwrite the engine's
    -- and scheduling will silently break. Always do `LFTME.New()` after
    -- defining your own `update`, or just let the engine own `update`
    -- completely and use `UpdateService.OnUpdate:Connect(fn)` instead.
    self._previousUpdate = rawget(_G, "update")
    rawset(_G, "update", function(dt)
        -- Call the mod's pre-existing `update` first if there was one,
        -- wrapped in a safety net so a thrown error there does not stop
        -- the engine's update loop.
        if self._previousUpdate then
            local ok, err = pcall(self._previousUpdate, dt)
            if not ok then
                _logSchedulerError("previous _G.update threw: " .. tostring(err))
            end
        end
        self:_pump(dt or 0)
    end)

    return self
end

-- Internal: add one entry to the scheduled-work list. Used by
-- `task.spawn`, `task.wait`, `UpdateService:After`, and
-- `UpdateService:Every`.
function UpdateService:_enqueue(entry)
    table.insert(self._queue, entry)
end

-- Internal: do one tick of the update loop. Called by the `update(dt)`
-- wrapper installed above.
--
-- What happens in order:
--   1. Add `dt` to the engine's internal clock.
--   2. Walk the scheduled-work list. For each entry, drop it if
--      cancelled, leave it for later if its deadline has not arrived
--      yet, otherwise run it. "every" entries get their deadline pushed
--      forward by `interval` and stay in the list.
--   3. Fire `UpdateService.OnUpdate` so anyone listening for "next
--      frame" gets called.
--
-- We record the list length at the start of the walk. Anything ADDED
-- to the list during this tick (for example, a callback that calls
-- `task.wait`) will NOT run on the same tick that scheduled it. This
-- keeps the rule simple -- "scheduled now, fires at least one tick from
-- now" -- and stops infinite loops where a zero-second wait would
-- otherwise re-fire immediately.
function UpdateService:_pump(dt)
    self._clock = self._clock + dt
    local now = self._clock

    local pending = self._queue
    local count = #pending
    local keep = {}

    for i = 1, count do
        local entry = pending[i]
        if entry.handle and entry.handle.Cancelled then
            -- silently drop cancelled entry
        elseif entry.deadline > now then
            keep[#keep + 1] = entry
        else
            if entry.type == "resume" then
                local co = entry.payload
                -- If the task already finished (someone resumed it
                -- elsewhere since we last touched it), Lua reports it
                -- as dead. We treat that as a normal end-of-life rather
                -- than an error -- finished tasks are fine to silently
                -- skip.
                if coroutine.status(co) ~= "dead" then
                    local ok, err = coroutine.resume(co)
                    if not ok then
                        _logSchedulerError("task.spawn coroutine error: " .. tostring(err))
                    end
                end
                -- If the task called `task.wait` while it was running,
                -- it has already added itself back to the list with a
                -- new deadline before pausing -- nothing more to do here.
            elseif entry.type == "after" then
                local ok, err = pcall(entry.payload)
                if not ok then
                    _logSchedulerError("UpdateService:After callback error: " .. tostring(err))
                end
            elseif entry.type == "every" then
                local ok, err = pcall(entry.payload)
                if not ok then
                    _logSchedulerError("UpdateService:Every callback error: " .. tostring(err))
                end
                -- Move the deadline forward from the planned time, not
                -- from "now", so the rhythm stays steady even if one
                -- frame ran late.
                entry.deadline = entry.deadline + entry.interval
                keep[#keep + 1] = entry
            end
        end
    end

    -- Carry over anything that was added during this tick (those live
    -- past the original end of the list right now).
    local total = #self._queue
    for i = count + 1, total do
        keep[#keep + 1] = self._queue[i]
    end

    self._queue = keep

    -- Fire OnUpdate listeners last, so their handlers see a stable list
    -- of scheduled work.
    self.OnUpdate:Fire(dt)
end

-- Run `fn` once, at least `seconds` from now (counting only time while
-- the engine is updating -- pausing the game pauses the timer). Useful
-- for "give the player 3 seconds of grace before the round starts" or
-- "show this hint for a moment then move on". Returns a TaskHandle;
-- call `:Cancel()` on it to stop the function from running.
function UpdateService:After(seconds, fn)
    _expectType("UpdateService", "After", "seconds", "number", seconds)
    _expectType("UpdateService", "After", "fn", "function", fn)
    local handle = _newTaskHandle()
    self:_enqueue({
        type = "after",
        deadline = self._clock + seconds,
        payload = fn,
        handle = handle,
    })
    return handle
end

-- Run `fn` over and over, every `seconds`. Great for periodic checks
-- (e.g. "every 5 seconds, save score to disk"). Returns a TaskHandle;
-- call `:Cancel()` on it to stop the repeats.
function UpdateService:Every(seconds, fn)
    _expectType("UpdateService", "Every", "seconds", "number", seconds)
    _expectType("UpdateService", "Every", "fn", "function", fn)
    if seconds <= 0 then
        error(_runtimeError("UpdateService", "Every",
            "interval must be positive, got " .. tostring(seconds)), 0)
    end
    local handle = _newTaskHandle()
    self:_enqueue({
        type = "every",
        deadline = self._clock + seconds,
        interval = seconds,
        payload = fn,
        handle = handle,
    })
    return handle
end

-- Tell the engine how to build UpdateService. The factory also stores
-- the new instance in a file-local so the `task` library below can find
-- it without making a service lookup on every call.
LFTME._registerService("UpdateService", function(_engine)
    local svc = _newUpdateService()
    _updateServiceInstance = svc
    return svc
end)

-- task library -------------------------------------------------------------
--
-- A small "task" library shaped like Roblox's, with three functions:
-- `task.spawn`, `task.wait`, and `task.delay`. All three are built on
-- top of UpdateService. You will use these constantly in mod code.

local task = {}

-- Start `fn(...)` in a new "task" -- a Lua function the engine can
-- pause and resume. The task starts running right away, and inside it
-- you can call `task.wait(seconds)` to pause for a while.
--
-- Useful for: any code that needs to wait, like cutscenes, countdowns,
-- "spawn a wave of enemies every 30 seconds for 5 minutes", or just
-- "do this thing after the game has had a frame to settle".
--
-- Returns a TaskHandle. Calling `:Cancel()` on it does NOT instantly
-- kill the running function -- Lua has no clean way to do that. Instead,
-- the engine will refuse to resume the task next time it would pause.
-- So if your task is in a tight loop with no `task.wait`, it will run
-- to completion regardless. Sprinkle `task.wait(0)` into long loops if
-- you want them to be cancellable.
function task.spawn(fn, ...)
    _expectType("task", "spawn", "fn", "function", fn)
    if _updateServiceInstance == nil then
        error(_runtimeError("task", "spawn",
            "engine has not been constructed. Call LFTME.New() first."), 0)
    end
    local handle = _newTaskHandle()
    local args = { ... }
    local n = select("#", ...)
    local co = coroutine.create(function()
        fn(table.unpack(args, 1, n))
    end)
    _managedCoroutines[co] = handle
    local ok, err = coroutine.resume(co)
    if not ok then
        _logSchedulerError("task.spawn coroutine error: " .. tostring(err))
    end
    return handle
end

-- Pause the current task for at least `seconds`. `seconds` defaults to
-- 0, which means "pause until the next frame". Resumes automatically.
--
-- Useful for: spacing out work across frames, building delays into a
-- sequence, or yielding back to the engine to keep the game responsive.
--
-- GOTCHA: this only works inside a `task.spawn(function() ... end)`.
-- Calling it from a normal top-level function (or a `:Connect` handler
-- that is not itself inside a task) is an error, because there is
-- nothing to resume.
function task.wait(seconds)
    seconds = seconds or 0
    _expectType("task", "wait", "seconds", "number", seconds)
    local co, isMain = coroutine.running()
    if not co or isMain or _managedCoroutines[co] == nil then
        error(_runtimeError("task", "wait",
            "cannot yield from an unmanaged coroutine. Use task.spawn(function() ... end)."), 0)
    end
    if _updateServiceInstance == nil then
        error(_runtimeError("task", "wait",
            "engine has not been constructed. Call LFTME.New() first."), 0)
    end
    local handle = _managedCoroutines[co]
    _updateServiceInstance:_enqueue({
        type = "resume",
        deadline = _updateServiceInstance._clock + seconds,
        payload = co,
        handle = handle,
    })
    return coroutine.yield()
end

-- Same as `UpdateService:After(seconds, fn)`. Run `fn` once, `seconds`
-- from now. We expose it as `task.delay` too because that is the name
-- Roblox uses, and copy-pasted snippets from there expect it to work.
function task.delay(seconds, fn)
    if _updateServiceInstance == nil then
        error(_runtimeError("task", "delay",
            "engine has not been constructed. Call LFTME.New() first."), 0)
    end
    return _updateServiceInstance:After(seconds, fn)
end

--------------------------------------------------------------------------------
-- 6. TaskManager
--
-- A handy "clean these up when I am done" bucket. You add things that
-- need to be released later -- event connections, scheduled tasks,
-- spawned objects, plain functions -- and when you call
-- `taskManager:Cleanup()` (or `:Destroy()`) every one of them is released
-- with the right method. (Roblox calls this a "Maid"; we use the
-- clearer name TaskManager.)
--
-- What you can add, and what cleanup does:
--
--   * Connection       -> calls `:Disconnect()`
--   * TaskHandle       -> calls `:Cancel()`
--   * any { :Destroy } -> calls `:Destroy()`  (SpawnedObject, etc.)
--   * function         -> just runs the function (no arguments)
--
-- You cannot add a raw Lua coroutine directly. Lua has no portable way
-- to cancel a paused coroutine, and silently dropping one would leak
-- memory. If you want cancellable background work, use `task.spawn`
-- (which returns a TaskHandle) and add THAT.
--
-- `Add` returns a token. Hold on to it if you want to target ONE
-- specific item later -- `Remove(token)` forgets it without releasing,
-- and `CleanupTask(token)` releases just that one item.
--
-- The Players service uses this so every Player has their own
-- TaskManager. Anything you add to `player.TaskManager` is cleaned up
-- for you when the player leaves -- great for per-player event
-- connections you might otherwise forget to disconnect.
--------------------------------------------------------------------------------

local TaskManager = {}
TaskManager.__index = TaskManager

-- Internal: refuse to do anything if this TaskManager has already been
-- destroyed, with an error message that points at the calling line in
-- your code.
local function _ensureNotDestroyed(self, methodName)
    if self._isDestroyed then
        error(_runtimeError("TaskManager", methodName,
            "this TaskManager has been destroyed."), 0)
    end
end

-- Internal: release one task using the right cleanup method for its
-- type. Returns (ok, err) -- the caller logs the error and keeps going,
-- because one bad release should never stop the rest of `Cleanup`.
local function _releaseTask(task)
    local t = type(task)
    if t == "function" then
        return pcall(task)
    end
    if t == "table" then
        local cls = rawget(task, "_className")
        if cls == "Connection" and type(task.Disconnect) == "function" then
            return pcall(task.Disconnect, task)
        end
        if cls == "TaskHandle" and type(task.Cancel) == "function" then
            return pcall(task.Cancel, task)
        end
        if type(task.Destroy) == "function" then
            return pcall(task.Destroy, task)
        end
    end
    -- Unknown shape: just succeed silently. `Add` already checked the
    -- shape when the item was registered, so getting here means
    -- something mutated under our feet -- not worth crashing cleanup
    -- over.
    return true, nil
end

-- Make a new, empty TaskManager. Start adding things to it with `:Add`.
function TaskManager.new()
    return setmetatable({
        _className = "TaskManager",
        _tasks = {},          -- ordered array of { token = ..., task = ... }
        _isDestroyed = false,
    }, TaskManager)
end

-- Add a task. Returns a token you can use later to target this one
-- specific item. We check the shape right now (Connection / TaskHandle /
-- something with `:Destroy` / function) so you find out about a bad add
-- immediately, rather than at cleanup time. Raw coroutines are rejected
-- with a clear message pointing you at `task.spawn` instead.
function TaskManager:Add(task)
    _ensureNotDestroyed(self, "Add")
    local t = type(task)
    if t == "thread" then
        error(_runtimeError("TaskManager", "Add",
            "raw coroutines are not accepted. Use task.spawn(...) to get a cancellable TaskHandle."), 0)
    end
    if t ~= "function" and t ~= "table" then
        _typeError("TaskManager", "Add", "task",
            "Connection, TaskHandle, object with :Destroy, or function", task)
    end
    -- Use an empty table as the token -- every empty table is unique,
    -- so two tokens can never accidentally compare equal. An integer
    -- counter would work but you could get a "stale" token problem if
    -- the manager were ever reset.
    local token = {}
    table.insert(self._tasks, { token = token, task = task })
    return token
end

-- Forget about a task WITHOUT releasing it. From this point you are
-- responsible for cleaning it up yourself. Does nothing if the token
-- is unknown (which keeps `Remove`-then-`Remove` safe instead of
-- throwing).
function TaskManager:Remove(token)
    _ensureNotDestroyed(self, "Remove")
    for i = 1, #self._tasks do
        if self._tasks[i].token == token then
            table.remove(self._tasks, i)
            return
        end
    end
end

-- Release one specific task right now and forget it. Other tasks stay
-- in the TaskManager. If the release throws an error, the engine logs
-- it (via Logger if you have one set up) and continues -- the task is
-- still considered cleaned up.
function TaskManager:CleanupTask(token)
    _ensureNotDestroyed(self, "CleanupTask")
    for i = 1, #self._tasks do
        if self._tasks[i].token == token then
            local entry = table.remove(self._tasks, i)
            local ok, err = _releaseTask(entry.task)
            if not ok then
                local logger = LFTME._logger
                if logger then
                    logger:Error("TaskManager:CleanupTask release error: " .. tostring(err))
                end
            end
            return
        end
    end
end

-- Release every task in REVERSE order from how they were added.
-- Reverse order matches the usual pattern where the most recently added
-- thing depends on something earlier; tearing the inner one down first
-- could leave the outer one firing against half-cleaned-up state.
--
-- We swap the list out before walking it so a task that calls `Add`
-- during its own release will not loop forever or grow the list under
-- us. Any new additions land in the fresh empty list.
function TaskManager:Cleanup()
    _ensureNotDestroyed(self, "Cleanup")
    local tasks = self._tasks
    self._tasks = {}
    for i = #tasks, 1, -1 do
        local ok, err = _releaseTask(tasks[i].task)
        if not ok then
            local logger = LFTME._logger
            if logger then
                logger:Error("TaskManager:Cleanup release error: " .. tostring(err))
            end
        end
    end
end

-- Run one final `Cleanup` and then mark this TaskManager dead. Any
-- further call to it (including another `Destroy`) throws -- a destroyed
-- manager that silently swallowed new tasks would just hide bugs and
-- leak resources.
function TaskManager:Destroy()
    if self._isDestroyed then
        error(_runtimeError("TaskManager", "Destroy", "already destroyed."), 0)
    end
    self:Cleanup()
    self._isDestroyed = true
end

--------------------------------------------------------------------------------
-- 7. Players service
--
-- The live list of human players in the session, plus a `Player` object
-- that represents each one.
--
-- What this service does for you:
--   * Bridges Trailmakers' join/leave events to friendlier engine
--     signals: `PlayerJoinedServer` and `PlayerLeftServer`. Just call
--     `engine:GetService("Players").PlayerJoinedServer:Connect(fn)`.
--   * Pre-populates the player list at startup, so if a player was
--     already in the game when the mod loaded, you can still see them.
--   * Gives every Player their own TaskManager (`player.TaskManager`).
--     Anything you add to it (event connections, scheduled tasks, etc.)
--     is automatically cleaned up when the player leaves.
--
-- What a `Player` object gives you:
--   * `Name`, `Id`, `TaskManager` (read these, do not write to them).
--   * Action methods like `:Teleport`, `:Kick`, `:Kill`, `:Eject`,
--     `:SetTeam`, `:SetInvincible`, `:SetJetpackEnabled`. These return
--     the player so you can chain calls: `player:Kill():Eject()`.
--   * Question methods like `:GetPosition`, `:IsInSeat` which return
--     the answer instead of `self`.
--
-- Exactly what happens when a player leaves:
--   1. Trailmakers tells the engine the player is leaving.
--   2. The engine fires `PlayerLeftServer` -- all your handlers run.
--      The player and their TaskManager are still fully usable here, so
--      a handler can register one last cleanup task if it needs to.
--   3. The engine then calls `Destroy()` on the player's TaskManager,
--      which releases every task (including the ones a handler just
--      added) in reverse order.
--   4. The player is removed from the lookup tables -- after this,
--      `FindById` and `FindByName` will not find them.
--------------------------------------------------------------------------------

-- Player class -------------------------------------------------------------

local Player = {}
Player.__index = Player

-- Internal: convert a Trailmakers vector (lowercase `x/y/z`) into an
-- engine Vector3 (uppercase `X/Y/Z`). Tolerates missing fields by
-- defaulting them to 0.
local function _hostVec3ToVector3(v)
    return Vector3.new(v.x or 0, v.y or 0, v.z or 0)
end

-- Internal: build the kind of vector Trailmakers expects (lowercase
-- `x/y/z`) from three numbers. We try the official `tm.vector3.Create`
-- first; if that is not available we just build a plain table with
-- `.x/.y/.z` fields, which works for any Trailmakers function that just
-- reads the components.
local function _makeHostVec3(x, y, z)
    if tm and tm.vector3 and tm.vector3.Create then
        local ok, v = pcall(tm.vector3.Create, x, y, z)
        if ok and v then
            return v
        end
    end
    return { x = x, y = y, z = z }
end

-- Internal: build a new Player object from Trailmakers' raw player
-- handle. Only the Players service calls this.
local function _newPlayer(modPlayer)
    return setmetatable({
        _className = "Player",
        _modPlayer = modPlayer,
        Id = modPlayer.playerId,
        Name = modPlayer.playerName,
        TaskManager = TaskManager.new(),
    }, Player)
end

-- Move the player instantly to a new spot. You can pass either a
-- Vector3 or three numbers. Useful for spawn points, race checkpoints,
-- arena resets, or just yanking a stuck player back to a known place.
-- Returns self so you can chain other calls
-- (wraps `tm.players.GetPlayerTransform(...).SetPositionWorld`).
function Player:Teleport(xOrVec, y, z)
    local vx, vy, vz
    if _isInstanceOf(xOrVec, "Vector3") then
        vx, vy, vz = xOrVec.X, xOrVec.Y, xOrVec.Z
    elseif type(xOrVec) == "number" and type(y) == "number" and type(z) == "number" then
        vx, vy, vz = xOrVec, y, z
    else
        _typeError("Player", "Teleport", "position",
            "Vector3 or (x, y, z) numbers", xOrVec)
    end
    if tm and tm.players and tm.players.GetPlayerTransform then
        local ok, transform = pcall(tm.players.GetPlayerTransform, self.Id)
        if ok and transform and transform.SetPositionWorld then
            pcall(transform.SetPositionWorld, transform, _makeHostVec3(vx, vy, vz))
        end
    end
    return self
end

-- Boot the player off the server. The optional `reason` string is
-- written to the engine's log for your records. GOTCHA: Trailmakers'
-- own `tm.players.Kick` does NOT accept a reason and does NOT show one
-- to the kicked player, so treat `reason` as audit-only. Returns self
-- for chaining (wraps `tm.players.Kick`).
function Player:Kick(reason)
    if reason ~= nil then
        _expectType("Player", "Kick", "reason", "string", reason)
        local logger = LFTME._logger
        if logger then
            logger:Info("Kicking player '" .. tostring(self.Name) ..
                "' (id " .. tostring(self.Id) .. "): " .. reason)
        end
    end
    if tm and tm.players and tm.players.Kick then
        pcall(tm.players.Kick, self.Id)
    end
    return self
end

-- Kill the player. Trailmakers handles whatever respawn rules the map
-- has set. Useful for arena game modes, "out of bounds" punishments,
-- or testing your death-handling code. Returns self for chaining
-- (wraps `tm.players.KillPlayer`).
function Player:Kill()
    if tm and tm.players and tm.players.KillPlayer then
        pcall(tm.players.KillPlayer, self.Id)
    end
    return self
end

-- Force the player out of whatever seat they are sitting in. Does
-- nothing if they are not in a seat. Useful for "kick people off
-- vehicles between rounds" style logic. Returns self for chaining
-- (wraps `tm.players.ForceExitSeat`).
function Player:Eject()
    if tm and tm.players and tm.players.ForceExitSeat then
        pcall(tm.players.ForceExitSeat, self.Id)
    end
    return self
end

-- Assign the player to a team number. What "team" means is up to
-- Trailmakers / the map -- the engine just passes the number along
-- without validating it. Returns self for chaining
-- (wraps `tm.players.SetPlayerTeam`).
function Player:SetTeam(teamId)
    _expectType("Player", "SetTeam", "teamId", "number", teamId)
    if tm and tm.players and tm.players.SetPlayerTeam then
        pcall(tm.players.SetPlayerTeam, self.Id, teamId)
    end
    return self
end

-- Make the player invincible (or take it away). While invincible they
-- cannot take damage; `Kill()` and `CanKill()` are also affected.
-- Useful for spectator modes, judges in a race, or temporarily
-- protecting players during cutscenes. Returns self for chaining
-- (wraps `tm.players.SetPlayerIsInvincible`).
function Player:SetInvincible(enabled)
    _expectType("Player", "SetInvincible", "enabled", "boolean", enabled)
    if tm and tm.players and tm.players.SetPlayerIsInvincible then
        pcall(tm.players.SetPlayerIsInvincible, self.Id, enabled)
    end
    return self
end

-- Turn the player's jetpack on or off. If you disable mid-flight, they
-- do not fall instantly -- they just lose thrust the next time they
-- press the jetpack button. Useful for ground-only game modes or
-- punishing speeders. Returns self for chaining
-- (wraps `tm.players.SetJetpackEnabled`).
function Player:SetJetpackEnabled(enabled)
    _expectType("Player", "SetJetpackEnabled", "enabled", "boolean", enabled)
    if tm and tm.players and tm.players.SetJetpackEnabled then
        pcall(tm.players.SetJetpackEnabled, self.Id, enabled)
    end
    return self
end

-- Get the player's current position as a Vector3. Useful for distance
-- checks, follow-style cameras, or spawning effects near a player.
-- Returns `Vector3.new(0, 0, 0)` if Trailmakers cannot answer right
-- now (for instance, between death and respawn the player has no
-- transform). If you need to tell "really at the origin" apart from
-- "no answer", pair this with `IsInSeat()` or a respawn-aware event.
-- (Wraps `tm.players.GetPlayerTransform(...).GetPositionWorld`.)
function Player:GetPosition()
    if tm and tm.players and tm.players.GetPlayerTransform then
        local ok, transform = pcall(tm.players.GetPlayerTransform, self.Id)
        if ok and transform and transform.GetPositionWorld then
            local pok, pos = pcall(transform.GetPositionWorld, transform)
            if pok and pos then
                return _hostVec3ToVector3(pos)
            end
        end
    end
    return Vector3.new(0, 0, 0)
end

-- True if the player is currently sitting in a seat, false otherwise.
-- A handy "is the player driving?" check. Returns false rather than
-- throwing if Trailmakers cannot answer -- "not currently driving" is
-- the safer default. (Wraps `tm.players.IsPlayerInSeat`.)
function Player:IsInSeat()
    if tm and tm.players and tm.players.IsPlayerInSeat then
        local ok, seated = pcall(tm.players.IsPlayerInSeat, self.Id)
        if ok then
            return seated and true or false
        end
    end
    return false
end

-- Spawn a prefab right next to this player, with an optional Vector3
-- `offset` from their position. Returns the spawned object so you can
-- chain calls like `:Scale(2):Rotation(...)` -- not `self`, because
-- you almost always want to keep working with the new object next.
-- Useful for "give the player a crate at their feet" style features.
-- (This first version is a stub that errors; the real one is added
-- further down once ObjectSpawner is in scope.)
function Player:SpawnObjectNearby(prefab, offset)
    error(_runtimeError("Player", "SpawnObjectNearby",
        "ObjectSpawner is not yet implemented in this engine build. " ..
        "Spawn directly via engine:GetService(\"ObjectSpawner\") once it ships."), 0)
end

-- Players service ----------------------------------------------------------

local Players = {}
Players.__index = Players

-- Internal: turn a name into a comparable form for fuzzy lookup. We
-- lowercase it and strip spaces, underscores, and hyphens, so
-- "Player 123", "player_123", and "PLAYER-123" all match. Used by
-- `FindByName`.
local function _normalizeName(name)
    return (name:lower():gsub("[%s_%-]", ""))
end

-- Internal: build the Players service. Subscribes to Trailmakers'
-- join/leave events and pre-fills from anyone already in the session.
-- All Trailmakers calls are wrapped in safety nets so the service can
-- still boot if some of those functions are missing (for example
-- under a unit-test harness).
local function _newPlayers()
    local self = setmetatable({
        _className = "Players",
        _byId = {},                    -- [playerId] = Player
        PlayerJoinedServer = _newSignal("Players.PlayerJoinedServer"),
        PlayerLeftServer = _newSignal("Players.PlayerLeftServer"),
    }, Players)

    -- Internal: turn a Trailmakers player handle into an engine Player
    -- (or return the existing one if we already wrapped this id).
    -- Returns nil if the input is missing a player id.
    function self:_track(modPlayer)
        if not modPlayer or modPlayer.playerId == nil then
            return nil
        end
        local existing = self._byId[modPlayer.playerId]
        if existing then
            return existing
        end
        local p = _newPlayer(modPlayer)
        self._byId[modPlayer.playerId] = p
        return p
    end

    -- Add everyone already in the session right now. Wrapped in a safety
    -- net because `CurrentPlayers` does not exist on every Trailmakers
    -- build (older versions, test harnesses, etc.).
    if tm and tm.players and tm.players.CurrentPlayers then
        local ok, list = pcall(tm.players.CurrentPlayers)
        if ok and type(list) == "table" then
            for _, modPlayer in ipairs(list) do
                self:_track(modPlayer)
            end
        end
    end

    -- Hook Trailmakers' own join/leave events and forward them to the
    -- engine's signals. The bridge functions are kept on `self` in case
    -- a future cleanup needs to unregister them; in practice the
    -- Players service lives as long as the engine does.
    if tm and tm.players then
        if tm.players.OnPlayerJoined and tm.players.OnPlayerJoined.add then
            self._onJoinedBridge = function(modPlayer)
                local p = self:_track(modPlayer)
                if p then
                    self.PlayerJoinedServer:Fire(p)
                end
            end
            pcall(tm.players.OnPlayerJoined.add, self._onJoinedBridge)
        end
        if tm.players.OnPlayerLeft and tm.players.OnPlayerLeft.add then
            self._onLeftBridge = function(modPlayer)
                if not modPlayer or modPlayer.playerId == nil then
                    return
                end
                local p = self._byId[modPlayer.playerId]
                if not p then
                    return
                end
                -- Fire the signal first so your handlers can still
                -- read or use the player's TaskManager one last time.
                self.PlayerLeftServer:Fire(p)
                -- Then destroy the player's TaskManager. That releases
                -- everything in it, including any last-minute tasks
                -- the handlers above just added.
                if p.TaskManager and not p.TaskManager._isDestroyed then
                    pcall(p.TaskManager.Destroy, p.TaskManager)
                end
                self._byId[modPlayer.playerId] = nil
            end
            pcall(tm.players.OnPlayerLeft.add, self._onLeftBridge)
        end
    end

    return self
end

-- Get every currently-connected player as an array. Useful for "for
-- each player do X" loops. The order is not guaranteed -- sort the
-- result yourself if order matters (e.g. by Name or by Id).
function Players:GetPlayers()
    local arr = {}
    for _, p in pairs(self._byId) do
        arr[#arr + 1] = p
    end
    return arr
end

-- Find a player by their numeric id (the same `player.Id` you get from
-- a join event). Returns the Player, or `nil` plus an error message
-- if no such player exists right now.
function Players:FindById(id)
    _expectType("Players", "FindById", "id", "number", id)
    local p = self._byId[id]
    if p then
        return p
    end
    return nil, _runtimeError("Players", "FindById",
        "no player with id " .. tostring(id) .. ".")
end

-- Find a player by their display name. Tries an exact case-sensitive
-- match first. If that fails, falls back to a fuzzy match
-- (case-insensitive, ignoring spaces, underscores, and hyphens). If
-- the fuzzy match is unique you get that player; if more than one
-- player matches you get `nil` plus an error listing them all, so you
-- can ask the user to be more specific.
function Players:FindByName(name)
    _expectType("Players", "FindByName", "name", "string", name)
    for _, p in pairs(self._byId) do
        if p.Name == name then
            return p
        end
    end
    local target = _normalizeName(name)
    local matches = {}
    for _, p in pairs(self._byId) do
        if _normalizeName(p.Name) == target then
            matches[#matches + 1] = p
        end
    end
    if #matches == 1 then
        return matches[1]
    end
    if #matches == 0 then
        return nil, _runtimeError("Players", "FindByName",
            'no player matched "' .. name .. '".')
    end
    local names = {}
    for i, p in ipairs(matches) do
        names[i] = '"' .. p.Name .. '"'
    end
    return nil, _runtimeError("Players", "FindByName",
        'name "' .. name .. '" is ambiguous. Matches: ' ..
        table.concat(names, ", ") .. ".")
end

-- Returns a function suitable for use in a generic `for` loop:
--   `for player in Players:Iterate() do ... end`
-- It takes a snapshot of the player list right now, so a player joining
-- or leaving in the middle of the loop will not cause you to skip
-- someone or visit them twice.
function Players:Iterate()
    local snapshot = {}
    for _, p in pairs(self._byId) do
        snapshot[#snapshot + 1] = p
    end
    local i = 0
    return function()
        i = i + 1
        return snapshot[i]
    end
end

-- Tell the engine how to build the Players service. It is built lazily,
-- but `LFTME.New()` immediately requests it so the join/leave event
-- bridges are hooked up before any of your code runs.
LFTME._registerService("Players", function(_engine)
    return _newPlayers()
end)

--------------------------------------------------------------------------------
-- 8. Chat service
--
-- The Chat service covers TWO different on-screen surfaces in
-- Trailmakers, with one method each:
--
--   * Chat:SendMessageTo(player, message)
--       A normal chat line in the chat panel. By default it appears
--       to come from "Server" -- change that with
--       `Chat:SetSenderName("...")`.
--
--   * Chat:BroadcastToAll(header, body, duration?)
--       A big middle-of-screen popup that EVERY player sees. There is
--       also a builder form:
--       `Chat:BroadcastToAll():Header("..."):Body("..."):Duration(5)`.
--
-- INCOMING chat fires `Chat.MessageReceived(player, message)`. Notice
-- the signal is on the service, not on the player -- the player is
-- the subject of the event, not its owner. If the chat line came from
-- something that is NOT a tracked player (a system message, an NPC,
-- or a player who left in the same frame), `player` will be `nil` -- so
-- always check that first in your handler.
--
-- ECHO SUPPRESSION: when the engine sends a chat line via
-- `SendChatMessage`, Trailmakers immediately bounces that same line
-- back to us as an inbound message. Without filtering, your
-- `MessageReceived` handlers would fire for every outbound message
-- and you would get infinite loops. The engine keeps a tiny short-term
-- map of recently-sent messages and silently drops any inbound match.
--
-- BUILDER COMMIT TIMING: the chain-form builder does NOT send the
-- popup the moment you call `:Header(...)`. It waits until the next
-- frame, so every setter on the same line gets a chance to run first.
-- That way `:Header(...):Body(...):Duration(...)` fires the popup
-- ONCE with the final values, not three times as you build it up.
--------------------------------------------------------------------------------

local ECHO_SUPPRESSION_TTL = 0.25
local DEFAULT_INTRUSIVE_DURATION = 5
local DEFAULT_SENDER_NAME = "Server"

-- IntrusiveBuilder ---------------------------------------------------------
--
-- A small helper object you get back from `Chat:BroadcastToAll()` with
-- no arguments. Lets you build a popup piece-by-piece, then automatically
-- shows it on the next frame.

local IntrusiveBuilder = {}
IntrusiveBuilder.__index = IntrusiveBuilder

-- Internal: build a new IntrusiveBuilder with empty header/body and the
-- default duration. The first setter you call arms the "show on next
-- frame" timer.
local function _newIntrusiveBuilder()
    return setmetatable({
        _className = "IntrusiveBuilder",
        _header = "",
        _body = "",
        _duration = DEFAULT_INTRUSIVE_DURATION,
        _armed = false,        -- have we scheduled the deferred fire yet?
        _fired = false,        -- has the deferred fire run?
    }, IntrusiveBuilder)
end

-- Internal: the first time a setter is called, schedule the actual
-- popup display for the next frame. If you call more setters after,
-- they just update the stored values -- the timer was already armed.
-- Showing the popup from a one-frame-later callback lets the whole
-- chain finish first, so the popup uses the final values.
local function _armIntrusive(self)
    if self._armed then
        return
    end
    self._armed = true
    if _updateServiceInstance then
        _updateServiceInstance:After(0, function()
            self:_fire()
        end)
    else
        -- No scheduler yet (extremely early call); fire immediately.
        self:_fire()
    end
end

-- Set the bold top line of the popup. Calling this also schedules the
-- popup to appear on the next frame, so later setters in the same
-- chain get applied first. Returns self for chaining.
function IntrusiveBuilder:Header(text)
    _expectType("IntrusiveBuilder", "Header", "text", "string", text)
    self._header = text
    _armIntrusive(self)
    return self
end

-- Set the main body text of the popup. You can pass a plain string, or
-- a MarkupText for HTML-style formatting (`MarkupText.new("hi"):Bold()`).
-- Returns self for chaining.
function IntrusiveBuilder:Body(text)
    _expectType("IntrusiveBuilder", "Body", "text", "string", text)
    self._body = text
    _armIntrusive(self)
    return self
end

-- How long the popup stays on screen, in seconds. Default is 5 seconds.
-- Returns self for chaining.
function IntrusiveBuilder:Duration(seconds)
    _expectType("IntrusiveBuilder", "Duration", "seconds", "number", seconds)
    self._duration = seconds
    _armIntrusive(self)
    return self
end

-- Internal: actually show the popup, with whatever header/body/duration
-- have been set. Only runs once per builder -- calling setters again
-- after the popup is shown will update the stored values but the
-- on-screen popup will not change (Trailmakers does not let us edit a
-- popup that is already up).
function IntrusiveBuilder:_fire()
    if self._fired then
        return
    end
    self._fired = true
    if tm and tm.playerUI and tm.playerUI.ShowIntrusiveMessageForAllPlayers then
        pcall(tm.playerUI.ShowIntrusiveMessageForAllPlayers,
            tostring(self._header),
            tostring(self._body),
            self._duration)
    end
end

-- Chat service -------------------------------------------------------------

local Chat = {}
Chat.__index = Chat

-- Internal: build the Chat service, hook Trailmakers' incoming-chat
-- event, and set up the echo-suppression map so the engine's own
-- outbound messages do not bounce back as inbound events.
local function _newChat(playersService)
    local self = setmetatable({
        _className = "Chat",
        _senderName = DEFAULT_SENDER_NAME,
        _echoMap = {},                 -- [senderName..NUL..message] = expiry clock
        _playersService = playersService,
        MessageReceived = _newSignal("Chat.MessageReceived"),
    }, Chat)

    -- Forward Trailmakers' built-in chat event to the engine's
    -- `MessageReceived` signal.
    if tm and tm.playerUI and tm.playerUI.OnChatMessage and tm.playerUI.OnChatMessage.add then
        self._onChatBridge = function(senderName, message, _color)
            -- Check echo suppression first -- if Trailmakers is just
            -- bouncing back a message we sent ourselves, drop it
            -- silently. This prevents infinite "send -> receive -> send"
            -- loops.
            local now = (_updateServiceInstance and _updateServiceInstance._clock) or 0
            local key = tostring(senderName) .. "\0" .. tostring(message)
            local expiry = self._echoMap[key]
            if expiry and expiry > now then
                self._echoMap[key] = nil
                return
            end
            -- Try to look the sender up as a Player. `FindByName`
            -- returns `(nil, err)` if it cannot match a name; we just
            -- pass `nil` along as the player, since system messages
            -- and NPC chat are normal and should not throw.
            local player = nil
            if self._playersService then
                local found = self._playersService:FindByName(senderName)
                if found then
                    player = found
                end
            end
            self.MessageReceived:Fire(player, message)
        end
        pcall(tm.playerUI.OnChatMessage.add, self._onChatBridge)
    end

    return self
end

-- Change the name that appears next to engine-sent chat lines. Default
-- is "Server". Useful for branding (e.g. set it to your mod's name)
-- or for impersonating an NPC. Returns self for chaining.
function Chat:SetSenderName(name)
    _expectType("Chat", "SetSenderName", "name", "string", name)
    self._senderName = name
    return self
end

-- Send a chat line that every player will see in their chat panel.
-- It will be shown as if it came from the sender name you configured
-- (default "Server"; change with `Chat:SetSenderName`). The `player`
-- argument is currently mostly ceremonial -- Trailmakers' chat API only
-- supports broadcasting, so the message goes to everyone regardless.
-- We accept it now so a future per-player chat API can drop in cleanly.
-- The engine notes the (sender, message) pair for a moment so the
-- inbound chat handler can drop Trailmakers' own self-echo. Returns
-- self for chaining (wraps `tm.playerUI.SendChatMessage`).
function Chat:SendMessageTo(player, message)
    _expectInstance("Chat", "SendMessageTo", "player", "Player", player)
    _expectType("Chat", "SendMessageTo", "message", "string", message)
    local senderName = self._senderName
    local now = (_updateServiceInstance and _updateServiceInstance._clock) or 0
    local key = senderName .. "\0" .. message
    self._echoMap[key] = now + ECHO_SUPPRESSION_TTL
    if tm and tm.playerUI and tm.playerUI.SendChatMessage then
        pcall(tm.playerUI.SendChatMessage, senderName, message)
    end
    return self
end

-- Show a big middle-of-screen popup to every player. Two ways to call:
--
--   * Positional: `Chat:BroadcastToAll("Warning", "Restart in 10s", 10)`
--     Shows the popup right now. Duration is optional (defaults to 5
--     seconds).
--
--   * Builder:    `Chat:BroadcastToAll():Header(...):Body(...):Duration(...)`
--     Returns an IntrusiveBuilder. Each setter stores its value, and
--     the popup is shown ONCE on the next frame with whatever the final
--     header/body/duration ended up being.
--
-- Useful for round-start announcements, server-wide alerts, victory
-- screens. (Wraps `tm.playerUI.ShowIntrusiveMessageForAllPlayers`.)
function Chat:BroadcastToAll(header, body, duration)
    -- Zero-arg form returns a builder so you can fill it in by chaining.
    if header == nil and body == nil and duration == nil then
        return _newIntrusiveBuilder()
    end
    _expectType("Chat", "BroadcastToAll", "header", "string", header)
    _expectType("Chat", "BroadcastToAll", "body", "string", body)
    if duration ~= nil then
        _expectType("Chat", "BroadcastToAll", "duration", "number", duration)
    end
    if tm and tm.playerUI and tm.playerUI.ShowIntrusiveMessageForAllPlayers then
        pcall(tm.playerUI.ShowIntrusiveMessageForAllPlayers,
            header, body, duration or DEFAULT_INTRUSIVE_DURATION)
    end
    return self
end

LFTME._registerService("Chat", function(engine)
    -- The Chat service needs Players so the inbound chat bridge can
    -- look senders up by name. We grab the Players service once here
    -- and pass it into the constructor rather than re-fetching it on
    -- every chat event. By the time you call `engine:GetService("Chat")`,
    -- `LFTME.New()` has already made sure Players exists.
    local playersService = engine:GetService("Players")
    return _newChat(playersService)
end)

--------------------------------------------------------------------------------
-- 9. ObjectSpawner service
--
-- Spawns props into the world and lets you push them around. The basic
-- surface, which is what most mods use:
--
--   * SpawnObject(prefab) -> SpawnedObject       -- spawn at the origin
--   * SpawnedObject:Position(x,y,z | Vector3)    -- move it
--   * SpawnedObject:Scale(x,y,z | Vector3 | n)   -- resize it
--   * SpawnedObject:Rotation(x,y,z | Vector3)    -- rotate it (Euler, degrees)
--   * SpawnedObject:Destroy()                    -- despawn it
--   * ResolvePrefab(name) -> canonical, err      -- name lookup
--
-- The position/scale/rotation setters all return the SpawnedObject so
-- you can chain them: `spawner:SpawnObject("PFB_X"):Position(0,10,0):Scale(2)`.
--
-- COMING LATER (not in this version of the engine):
--   * SpawnGroup + the patterns library (Grid, Circle, Ring, Cube, ...)
--   * Friendly prefab name lookup (aliases, fuzzy matching, "did you
--     mean ...?" errors when you mistype). For now, use exact names --
--     get the full list with `ObjectSpawner:GetCatalog()`.
--   * An engine-wide spawn registry so you can destroy everything you
--     spawned in one call.
--
-- Behind the scenes the engine uses `tm.physics.SpawnObject(pos, name)`
-- to spawn and then reaches into the object's transform to set
-- position, rotation, and scale. Every Trailmakers call is wrapped in
-- a safety net because the game can fail harmlessly (object despawned
-- between two chained calls, name not in the catalog, etc.) and a
-- crash there is almost never what you want.
--------------------------------------------------------------------------------

-- SpawnedObject ------------------------------------------------------------

local SpawnedObject = {}
SpawnedObject.__index = SpawnedObject

-- Internal: build a new SpawnedObject. You get these from
-- `ObjectSpawner:SpawnObject` or `ObjectSpawner:SpawnAt`; do not
-- construct one yourself.
local function _newSpawnedObject(modGameObject, prefab)
    return setmetatable({
        _className = "SpawnedObject",
        _modGameObject = modGameObject,
        _prefab = prefab,
        _isDestroyed = false,
    }, SpawnedObject)
end

-- Internal: turn the various ways of passing 3 numbers into actual
-- x, y, z values. Accepts:
--   * a Vector3
--   * three numbers (x, y, z)
--   * a single number, but ONLY when `allowUniform` is true
-- Scale allows the single-number form (so `:Scale(2)` means "2x in
-- all axes"). Position and Rotation refuse it, because `Position(5)`
-- almost always means "I forgot the other two arguments" and we would
-- rather catch that mistake than silently put the object at (5, 5, 5).
local function _xyzArgs(className, methodName, paramName, allowUniform, a, b, c)
    if _isInstanceOf(a, "Vector3") then
        return a.X, a.Y, a.Z
    end
    if type(a) == "number" then
        if b == nil and c == nil then
            if allowUniform then
                return a, a, a
            end
        elseif type(b) == "number" and type(c) == "number" then
            return a, b, c
        end
    end
    _typeError(className, methodName, paramName,
        allowUniform and "Vector3, (x, y, z), or uniform number" or "Vector3 or (x, y, z)",
        a)
end

-- Internal: refuse to do anything on a destroyed object. Throws an
-- error that points at the line in your code that tried it.
local function _ensureLive(self, method)
    if self._isDestroyed then
        error(_runtimeError("SpawnedObject", method,
            "this object has been destroyed."), 0)
    end
end

-- Internal helper: every method that needs to read or change an
-- object's position, scale, or rotation goes through here. It fetches
-- the underlying Trailmakers transform and runs `fn` against it, all
-- wrapped in safety nets so a transient Trailmakers hiccup (object
-- mid-despawn, etc.) never crashes the mod.
local function _withTransform(self, fn)
    if not self._modGameObject or not self._modGameObject.GetTransform then
        return
    end
    local ok, transform = pcall(self._modGameObject.GetTransform, self._modGameObject)
    if ok and transform then
        pcall(fn, transform)
    end
end

-- Move the spawned object to a new world position. Accepts a Vector3
-- or three numbers. Returns self for chaining
-- (wraps the underlying transform's `SetPositionWorld`).
function SpawnedObject:Position(a, b, c)
    _ensureLive(self, "Position")
    local x, y, z = _xyzArgs("SpawnedObject", "Position", "position", false, a, b, c)
    _withTransform(self, function(t)
        if t.SetPositionWorld then
            t:SetPositionWorld(_makeHostVec3(x, y, z))
        end
    end)
    return self
end

-- Resize the spawned object. You can pass:
--   * a single number (`:Scale(2)` makes it twice as big in every axis)
--   * three numbers (`:Scale(2, 1, 1)` stretches it on X only)
--   * a Vector3
-- Returns self for chaining
-- (wraps the underlying transform's `SetScale`).
function SpawnedObject:Scale(a, b, c)
    _ensureLive(self, "Scale")
    local x, y, z = _xyzArgs("SpawnedObject", "Scale", "scale", true, a, b, c)
    _withTransform(self, function(t)
        if t.SetScale then
            t:SetScale(_makeHostVec3(x, y, z))
        end
    end)
    return self
end

-- Rotate the spawned object. Values are Euler angles in DEGREES
-- (not radians) -- so `:Rotation(0, 90, 0)` is a quarter turn around
-- the Y axis. Accepts a Vector3 or three numbers. Returns self for
-- chaining (wraps the underlying transform's `SetEulerAnglesWorld`).
function SpawnedObject:Rotation(a, b, c)
    _ensureLive(self, "Rotation")
    local x, y, z = _xyzArgs("SpawnedObject", "Rotation", "rotation", false, a, b, c)
    _withTransform(self, function(t)
        if t.SetEulerAnglesWorld then
            t:SetEulerAnglesWorld(_makeHostVec3(x, y, z))
        end
    end)
    return self
end

-- Remove the object from the world. Safe to call more than once -- a
-- second `Destroy` does nothing rather than throwing. This matters
-- because cleanup code can legitimately end up destroying the same
-- object twice (for example, a TaskManager holds both the object AND
-- a callback that also destroys it).
function SpawnedObject:Destroy()
    if self._isDestroyed then
        return
    end
    self._isDestroyed = true
    if self._modGameObject and self._modGameObject.Despawn then
        pcall(self._modGameObject.Despawn, self._modGameObject)
    end
end

-- ObjectSpawner service ----------------------------------------------------

local ObjectSpawner = {}
ObjectSpawner.__index = ObjectSpawner

-- Internal: build a new ObjectSpawner. The `_aliases` table is reserved
-- for a future name-lookup feature; it is unused right now.
local function _newObjectSpawner()
    return setmetatable({
        _className = "ObjectSpawner",
        _aliases = {},     -- reserved for the future alias registry
    }, ObjectSpawner)
end

-- For now, `ResolvePrefab` just accepts a prefab name string and hands
-- it back unchanged. A later engine version will add nicer features
-- here: aliases (so short nicknames map to the long official names),
-- fuzzy matching (so "metalcraet" still finds "PFB_Metal_Crate"), and
-- helpful "did you mean ...?" errors when you mistype. For now, use
-- exact prefab names -- you can list them all with
-- `ObjectSpawner:GetCatalog()`.
function ObjectSpawner:ResolvePrefab(name)
    if type(name) == "string" then
        return name
    end
    return nil, _runtimeError("ObjectSpawner", "ResolvePrefab",
        "could not resolve prefab " .. _describeValue(name) .. ". " ..
        "Pass the canonical host name as a string (e.g. \"PFB_Metal_Crate\").")
end

-- Spawn a single prefab at the world origin and return a SpawnedObject
-- you can keep chaining methods on. Most of the time you will follow
-- this up with `:Position(x, y, z)` to put it where you want.
-- Example:
--   local box = spawner:SpawnObject("PFB_Metal_Crate"):Position(0, 5, 0)
-- (Wraps `tm.physics.SpawnObject`.)
function ObjectSpawner:SpawnObject(prefab)
    local resolved, err = self:ResolvePrefab(prefab)
    if not resolved then
        error(err, 0)
    end
    if not (tm and tm.physics and tm.physics.SpawnObject) then
        error(_runtimeError("ObjectSpawner", "SpawnObject",
            "host API tm.physics.SpawnObject is not available."), 0)
    end
    local ok, modGameObject = pcall(tm.physics.SpawnObject,
        _makeHostVec3(0, 0, 0), resolved)
    if not ok or not modGameObject then
        error(_runtimeError("ObjectSpawner", "SpawnObject",
            "host failed to spawn \"" .. resolved .. "\": " .. tostring(modGameObject)), 0)
    end
    return _newSpawnedObject(modGameObject, resolved)
end

-- `SpawnGroup` will eventually let you spawn many objects in patterns
-- (grids, circles, etc.) with one call. It is not in this version of
-- the engine. Right now this method throws a clear error pointing you
-- at `SpawnObject` -- call that in a loop until the real version ships.
function ObjectSpawner:SpawnGroup(_prefab)
    error(_runtimeError("ObjectSpawner", "SpawnGroup",
        "SpawnGroup and the patterns library are not yet implemented in this engine build. " ..
        "Spawn objects individually via SpawnObject for now."), 0)
end

-- Tell the engine how to build ObjectSpawner. It is built the first
-- time you call `engine:GetService("ObjectSpawner")` -- there are no
-- background events it needs to subscribe to, so building it on-demand
-- is fine.
LFTME._registerService("ObjectSpawner", function(_engine)
    return _newObjectSpawner()
end)

-- BEGIN_LFTME_EXTENSIONS
--------------------------------------------------------------------------------
-- Extension services and helpers
--
-- Everything below this banner is the second wave of engine features:
--   * Four more services: ModStorage (save/load), World (gravity,
--     weather, time of day), UI (HUD labels & popups), and Audio.
--   * Extra methods on Player for moderation (build/repair toggles,
--     profile ids) and replacing the earlier `SpawnObjectNearby` stub
--     with a working version.
--   * Extra methods on ObjectSpawner for browsing the prefab catalog,
--     registering custom meshes and textures, spawning at a position,
--     and clearing every spawn.
--   * A `GetPosition` method on SpawnedObject.
--
-- Same style rules as the rest of the engine: every Trailmakers call is
-- wrapped in a safety net, every argument is type-checked, errors use
-- the same prefix format pointing back at your code.
--------------------------------------------------------------------------------

-- A small JSON encoder/decoder used by ModStorage so your mod can save
-- and load tables as files. You usually do not call `_json.*` directly;
-- use `ModStorage:ReadJSON` / `ModStorage:WriteJSON` instead.
local _json = {}

-- Internal: turn a Lua string into a JSON-quoted string. Escapes the
-- special characters JSON requires (`"`, `\`, tabs, newlines, etc.).
local function _jsonEncodeString(s)
    local out = { string.char(34) }
    for i = 1, #s do
        local c = s:byte(i)
        if c == 34 then out[#out+1] = "\\\""
        elseif c == 92 then out[#out+1] = "\\\\"
        elseif c == 8 then out[#out+1] = "\b"
        elseif c == 9 then out[#out+1] = "\t"
        elseif c == 10 then out[#out+1] = "\n"
        elseif c == 12 then out[#out+1] = "\f"
        elseif c == 13 then out[#out+1] = "\r"
        elseif c < 32 then out[#out+1] = string.format("\\u%04x", c)
        else out[#out+1] = string.char(c) end
    end
    out[#out+1] = string.char(34)
    return table.concat(out)
end

-- Internal: turn a Lua value of any supported type into a JSON string.
-- The `seen` table is used to spot cycles (a table that contains
-- itself) so we throw a friendly error instead of looping forever.
-- A table with keys 1..n is treated as a JSON array; everything else
-- is a JSON object, and non-string keys are skipped.
local function _jsonEncodeValue(v, seen)
    local t = type(v)
    if v == nil then return "null"
    elseif t == "boolean" then return v and "true" or "false"
    elseif t == "number" then
        if v ~= v or v == math.huge or v == -math.huge then return "null" end
        if v == math.floor(v) and math.abs(v) < 1e15 then
            return string.format("%d", v)
        end
        return string.format("%.17g", v)
    elseif t == "string" then return _jsonEncodeString(v)
    elseif t == "table" then
        if seen[v] then
            error(_runtimeError("ModStorage", "Encode",
                "cycle detected during JSON encode."), 0)
        end
        seen[v] = true
        local n = #v
        local isArray = n > 0
        if isArray then
            for k, _ in pairs(v) do
                if type(k) ~= "number" or k ~= math.floor(k) or k < 1 or k > n then
                    isArray = false
                    break
                end
            end
        else
            local hasAny = false
            for _, _ in pairs(v) do hasAny = true; break end
            if not hasAny then seen[v] = nil; return "{}" end
        end
        if isArray then
            local parts = {}
            for i = 1, n do parts[i] = _jsonEncodeValue(v[i], seen) end
            seen[v] = nil
            return "[" .. table.concat(parts, ",") .. "]"
        else
            local parts = {}
            for k, val in pairs(v) do
                if type(k) == "string" then
                    parts[#parts+1] = _jsonEncodeString(k) .. ":" .. _jsonEncodeValue(val, seen)
                end
            end
            seen[v] = nil
            return "{" .. table.concat(parts, ",") .. "}"
        end
    end
    error(_runtimeError("ModStorage", "Encode",
        "cannot encode value of type " .. t .. "."), 0)
end

-- Internal: top-level entry point for encoding. Just starts the
-- recursion with an empty "seen" set so cycle detection works.
function _json.encode(value)
    return _jsonEncodeValue(value, {})
end

-- Internal: parse a JSON string into a Lua value. Returns the value on
-- success, or `(nil, errorMessage)` if the input was malformed. Never
-- throws -- callers can rely on the second return value.
function _json.decode(text)
    if type(text) ~= "string" then
        return nil, "JSON input is not a string"
    end
    local pos = 1
    local len = #text
    local function skipWs()
        while pos <= len do
            local c = text:byte(pos)
            if c == 32 or c == 9 or c == 10 or c == 13 then pos = pos + 1
            else break end
        end
    end
    local parseValue
    local function err(msg)
        return nil, msg .. " at position " .. pos
    end
    local function parseString()
        if text:byte(pos) ~= 34 then return err("expected quote") end
        pos = pos + 1
        local out = {}
        while pos <= len do
            local c = text:byte(pos)
            if c == 34 then pos = pos + 1; return table.concat(out) end
            if c == 92 then
                pos = pos + 1
                local esc = text:byte(pos)
                if esc == 34 then out[#out+1] = "\""
                elseif esc == 92 then out[#out+1] = "\\"
                elseif esc == 47 then out[#out+1] = "/"
                elseif esc == 98 then out[#out+1] = "\b"
                elseif esc == 102 then out[#out+1] = "\f"
                elseif esc == 110 then out[#out+1] = "\n"
                elseif esc == 114 then out[#out+1] = "\r"
                elseif esc == 116 then out[#out+1] = "\t"
                elseif esc == 117 then
                    local hex = text:sub(pos+1, pos+4)
                    local n = tonumber(hex, 16)
                    if not n then return err("bad unicode escape") end
                    if n < 0x80 then
                        out[#out+1] = string.char(n)
                    elseif n < 0x800 then
                        out[#out+1] = string.char(0xC0 + math.floor(n/0x40),
                                                  0x80 + (n % 0x40))
                    else
                        out[#out+1] = string.char(0xE0 + math.floor(n/0x1000),
                                                  0x80 + (math.floor(n/0x40) % 0x40),
                                                  0x80 + (n % 0x40))
                    end
                    pos = pos + 4
                else return err("bad escape") end
                pos = pos + 1
            else
                out[#out+1] = string.char(c)
                pos = pos + 1
            end
        end
        return err("unterminated string")
    end
    local function parseNumber()
        local start = pos
        if text:byte(pos) == 45 then pos = pos + 1 end
        while pos <= len do
            local c = text:byte(pos)
            if (c >= 48 and c <= 57) or c == 46 or c == 43 or c == 45
                or c == 69 or c == 101 then
                pos = pos + 1
            else break end
        end
        local n = tonumber(text:sub(start, pos - 1))
        if not n then return err("bad number") end
        return n
    end
    local function parseArray()
        pos = pos + 1
        local out = {}
        skipWs()
        if text:byte(pos) == 93 then pos = pos + 1; return out end
        while true do
            skipWs()
            local v, e = parseValue()
            if e then return nil, e end
            out[#out+1] = v
            skipWs()
            local c = text:byte(pos)
            if c == 93 then pos = pos + 1; return out end
            if c ~= 44 then return err("expected comma or ]") end
            pos = pos + 1
        end
    end
    local function parseObject()
        pos = pos + 1
        local out = {}
        skipWs()
        if text:byte(pos) == 125 then pos = pos + 1; return out end
        while true do
            skipWs()
            local k, e = parseString()
            if e then return nil, e end
            skipWs()
            if text:byte(pos) ~= 58 then return err("expected colon") end
            pos = pos + 1
            skipWs()
            local v, ve = parseValue()
            if ve then return nil, ve end
            out[k] = v
            skipWs()
            local c = text:byte(pos)
            if c == 125 then pos = pos + 1; return out end
            if c ~= 44 then return err("expected comma or }") end
            pos = pos + 1
        end
    end
    parseValue = function()
        skipWs()
        local c = text:byte(pos)
        if c == 34 then return parseString() end
        if c == 123 then return parseObject() end
        if c == 91 then return parseArray() end
        if c == 116 and text:sub(pos, pos+3) == "true" then pos = pos + 4; return true end
        if c == 102 and text:sub(pos, pos+4) == "false" then pos = pos + 5; return false end
        if c == 110 and text:sub(pos, pos+3) == "null" then pos = pos + 4; return nil end
        if c == 45 or (c and c >= 48 and c <= 57) then return parseNumber() end
        return err("unexpected character")
    end
    local v, e = parseValue()
    if e then return nil, e end
    return v
end

--------------------------------------------------------------------------------
-- ModStorage service
--
-- The "save and load files" service. Reads and writes files in your
-- mod's dynamic storage folder (`data_dynamic_willNotBeUploadedToWorkshop/`)
-- and, for the static folder (`data_static/`), reads only.
--
-- Useful for saving player progress, settings, leaderboards, or any
-- data that should persist between play sessions. Comes with JSON
-- helpers so you can save a whole Lua table in one line.
--
-- Missing files return `nil` rather than throwing, so you can ask
-- "does this exist?" without wrapping it in a pcall.
--------------------------------------------------------------------------------

local ModStorage = {}
ModStorage.__index = ModStorage

-- Internal: build a new ModStorage. The service holds no state -- it
-- is just a thin wrapper over Trailmakers' file read/write functions.
local function _newModStorage()
    return setmetatable({ _className = "ModStorage" }, ModStorage)
end

-- Read a file from the mod's dynamic storage folder and return its
-- contents as a string. Returns `nil` if the file does not exist (or
-- if the read fails) -- this does NOT throw, so you can safely call
-- it without checking first. If you need to tell "empty file" apart
-- from "missing file", use `Exists(path)`.
-- (Wraps `tm.os.ReadAllText_Dynamic`.)
function ModStorage:Read(path)
    _expectType("ModStorage", "Read", "path", "string", path)
    if not (tm and tm.os and tm.os.ReadAllText_Dynamic) then return nil end
    local ok, contents = pcall(tm.os.ReadAllText_Dynamic, path)
    if not ok or type(contents) ~= "string" then return nil end
    return contents
end

-- Write `contents` to a file in the mod's dynamic storage folder.
-- Creates the file if it does not exist; replaces it entirely if it
-- does. Trailmakers has no "append" function, so this is always a
-- full rewrite. Any underlying error is swallowed -- call `Exists`
-- afterwards if you need to confirm the write happened. Returns self
-- for chaining (wraps `tm.os.WriteAllText_Dynamic`).
function ModStorage:Write(path, contents)
    _expectType("ModStorage", "Write", "path", "string", path)
    _expectType("ModStorage", "Write", "contents", "string", contents)
    if tm and tm.os and tm.os.WriteAllText_Dynamic then
        pcall(tm.os.WriteAllText_Dynamic, path, contents)
    end
    return self
end

-- Read a file and decode its contents as JSON. Returns the decoded Lua
-- value, or `(nil, errorMessage)` if the file is missing, empty, or
-- malformed. Never throws. Ideal for loading saved settings or save
-- data into a Lua table.
function ModStorage:ReadJSON(path)
    local text = self:Read(path)
    if text == nil then return nil, "file not found" end
    if text == "" then return nil, "empty file" end
    return _json.decode(text)
end

-- Encode `value` as JSON and write it to a file. Throws if the value
-- cannot be encoded (a table that contains itself, or values like
-- functions that JSON cannot represent). Returns self for chaining.
-- Pair with `ReadJSON` to round-trip Lua tables to disk.
function ModStorage:WriteJSON(path, value)
    _expectType("ModStorage", "WriteJSON", "path", "string", path)
    self:Write(path, _json.encode(value))
    return self
end

-- Returns true if the file exists in dynamic storage. NOTE: Trailmakers
-- gives us no cheap "does this exist?" function, so this actually reads
-- the file to find out. Fine for occasional checks; avoid in tight
-- loops.
function ModStorage:Exists(path)
    return self:Read(path) ~= nil
end

-- Add `line` plus a newline to the end of a file, creating the file
-- if it does not exist. Useful for things like a custom event log.
-- NOTE: Trailmakers has no real "append" call, so this reads the
-- file, sticks `line` on the end, and writes the whole thing back.
-- Fine for the occasional entry; avoid for fast-paced writes.
-- Returns self for chaining.
function ModStorage:AppendLine(path, line)
    _expectType("ModStorage", "AppendLine", "path", "string", path)
    _expectType("ModStorage", "AppendLine", "line", "string", line)
    local existing = self:Read(path) or ""
    if #existing > 0 and existing:sub(-1) ~= "\n" then existing = existing .. "\n" end
    self:Write(path, existing .. line .. "\n")
    return self
end

ModStorage.JSON = {
    Encode = function(v) return _json.encode(v) end,
    Decode = function(s) return _json.decode(s) end,
}

LFTME._registerService("ModStorage", function(_engine)
    return _newModStorage()
end)

--------------------------------------------------------------------------------
-- World service
--
-- Knobs and dials for the world itself: time of day, gravity, physics
-- time scale, wind, map name, build complexity limits.
--
-- All "Get..." methods return safe defaults (0, 1, "") instead of
-- throwing if Trailmakers cannot answer right now. All "Set..."
-- methods return self for chaining.
--
-- Useful for weather effects, slow-motion replays, low-gravity arenas,
-- or just reading the current map name to gate map-specific logic.
--------------------------------------------------------------------------------

local World = {}
World.__index = World

-- Internal: build a new World service. It holds no state -- every
-- method just calls straight through to Trailmakers.
local function _newWorld()
    return setmetatable({ _className = "World" }, World)
end

-- Get the current time of day as a number from 0 to 100. Trailmakers'
-- convention: 0 is dawn, ~25 is noon, ~50 is dusk, ~75 is midnight.
-- Returns 0 if Trailmakers cannot answer. Useful for "only spawn
-- monsters at night" style logic. (Wraps `tm.world.GetTimeOfDay`.)
function World:GetTimeOfDay()
    if tm and tm.world and tm.world.GetTimeOfDay then
        local ok, v = pcall(tm.world.GetTimeOfDay)
        if ok and type(v) == "number" then return v end
    end
    return 0
end

-- Jump the time-of-day clock to `t`, where 0..100 covers a full day
-- (see `GetTimeOfDay` for what specific values mean). Throws if `t`
-- is out of range -- a typo like `SetTimeOfDay(1200)` would otherwise
-- leave the world stuck at midnight without telling you why. Useful
-- for staging screenshots, weather mods, or instantly switching from
-- day to night. Returns self for chaining
-- (wraps `tm.world.SetTimeOfDay`).
function World:SetTimeOfDay(t)
    _expectType("World", "SetTimeOfDay", "t", "number", t)
    if t < 0 or t > 100 then
        error(_runtimeError("World", "SetTimeOfDay",
            "value " .. tostring(t) .. " is out of range [0, 100]."), 0)
    end
    if tm and tm.world and tm.world.SetTimeOfDay then
        pcall(tm.world.SetTimeOfDay, t)
    end
    return self
end

-- Pass `true` to stop time of day from advancing, `false` to let it
-- resume. Useful for screenshot mods, in-game cinematics, or any
-- "hold the lighting still" situation. Returns self for chaining
-- (wraps `tm.world.SetPausedTimeOfDay`).
function World:SetTimeOfDayPaused(paused)
    _expectType("World", "SetTimeOfDayPaused", "paused", "boolean", paused)
    if tm and tm.world and tm.world.SetPausedTimeOfDay then
        pcall(tm.world.SetPausedTimeOfDay, paused)
    end
    return self
end

-- Get the current gravity multiplier. 1 is normal Earth gravity, 0
-- means everything floats, negative flips gravity upward. Returns 1
-- if Trailmakers cannot answer. (Wraps `tm.physics.GetGravityMultiplier`.)
function World:GetGravity()
    if tm and tm.physics and tm.physics.GetGravityMultiplier then
        local ok, v = pcall(tm.physics.GetGravityMultiplier)
        if ok and type(v) == "number" then return v end
    end
    return 1
end

-- Change how strong gravity feels for the whole world. The number is
-- a multiplier of normal Earth gravity: 1 is normal, 0.5 is moon-ish,
-- 0 makes everything float, 2 doubles gravity. Negative values flip
-- gravity so things fall upward -- Trailmakers accepts it without
-- complaint, so use deliberately. Useful for floaty arenas, space
-- mods, and just plain chaos. Returns self for chaining
-- (wraps `tm.physics.SetGravityMultiplier`).
function World:SetGravity(multiplier)
    _expectType("World", "SetGravity", "multiplier", "number", multiplier)
    if tm and tm.physics and tm.physics.SetGravityMultiplier then
        pcall(tm.physics.SetGravityMultiplier, multiplier)
    end
    return self
end

-- Get the current physics time scale. 1 is real-time, 0.5 is
-- slow-motion, 2 is fast-forward. Returns 1 if Trailmakers cannot
-- answer. (Wraps `tm.physics.GetTimeScale`.)
function World:GetTimeScale()
    if tm and tm.physics and tm.physics.GetTimeScale then
        local ok, v = pcall(tm.physics.GetTimeScale)
        if ok and type(v) == "number" then return v end
    end
    return 1
end

-- Speed up or slow down physics for everyone. 1 is real-time, 0.5 is
-- half-speed (great for slow-mo replays), 2 is double speed. Useful
-- for cinematic kill cams and "bullet time" effects. Returns self for
-- chaining (wraps `tm.physics.SetTimeScale`).
function World:SetTimeScale(scale)
    _expectType("World", "SetTimeScale", "scale", "number", scale)
    if tm and tm.physics and tm.physics.SetTimeScale then
        pcall(tm.physics.SetTimeScale, scale)
    end
    return self
end

-- Set the world's wind. Accepts a Vector3 or three numbers. The
-- length of the vector is the wind speed; the direction it points is
-- the direction the wind blows. Useful for weather effects, sailing
-- mods, or just nudging players around with strong gusts. Returns
-- self for chaining (wraps `tm.world.SetGlobalWind`).
function World:SetGlobalWind(a, b, c)
    local x, y, z
    if _isInstanceOf(a, "Vector3") then
        x, y, z = a.X, a.Y, a.Z
    elseif type(a) == "number" and type(b) == "number" and type(c) == "number" then
        x, y, z = a, b, c
    else
        _typeError("World", "SetGlobalWind", "wind",
            "Vector3 or (x, y, z) numbers", a)
    end
    if tm and tm.world and tm.world.SetGlobalWind then
        pcall(tm.world.SetGlobalWind, _makeHostVec3(x, y, z))
    end
    return self
end

-- Get the name of the currently loaded map as a string. Returns an
-- empty string if Trailmakers cannot answer. Handy for gating
-- map-specific code: `if World:GetMapName() == "Race Island" then ...`.
-- (Wraps `tm.physics.GetMapName`.)
function World:GetMapName()
    if tm and tm.physics and tm.physics.GetMapName then
        local ok, v = pcall(tm.physics.GetMapName)
        if ok and type(v) == "string" then return v end
    end
    return ""
end

-- Cap how many blocks each player can place in their builds.
-- Trailmakers may silently clamp very large numbers to its own
-- internal maximum. Useful for performance-sensitive servers or
-- limited-build challenges. Returns self for chaining
-- (wraps `tm.physics.SetBuildComplexity`).
function World:SetBuildComplexity(n)
    _expectType("World", "SetBuildComplexity", "n", "number", n)
    if tm and tm.physics and tm.physics.SetBuildComplexity then
        pcall(tm.physics.SetBuildComplexity, n)
    end
    return self
end

LFTME._registerService("World", function(_engine)
    return _newWorld()
end)

--------------------------------------------------------------------------------
-- UI service
--
-- Show stuff on a player's HUD: text labels (which you can update or
-- remove), big middle-of-screen popups, and small corner notifications.
--
-- HEADS UP: label keys are NOT automatically namespaced. If you and
-- another mod both use the key "score", you will overwrite each
-- other. Pick a prefix unique to your mod (e.g. "lululabs_score").
--------------------------------------------------------------------------------

local UI = {}
UI.__index = UI

-- Internal: build a new UI service. Holds no state -- methods call
-- straight through to Trailmakers.
local function _newUI()
    return setmetatable({ _className = "UI" }, UI)
end

-- Internal: accept either a Player object or a raw numeric id and
-- return the numeric id. Throws a helpful error if you pass something
-- else. Used by every UI method so they all accept both forms.
local function _uiPlayerId(method, p)
    if type(p) == "number" then return p end
    if type(p) == "table" and p._className == "Player" then return p.Id end
    _typeError("UI", method, "player", "Player or numeric id", p)
end

-- Add (or replace) a text label on a player's HUD. The `key` is your
-- handle for updating or removing the label later -- pick something
-- unique to your mod so you do not clash with other mods. `player`
-- can be a Player object or a raw numeric id. Useful for score
-- displays, mission timers, status indicators. Returns self for
-- chaining (wraps `tm.playerUI.AddUILabel`).
function UI:AddLabel(player, key, text)
    local id = _uiPlayerId("AddLabel", player)
    _expectType("UI", "AddLabel", "key", "string", key)
    _expectType("UI", "AddLabel", "text", "string", text)
    if tm and tm.playerUI and tm.playerUI.AddUILabel then
        pcall(tm.playerUI.AddUILabel, id, key, text)
    end
    return self
end

-- Change the text of a label you already added. Behaviour is identical
-- to `AddLabel` (Trailmakers treats add-with-existing-key as update);
-- this method exists so your code reads more clearly when you mean
-- "update" vs "create". Returns self for chaining.
function UI:UpdateLabel(player, key, text)
    return self:AddLabel(player, key, text)
end

-- Remove every UI label this mod added for the given player. Labels
-- added by other mods are NOT touched -- Trailmakers scopes the clear
-- to the calling mod. Returns self for chaining
-- (wraps `tm.playerUI.ClearUI`).
function UI:ClearLabels(player)
    local id = _uiPlayerId("ClearLabels", player)
    if tm and tm.playerUI and tm.playerUI.ClearUI then
        pcall(tm.playerUI.ClearUI, id)
    end
    return self
end

-- Show a big middle-of-screen notification to every player.
-- `duration` is in seconds and defaults to 5. Use sparingly -- it
-- covers the middle of the screen, so save it for important things
-- like round-start announcements. Returns self for chaining
-- (wraps `tm.playerUI.ShowIntrusiveMessageForAllPlayers`).
function UI:ShowIntrusive(title, body, duration)
    _expectType("UI", "ShowIntrusive", "title", "string", title)
    _expectType("UI", "ShowIntrusive", "body", "string", body)
    if duration ~= nil then
        _expectType("UI", "ShowIntrusive", "duration", "number", duration)
    end
    if tm and tm.playerUI and tm.playerUI.ShowIntrusiveMessageForAllPlayers then
        pcall(tm.playerUI.ShowIntrusiveMessageForAllPlayers, title, body, duration or 5)
    end
    return self
end

-- Show a small corner-of-screen notification to every player. Much
-- less in-your-face than `ShowIntrusive`, so it is good for low-key
-- info (hints, "+1 score", etc.). `duration` is in seconds and
-- defaults to 5. Returns self for chaining
-- (wraps `tm.playerUI.AddSubtleMessageForAllPlayers`).
function UI:ShowSubtle(title, body, duration)
    _expectType("UI", "ShowSubtle", "title", "string", title)
    _expectType("UI", "ShowSubtle", "body", "string", body)
    if duration ~= nil then
        _expectType("UI", "ShowSubtle", "duration", "number", duration)
    end
    if tm and tm.playerUI and tm.playerUI.AddSubtleMessageForAllPlayers then
        pcall(tm.playerUI.AddSubtleMessageForAllPlayers, title, body, duration or 5)
    end
    return self
end

LFTME._registerService("UI", function(_engine)
    return _newUI()
end)

--------------------------------------------------------------------------------
-- Audio service
--
-- Play named sound effects at a position in the world. Trailmakers
-- knows a set of built-in sound names; pass an unknown name and the
-- call is silently ignored (no error).
--
-- Useful for explosions, pickup chimes, ambient noises, or punctuating
-- gameplay moments.
--------------------------------------------------------------------------------

local Audio = {}
Audio.__index = Audio

-- Internal: build a new Audio service. Holds no state -- methods call
-- straight through to Trailmakers.
local function _newAudio()
    return setmetatable({ _className = "Audio" }, Audio)
end

-- Play a sound effect at a Vector3 position in the world. `name` must
-- be a sound identifier Trailmakers knows about -- pass anything else
-- and nothing happens (no error). Useful for distance-attenuated
-- effects like a chime when a player picks something up. Returns
-- self for chaining (wraps `tm.audio.PlayAudioAtPosition`).
function Audio:PlayAtPosition(position, name)
    _expectInstance("Audio", "PlayAtPosition", "position", "Vector3", position)
    _expectType("Audio", "PlayAtPosition", "name", "string", name)
    if tm and tm.audio and tm.audio.PlayAudioAtPosition then
        pcall(tm.audio.PlayAudioAtPosition,
            _makeHostVec3(position.X, position.Y, position.Z), name)
    end
    return self
end

LFTME._registerService("Audio", function(_engine)
    return _newAudio()
end)

--------------------------------------------------------------------------------
-- Extra Player methods (added once the other services exist)
--------------------------------------------------------------------------------

-- Send the player back to their spawn point. Useful for "respawn" or
-- "reset" buttons. Returns self for chaining
-- (wraps `tm.players.TeleportPlayerToSpawnPoint`).
function Player:TeleportToSpawn()
    if tm and tm.players and tm.players.TeleportPlayerToSpawnPoint then
        pcall(tm.players.TeleportPlayerToSpawnPoint, self.Id)
    end
    return self
end

-- Allow or block this player from entering build mode. A common
-- moderation tool -- pair with `SetRepairEnabled(false)` to make a
-- spectator who cannot build or fix things. Returns self for chaining
-- (wraps `tm.players.SetBuilderEnabled`).
function Player:SetBuilderEnabled(enabled)
    _expectType("Player", "SetBuilderEnabled", "enabled", "boolean", enabled)
    if tm and tm.players and tm.players.SetBuilderEnabled then
        pcall(tm.players.SetBuilderEnabled, self.Id, enabled)
    end
    return self
end

-- Allow or block this player from repairing damaged blocks. Useful
-- for combat modes where you want damage to stick around. Returns
-- self for chaining (wraps `tm.players.SetRepairEnabled`).
function Player:SetRepairEnabled(enabled)
    _expectType("Player", "SetRepairEnabled", "enabled", "boolean", enabled)
    if tm and tm.players and tm.players.SetRepairEnabled then
        pcall(tm.players.SetRepairEnabled, self.Id, enabled)
    end
    return self
end

-- Get the player's stable profile id as a string. This survives
-- reconnects, unlike `Id` which is just their current session slot.
-- Use this as the key when you want to remember anything about a
-- specific player across sessions (high scores, settings, bans).
-- Returns an empty string if Trailmakers cannot answer.
-- (Wraps `tm.players.GetPlayerProfileId`.)
function Player:GetProfileId()
    if tm and tm.players and tm.players.GetPlayerProfileId then
        local ok, v = pcall(tm.players.GetPlayerProfileId, self.Id)
        if ok and v ~= nil then return tostring(v) end
    end
    return ""
end

-- Replace the placeholder version of `SpawnObjectNearby` from earlier
-- in the file with a working one, now that ObjectSpawner exists.
function Player:SpawnObjectNearby(prefab, offset)
    local engine = LFTME.Get()
    if engine == nil then
        error(_runtimeError("Player", "SpawnObjectNearby",
            "engine has not been constructed. Call LFTME.New() first."), 0)
    end
    local spawner = engine:GetService("ObjectSpawner")
    local pos = self:GetPosition()
    if offset ~= nil then
        _expectInstance("Player", "SpawnObjectNearby", "offset", "Vector3", offset)
        pos = pos + offset
    end
    local obj = spawner:SpawnObject(prefab)
    obj:Position(pos)
    return obj
end

--------------------------------------------------------------------------------
-- Extra SpawnedObject methods
--------------------------------------------------------------------------------

-- Get the spawned object's current position as a Vector3. Useful for
-- detecting whether something has moved (e.g. a physics-enabled prop
-- has tipped over). Returns `Vector3.new(0, 0, 0)` if Trailmakers
-- cannot answer.
function SpawnedObject:GetPosition()
    _ensureLive(self, "GetPosition")
    local result = Vector3.new(0, 0, 0)
    _withTransform(self, function(t)
        if t.GetPositionWorld then
            local ok, hostVec = pcall(t.GetPositionWorld, t)
            if ok and hostVec then
                result = _hostVec3ToVector3(hostVec)
            end
        end
    end)
    return result
end

--------------------------------------------------------------------------------
-- Extra ObjectSpawner methods
--
-- Browsing the prefab catalog, registering custom meshes/textures,
-- spawning at a specific Vector3, and clearing every spawn at once.
--------------------------------------------------------------------------------

-- Spawn a prefab directly at a Vector3 position. Same as
-- `SpawnObject(prefab):Position(pos)` but in one call. Useful when
-- you already have a position computed and you do not want to chain.
-- Returns a SpawnedObject with the usual chainable methods.
function ObjectSpawner:SpawnAt(prefab, position)
    local resolved, err = self:ResolvePrefab(prefab)
    if not resolved then error(err, 0) end
    _expectInstance("ObjectSpawner", "SpawnAt", "position", "Vector3", position)
    if not (tm and tm.physics and tm.physics.SpawnObject) then
        error(_runtimeError("ObjectSpawner", "SpawnAt",
            "host API tm.physics.SpawnObject is not available."), 0)
    end
    local ok, modGameObject = pcall(tm.physics.SpawnObject,
        _makeHostVec3(position.X, position.Y, position.Z), resolved)
    if not ok or not modGameObject then
        error(_runtimeError("ObjectSpawner", "SpawnAt",
            "host failed to spawn " .. resolved .. ": " .. tostring(modGameObject)), 0)
    end
    return _newSpawnedObject(modGameObject, resolved)
end

-- Get a fresh array of every prefab name Trailmakers knows you can
-- spawn. The result is a copy you own; changing it does not affect
-- Trailmakers. Returns an empty table if Trailmakers cannot answer.
-- Handy for building in-game catalog browsers or "list all prefabs"
-- chat commands. (Wraps `tm.physics.SpawnableNames`.)
function ObjectSpawner:GetCatalog()
    if not (tm and tm.physics and tm.physics.SpawnableNames) then return {} end
    local ok, names = pcall(tm.physics.SpawnableNames)
    if not ok or type(names) ~= "table" then return {} end
    local out = {}
    for i = 1, #names do out[i] = names[i] end
    return out
end

-- Despawn every object this mod has spawned. Player-built creations
-- are NOT touched. Useful at mod shutdown to leave the world clean,
-- or when restarting a round and you want to wipe the previous one's
-- props. Returns self for chaining (wraps `tm.physics.ClearAllSpawns`).
function ObjectSpawner:ClearAllSpawns()
    if tm and tm.physics and tm.physics.ClearAllSpawns then
        pcall(tm.physics.ClearAllSpawns)
    end
    return self
end

-- Register a custom 3D mesh by name, using raw OBJ-format data as a
-- string. After this you can pass `name` to `SpawnCustom` to spawn
-- copies of it. Re-registering the same name replaces the previous
-- mesh. Useful when you want to ship a mod with custom prop models
-- bundled in. Returns self for chaining (wraps `tm.physics.AddMesh`).
function ObjectSpawner:AddMesh(name, data)
    _expectType("ObjectSpawner", "AddMesh", "name", "string", name)
    _expectType("ObjectSpawner", "AddMesh", "data", "string", data)
    if tm and tm.physics and tm.physics.AddMesh then
        pcall(tm.physics.AddMesh, name, data)
    end
    return self
end

-- Register a custom texture by name, using raw PNG or JPG file bytes
-- as a string. After this you can pair `name` with a mesh in
-- `SpawnCustom`. Useful for skinning a custom mesh with your own
-- artwork. Returns self for chaining (wraps `tm.physics.AddTexture`).
function ObjectSpawner:AddTexture(name, data)
    _expectType("ObjectSpawner", "AddTexture", "name", "string", name)
    _expectType("ObjectSpawner", "AddTexture", "data", "string", data)
    if tm and tm.physics and tm.physics.AddTexture then
        pcall(tm.physics.AddTexture, name, data)
    end
    return self
end

-- Spawn a custom mesh + texture combo you registered earlier with
-- `AddMesh` / `AddTexture`. Both names must already be known.
-- Returns a SpawnedObject with the usual chainable methods. Useful
-- for shipping mods with bespoke props.
-- (Wraps `tm.physics.SpawnCustomObjectConcave`.)
function ObjectSpawner:SpawnCustom(position, meshName, textureName)
    _expectInstance("ObjectSpawner", "SpawnCustom", "position", "Vector3", position)
    _expectType("ObjectSpawner", "SpawnCustom", "meshName", "string", meshName)
    _expectType("ObjectSpawner", "SpawnCustom", "textureName", "string", textureName)
    if not (tm and tm.physics and tm.physics.SpawnCustomObjectConcave) then
        error(_runtimeError("ObjectSpawner", "SpawnCustom",
            "host API tm.physics.SpawnCustomObjectConcave is not available."), 0)
    end
    local ok, modGameObject = pcall(tm.physics.SpawnCustomObjectConcave,
        _makeHostVec3(position.X, position.Y, position.Z), meshName, textureName)
    if not ok or not modGameObject then
        error(_runtimeError("ObjectSpawner", "SpawnCustom",
            "host failed to spawn custom mesh " .. meshName .. ": " ..
            tostring(modGameObject)), 0)
    end
    return _newSpawnedObject(modGameObject, meshName)
end

--------------------------------------------------------------------------------
-- Extra UpdateService method: tune how often the engine updates
--------------------------------------------------------------------------------

-- Ask Trailmakers to call this mod's `update(dt)` at a slower rate.
-- `dt` is the target time between updates in seconds: `1/60` for 60
-- updates/sec, `1/30` for 30, `0.1` for 10. Useful for cutting CPU
-- cost on a mod that does not need a high update rate. Trailmakers
-- may run faster than this (it caps at the game's own frame rate),
-- but never slower. Returns self for chaining
-- (wraps `tm.os.SetModTargetDeltaTime`).
function UpdateService:SetTargetDelta(dt)
    _expectType("UpdateService", "SetTargetDelta", "dt", "number", dt)
    if dt <= 0 then
        error(_runtimeError("UpdateService", "SetTargetDelta",
            "delta must be positive; got " .. tostring(dt) .. "."), 0)
    end
    if tm and tm.os and tm.os.SetModTargetDeltaTime then
        pcall(tm.os.SetModTargetDeltaTime, dt)
    end
    return self
end


--------------------------------------------------------------------------------
-- Extra helpers added later to close gaps a real mod hit in practice
--------------------------------------------------------------------------------

-- Read a file from the mod's `data_static/` folder. This folder ships
-- with the mod and is read-only at runtime, so use it for assets
-- bundled with the mod (config files, default data, etc.). Returns
-- the file contents as a string, or `nil` if the file is missing or
-- the read fails -- never throws.
-- (Wraps `tm.os.ReadAllText_Static`.)
function ModStorage:ReadStatic(path)
    _expectType("ModStorage", "ReadStatic", "path", "string", path)
    if not (tm and tm.os and tm.os.ReadAllText_Static) then return nil end
    local ok, contents = pcall(tm.os.ReadAllText_Static, path)
    if not ok or type(contents) ~= "string" then return nil end
    return contents
end

-- Read a JSON file from the mod's `data_static/` folder and decode
-- it into a Lua value. Returns `(nil, errorMessage)` if the file is
-- missing, empty, or malformed; never throws. Useful for loading
-- default settings or static data that ships with the mod.
function ModStorage:ReadStaticJSON(path)
    local text = self:ReadStatic(path)
    if text == nil then return nil, "static file not found" end
    if text == "" then return nil, "empty static file" end
    return _json.decode(text)
end

-- True if this player can be killed right now. Returns false when the
-- player is invincible, or in the gap between dying and respawning,
-- or when Trailmakers cannot answer. Useful to skip damage logic
-- gracefully instead of trying to kill someone who is already gone.
-- (Wraps `tm.players.CanKillPlayer`.)
function Player:CanKill()
    if tm and tm.players and tm.players.CanKillPlayer then
        local ok, v = pcall(tm.players.CanKillPlayer, self.Id)
        if ok then return v and true or false end
    end
    return false
end

-- Get the id of the structure (build) this player is currently in or
-- on, or `nil` if they are not in a seat / not standing on a build.
-- Useful for "team by vehicle" or "scoring by structure" mods.
-- (Wraps `tm.players.OccupiedStructure`.)
function Player:GetOccupiedStructure()
    if tm and tm.players and tm.players.OccupiedStructure then
        local ok, v = pcall(tm.players.OccupiedStructure, self.Id)
        if ok then return v end
    end
    return nil
end

-- Cap how many blocks this player can place. Pass a non-negative
-- whole number; 0 disables placement entirely. Useful for limited
-- build challenges. Returns self for chaining
-- (wraps `tm.players.SetBlockLimit`).
function Player:SetBlockLimit(n)
    _expectType("Player", "SetBlockLimit", "n", "number", n)
    if tm and tm.players and tm.players.SetBlockLimit then
        pcall(tm.players.SetBlockLimit, self.Id, n)
    end
    return self
end

-- Set this player's per-session spawn location to the given Vector3.
-- Most mods use this for "checkpoint reached" features in races or
-- platformers. Returns self for chaining (wraps
-- `tm.players.SetPlayerSpawnLocation`, with a fallback for older builds).
function Player:SetSpawnPoint(position)
    _expectInstance("Player", "SetSpawnPoint", "position", "Vector3", position)
    if tm and tm.players and tm.players.SetPlayerSpawnLocation then
        pcall(tm.players.SetPlayerSpawnLocation, self.Id,
            _makeHostVec3(position.X, position.Y, position.Z))
    elseif tm and tm.players and tm.players.SetSpawnPoint then
        pcall(tm.players.SetSpawnPoint, self.Id,
            _makeHostVec3(position.X, position.Y, position.Z))
    end
    return self
end

-- Set the default spawn location for the WHOLE server -- where new
-- joiners and respawning players appear. Distinct from
-- `Player:SetSpawnPoint`, which only affects one player. Returns self
-- for chaining (wraps `tm.players.SetSpawnPoint`).
function Players:SetGlobalSpawnPoint(position)
    _expectInstance("Players", "SetGlobalSpawnPoint", "position", "Vector3", position)
    if tm and tm.players and tm.players.SetSpawnPoint then
        pcall(tm.players.SetSpawnPoint,
            _makeHostVec3(position.X, position.Y, position.Z))
    end
    return self
end

-- Set how long one full day cycle takes, in seconds. Larger numbers
-- mean slower day/night transitions (5 minutes feels brisk; 30
-- minutes feels lived-in). Throws if you pass zero or a negative
-- value. Returns self for chaining
-- (wraps `tm.world.SetCycleDurationTimeOfDay`).
function World:SetTimeOfDayCycleDuration(seconds)
    _expectType("World", "SetTimeOfDayCycleDuration", "seconds", "number", seconds)
    if seconds <= 0 then
        error(_runtimeError("World", "SetTimeOfDayCycleDuration",
            "duration must be positive; got " .. tostring(seconds) .. "."), 0)
    end
    if tm and tm.world and tm.world.SetCycleDurationTimeOfDay then
        pcall(tm.world.SetCycleDurationTimeOfDay, seconds)
    end
    return self
end

--------------------------------------------------------------------------------
-- Camera service
--
-- Per-player named cameras. You add a camera at a position (and
-- optionally a rotation), give it a name, and later switch the
-- player's view to it on demand. Trailmakers keeps names unique
-- per-player, so two players can each have a "scoreboard" camera
-- without clashing.
--
-- Useful for cinematics, killcams, replays, and freecam admin tools.
--------------------------------------------------------------------------------

local Camera = {}
Camera.__index = Camera

-- Internal: build a new Camera service. Holds no state -- methods
-- call straight through to Trailmakers' camera functions.
local function _newCamera()
    return setmetatable({ _className = "Camera" }, Camera)
end

-- Internal: accept either a Player object or a numeric id and return
-- the numeric id. Throws a helpful error otherwise. Used so every
-- Camera method works the same for both forms.
local function _cameraPlayerId(method, p)
    if type(p) == "number" then return p end
    if type(p) == "table" and p._className == "Player" then return p.Id end
    _typeError("Camera", method, "player", "Player or numeric id", p)
end

-- Register a new named camera for this player. `position` is a
-- Vector3 in world space; `rotation` is an optional Vector3 of Euler
-- angles in degrees (defaults to no rotation). You can switch to this
-- camera later with `Activate(player, name)`. Returns self for chaining
-- (wraps `tm.players.AddCamera`).
function Camera:Add(player, name, position, rotation)
    local id = _cameraPlayerId("Add", player)
    _expectType("Camera", "Add", "name", "string", name)
    _expectInstance("Camera", "Add", "position", "Vector3", position)
    local hostPos = _makeHostVec3(position.X, position.Y, position.Z)
    local hostRot
    if rotation ~= nil then
        _expectInstance("Camera", "Add", "rotation", "Vector3", rotation)
        hostRot = _makeHostVec3(rotation.X, rotation.Y, rotation.Z)
    else
        hostRot = _makeHostVec3(0, 0, 0)
    end
    if tm and tm.players and tm.players.AddCamera then
        pcall(tm.players.AddCamera, id, name, hostPos, hostRot)
    end
    return self
end

-- Switch the player's view to a named camera you previously added.
-- Useful for cinematics and replays. Returns self for chaining
-- (wraps `tm.players.ActivateCamera`).
function Camera:Activate(player, name)
    local id = _cameraPlayerId("Activate", player)
    _expectType("Camera", "Activate", "name", "string", name)
    if tm and tm.players and tm.players.ActivateCamera then
        pcall(tm.players.ActivateCamera, id, name)
    end
    return self
end

-- Remove a named camera. Does nothing if no camera with that name
-- exists for this player. Returns self for chaining
-- (wraps `tm.players.RemoveCamera`).
function Camera:Remove(player, name)
    local id = _cameraPlayerId("Remove", player)
    _expectType("Camera", "Remove", "name", "string", name)
    if tm and tm.players and tm.players.RemoveCamera then
        pcall(tm.players.RemoveCamera, id, name)
    end
    return self
end

LFTME._registerService("Camera", function(_engine)
    return _newCamera()
end)

--------------------------------------------------------------------------------
-- Color3 presets
--
-- Ready-made colors so you can write `Color3.Red` instead of building
-- one with `Color3.new(1, 0, 0)`. Note that these are values, not
-- functions -- there are no parentheses. Treat them as constants;
-- if you need a different shade, build a fresh `Color3.new(...)`.
--------------------------------------------------------------------------------

Color3.Red     = Color3.new(1, 0, 0)
Color3.Green   = Color3.new(0, 1, 0)
Color3.Blue    = Color3.new(0, 0, 1)
Color3.Yellow  = Color3.new(1, 1, 0)
Color3.Cyan    = Color3.new(0, 1, 1)
Color3.Magenta = Color3.new(1, 0, 1)
Color3.White   = Color3.new(1, 1, 1)
Color3.Black   = Color3.new(0, 0, 0)
Color3.Gray    = Color3.new(0.5, 0.5, 0.5)
Color3.Grey    = Color3.Gray

-- END_LFTME_EXTENSIONS
--------------------------------------------------------------------------------
-- 10. The Engine itself
--
-- `LFTME.New()` builds the one engine instance the first time you call
-- it, and throws an error if you call it again. `LFTME.Get()` gives you
-- the existing engine, or `(nil, err)` if `New()` has not run yet.
--
-- Things you can do with the engine:
--   * `engine:GetService("ServiceName")` -- get the service object
--   * `engine.Settings` -- a table of engine-wide settings you can
--                          read and change (see `_defaultSettings`).
--
-- Anything else you might want -- player lookups, spawning, chat,
-- saving data -- lives on a service, accessed via `GetService`.
--------------------------------------------------------------------------------

local Engine = {}
Engine.__index = Engine

-- Holds the single engine instance once `New()` runs. `Get()` reads it.
-- Stays nil until then so you can tell whether `New` has been called.
local _engineInstance = nil

-- The default values for the `engine.Settings` table. Mods are free to
-- change values on `engine.Settings` -- the engine reads them live. See
-- DESIGN.md for what each setting does.
local function _defaultSettings()
    return {
        WarnOnRawPrefabStrings = false,
    }
end

-- Look up a service by name. The first call builds it; later calls
-- return the same one. Throws an error if there is no service with
-- that name -- service names are a fixed list, not arbitrary keys.
--
-- Common names: "Players", "Chat", "Logger", "ObjectSpawner",
-- "ModStorage", "World", "UI", "Audio", "Camera", "UpdateService".
function Engine:GetService(name)
    _expectType("Engine", "GetService", "name", "string", name)
    local cached = self._services[name]
    if cached then
        return cached
    end
    local factory = _serviceFactories[name]
    if not factory then
        error(_runtimeError("Engine", "GetService", 'no service named "' .. name .. '".'), 0)
    end
    -- Pass the engine to the factory so a service can keep a reference
    -- to it (for talking to OTHER services later) without reaching into
    -- the global namespace. The factory is in charge of creating any
    -- signals and private state the service needs.
    local svc = factory(self)
    self._services[name] = svc
    return svc
end

-- Build the engine. This is what your `main.lua` calls right after
-- loading this file. Throws if you call it twice -- there is only ever
-- one engine per mod. Returns the engine instance.
function LFTME.New()
    if _engineInstance ~= nil then
        error(_runtimeError("LFTME", "New", "engine instance already exists."), 0)
    end
    local self = setmetatable({
        _className = "Engine",
        _services = {},
        Settings = _defaultSettings(),
    }, Engine)
    _engineInstance = self
    -- Build UpdateService right away. We want its `update(dt)` hook
    -- installed before any of your code runs, because everything that
    -- can pause and resume (`task.spawn`, `task.wait`, `task.delay`,
    -- signal `:Wait()`) needs the update loop alive to work.
    self:GetService("UpdateService")
    -- Build Players right away too. Its join/leave event bridges need
    -- to be hooked into Trailmakers before any code runs, so that a
    -- player joining the same instant the mod loads is not missed.
    self:GetService("Players")
    return self
end

-- Return the existing engine, or `(nil, err)` if `New()` has not been
-- called yet. Never throws -- safe to call from helper libraries that
-- do not know whether the engine is up yet.
function LFTME.Get()
    if _engineInstance == nil then
        return nil, _runtimeError("LFTME", "Get", "engine has not been constructed. Call LFTME.New() first.")
    end
    return _engineInstance
end

--------------------------------------------------------------------------------
-- 11. Public type table
--
-- The data types you can use directly from your mod, hung off the
-- engine's namespace. You can access them either through the namespace
--   `LFTME.Vector3.new(0, 1, 0)`
-- or, more conveniently, by making short local aliases at the top of
-- your `main.lua`:
--   `local Vector3 = LFTME.Vector3`
--   `local Color3  = LFTME.Color3`
--
-- `Signal` and `TaskHandle` are exposed for advanced use (e.g. you
-- want to build your own signals or pretend something is a TaskHandle);
-- you do not need them for normal mods.
--------------------------------------------------------------------------------

LFTME.Vector3 = Vector3
LFTME.Color3 = Color3
LFTME.MarkupText = MarkupText
LFTME.Signal = Signal
LFTME.TaskHandle = TaskHandle
LFTME.TaskManager = TaskManager
LFTME.task = task

--------------------------------------------------------------------------------
-- 12. Globals
--
-- The engine creates exactly two global names so it is easy to find from
-- anywhere in your mod, without polluting the global namespace:
--
--   * `LuluFluffysTrailmakersModEngine` -- the full name
--   * `LFTME`                           -- the short alias most code uses
--
-- Both point at the same table. Everything else (services, data types,
-- etc.) is reached through one of these or through the engine instance
-- you get back from `LFTME.New()`.
--------------------------------------------------------------------------------

rawset(_G, "LuluFluffysTrailmakersModEngine", LFTME)
rawset(_G, "LFTME", LFTME)

return LFTME
