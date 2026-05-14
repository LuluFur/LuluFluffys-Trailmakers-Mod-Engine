--------------------------------------------------------------------------------
-- LuluFluffy's Trailmakers Mod Engine (LFTME)
--
-- A Roblox-Studio-flavored abstraction layer on top of the Trailmakers `tm.*`
-- modding API. The goal is that a hobbyist modder can spawn objects, listen
-- for chat, react to players joining, and persist data without ever typing
-- `tm.`.
--
-- LOAD MODEL
--   This file lives in the mod's `data_static/` folder. The modder's
--   `main.lua` loads it once at the top with:
--
--       local LFTME = tm.os.DoFile("engine.lua")
--       local engine = LFTME.New()
--
--   `tm.os.DoFile` resolves paths relative to `data_static/`. Subfolders
--   inside `data_static/` are reportedly not supported by the host, so the
--   engine is shipped as a single flat file.
--
-- HOW TO READ THIS FILE
--   The file is organised top-to-bottom in dependency order:
--
--     1. Internal utilities (typechecking, error templates, debug helpers)
--     2. Signal / Connection (the event primitive every service uses)
--     3. DataTypes: Vector3, Color3, MarkupText
--     4. Logger (leveled file-backed logging service)
--     5. Scheduler, task library, and UpdateService
--     6. TaskManager (heterogeneous cleanup primitive)
--     7. Players service (Player class + lifecycle + lookup)
--     8. Chat service (panel line + intrusive popup + MessageReceived)
--     9. ObjectSpawner service (Phase 1 skeleton: spawn + transform)
--    10. The Engine singleton (LFTME.New / LFTME.Get / GetService)
--    11. Module surface (datatypes exposed on the namespace)
--    12. Globals + return value
--
--   Public-facing names use PascalCase (`Vector3.new`, `engine:GetService`).
--   Private/internal state uses `_camelCase` (`self._connections`). Constants
--   are LOUD_SNAKE_CASE.
--
-- DESIGN INVARIANTS
--   * The engine is a singleton per Lua state.
--   * Programmer errors throw via `error(...)`. Expected failures return
--     `nil, err`. Both use a shared message prefix produced by `_makePrefix`.
--   * Signal dispatch is pcall-isolated: a thrown user handler never aborts
--     other handlers in the same fire.
--   * DataTypes (Vector3, Color3, MarkupText) are immutable from the
--     modder's perspective. Methods return new instances.
--
-- See DESIGN.md for the full public-API contract this file implements.
--------------------------------------------------------------------------------

-- The single module table we will populate and return at the end of the file.
-- The two global names `LuluFluffysTrailmakersModEngine` and `LFTME` are
-- assigned to this same table near the bottom of the file.
local LFTME = {}

-- Reference to the host modding API. Held in a local so tests can monkeypatch
-- `tm` without leaking globals, and so an absent `tm` (running this file
-- under plain Lua for unit tests) fails loudly the first time a host call is
-- made rather than silently nil-indexing.
local tm = rawget(_G, "tm")

-- Forward-declared file-locals that span multiple sections below. They
-- live here, above section 1, because Lua resolves upvalues by lexical
-- declaration order and section 2 (Signal:Wait) needs to see the same
-- `_managedCoroutines` table that section 5 (the scheduler) writes to.
-- Declaring them earlier and assigning later keeps the upvalue identity
-- consistent across sections.

-- Weak-keyed registry: coroutines created by `task.spawn` are added here
-- so `task.wait` and `Signal:Wait` can assert "you are inside a managed
-- coroutine" before yielding. Weak keys mean a finished coroutine drops
-- out automatically without retention pressure on the scheduler.
local _managedCoroutines = setmetatable({}, { __mode = "k" })

-- Set by the UpdateService factory at first construction. The `task`
-- library reads it directly so user code does not need to GetService
-- before calling `task.spawn` / `task.wait` / `task.delay`. Stays nil
-- until `LFTME.New()` runs (which eagerly constructs UpdateService).
local _updateServiceInstance = nil

--------------------------------------------------------------------------------
-- 1. Internal utilities
--------------------------------------------------------------------------------

-- Walk back up the call stack to find the user's call site. Engine-internal
-- frames live inside this file, so we skip them and report the first frame
-- whose `source` differs from our own.
--
-- Returns "<short_src>:<currentline>", e.g. "main.lua:34". Falls back to
-- "?:?" if `debug.getinfo` is unavailable (some sandboxed hosts strip it).
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

-- Build the shared prefix `<ClassOrService>:<Method>(<file>:<line>)` that
-- every engine error message starts with. See DESIGN.md section 4.
local function _makePrefix(className, methodName)
    return tostring(className) .. ":" .. tostring(methodName) .. "(" .. _userCallSite() .. ")"
end

-- Render an arbitrary value for inclusion in an error message. Strings are
-- quoted, numbers/booleans/nil printed verbatim, tables are summarised
-- (never dumped wholesale).
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

-- Produce a type-error message and throw. Used by parameter typechecks.
local function _typeError(className, methodName, paramName, expectedType, actualValue)
    error(string.format(
        '%s expected %s for parameter "%s", got %s',
        _makePrefix(className, methodName),
        expectedType,
        paramName,
        _describeValue(actualValue)
    ), 0)
end

-- Produce a runtime-failure message. Caller decides whether to `error()` it
-- (programmer error) or return it as `nil, err` (expected failure).
local function _runtimeError(className, methodName, message)
    return _makePrefix(className, methodName) .. " " .. message
end

-- Cheap "is this a Foo?" predicate that does not assume metatables. Datatype
-- instances carry a `_className` field; checking that field is faster than
-- a metatable walk and survives table copying.
local function _isInstanceOf(value, className)
    return type(value) == "table" and rawget(value, "_className") == className
end

-- Assert a parameter matches an expected primitive type, or throw a
-- type-error. `expected` is a Lua type name ("string", "number", ...).
local function _expectType(className, methodName, paramName, expected, value)
    if type(value) ~= expected then
        _typeError(className, methodName, paramName, expected, value)
    end
end

-- Assert a parameter is an instance of a named engine class, or throw.
local function _expectInstance(className, methodName, paramName, expected, value)
    if not _isInstanceOf(value, expected) then
        _typeError(className, methodName, paramName, expected, value)
    end
end

-- Service factory registry. Keys are service names ("Players", "Chat", ...).
-- Values are constructor functions that take the engine and return the
-- service table. Services are constructed lazily on first `GetService`
-- and then cached on the engine instance.
--
-- This registry and `LFTME._registerService` live above section 2 (rather
-- than next to the engine constructor) because sections 4 (Logger) and
-- 5 (UpdateService) register themselves at file-load time, and Lua
-- executes top-to-bottom -- the function must exist before those calls
-- run.
local _serviceFactories = {}

-- Register a service factory. Called by each service's section during
-- file load; the factory itself is not invoked until first GetService.
function LFTME._registerService(name, factory)
    _expectType("LFTME", "_registerService", "name", "string", name)
    _expectType("LFTME", "_registerService", "factory", "function", factory)
    _serviceFactories[name] = factory
end


--------------------------------------------------------------------------------
-- 2. Signal and Connection
--
-- The event primitive every service uses. Mirrors Roblox's RBXScriptSignal:
--   conn = signal:Connect(fn)   -- repeated dispatch
--   conn = signal:Once(fn)      -- one-shot, auto-disconnects
--   args = signal:Wait()        -- yield current coroutine until next fire
--   signal:Fire(...)            -- engine-internal; user code never calls
--
-- Connections expose `:Disconnect()` and a `Connected` boolean.
--
-- Handler errors are isolated with `pcall`: one bad handler does not stop
-- the rest of the dispatch. Errors are routed through Logger when one is
-- attached; until then they fall back to `print`.
--------------------------------------------------------------------------------

local Connection = {}
Connection.__index = Connection

-- Internal constructor. Users get Connections from `Signal:Connect/Once`,
-- never directly. `_signal` and `_fn` are private fields used only by the
-- owning Signal during dispatch and disconnect.
local function _newConnection(signal, fn)
    return setmetatable({
        _className = "Connection",
        _signal = signal,
        _fn = fn,
        Connected = true,
    }, Connection)
end

-- Break the link between this Connection and its Signal. Idempotent:
-- calling Disconnect twice is a no-op on the second call, not an error.
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

-- Internal constructor. Services create their own Signals as part of init.
local function _newSignal(name)
    return setmetatable({
        _className = "Signal",
        _name = name or "Signal",
        _handlers = {},     -- array of Connection
        _waiters = {},      -- array of coroutine threads parked on Wait()
    }, Signal)
end

-- Attach a function to fire every time the signal fires. Returns a
-- Connection the caller can use to stop listening.
function Signal:Connect(fn)
    _expectType("Signal", "Connect", "fn", "function", fn)
    local conn = _newConnection(self, fn)
    table.insert(self._handlers, conn)
    return conn
end

-- Attach a function that fires at most once, then disconnects itself.
function Signal:Once(fn)
    _expectType("Signal", "Once", "fn", "function", fn)
    local conn
    conn = self:Connect(function(...)
        conn:Disconnect()
        fn(...)
    end)
    return conn
end

-- Yield the current coroutine until the next fire. Returns the fire args.
-- Must be called from a scheduler-managed coroutine; the scheduler check
-- itself lives in UpdateService (added in a later pass). For now we
-- detect "no coroutine" and produce a friendly runtime-failure message.
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

-- Fire the signal. Engine-internal: user code should never call this on a
-- service-owned signal. Dispatching is pcall-isolated per handler so that
-- a thrown user handler does not abort the rest of the dispatch.
function Signal:Fire(...)
    -- Snapshot handlers before iterating: a handler may legally call
    -- Disconnect() on itself or on another handler during dispatch, which
    -- would mutate the underlying array if we iterated it directly.
    local snapshot = {}
    for i = 1, #self._handlers do
        snapshot[i] = self._handlers[i]
    end
    for i = 1, #snapshot do
        local conn = snapshot[i]
        if conn.Connected then
            local ok, err = pcall(conn._fn, ...)
            if not ok then
                -- Route to logger when available, else stderr-equivalent.
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
    -- Resume any coroutines parked on Wait().
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
-- 3. DataTypes
--
-- Three value types: Vector3, Color3, MarkupText. They are immutable from
-- the modder's perspective: methods return new instances rather than
-- mutating self. Value-equality is implemented via `__eq`.
--------------------------------------------------------------------------------

-- Vector3 -- 3D position, direction, or scale. Constructed via Vector3.new.
local Vector3 = {}
Vector3.__index = Vector3

-- Construct a new Vector3. All three components default to 0 when omitted,
-- which makes `Vector3.new()` a convenient zero-vector and `Vector3.new(0,1,0)`
-- a convenient up-vector.
function Vector3.new(x, y, z)
    return setmetatable({
        _className = "Vector3",
        X = x or 0,
        Y = y or 0,
        Z = z or 0,
    }, Vector3)
end

function Vector3.__add(a, b)
    _expectInstance("Vector3", "__add", "rhs", "Vector3", b)
    return Vector3.new(a.X + b.X, a.Y + b.Y, a.Z + b.Z)
end

function Vector3.__sub(a, b)
    _expectInstance("Vector3", "__sub", "rhs", "Vector3", b)
    return Vector3.new(a.X - b.X, a.Y - b.Y, a.Z - b.Z)
end

-- Scalar multiplication: supports both `v * 2` and `2 * v` since Lua tries
-- both operands' metatables.
function Vector3.__mul(a, b)
    if type(a) == "number" then
        return Vector3.new(b.X * a, b.Y * a, b.Z * a)
    elseif type(b) == "number" then
        return Vector3.new(a.X * b, a.Y * b, a.Z * b)
    else
        _typeError("Vector3", "__mul", "rhs", "number", b)
    end
end

function Vector3.__eq(a, b)
    return a.X == b.X and a.Y == b.Y and a.Z == b.Z
end

function Vector3.__tostring(v)
    return string.format("Vector3(%g, %g, %g)", v.X, v.Y, v.Z)
end

-- Euclidean length of the vector.
function Vector3:Magnitude()
    return math.sqrt(self.X * self.X + self.Y * self.Y + self.Z * self.Z)
end

-- Unit vector (length 1) in the same direction. Returns the zero vector
-- if `self` is the zero vector; callers that care should check first.
function Vector3:Unit()
    local mag = self:Magnitude()
    if mag == 0 then
        return Vector3.new(0, 0, 0)
    end
    return Vector3.new(self.X / mag, self.Y / mag, self.Z / mag)
end

function Vector3:Dot(other)
    _expectInstance("Vector3", "Dot", "other", "Vector3", other)
    return self.X * other.X + self.Y * other.Y + self.Z * other.Z
end

function Vector3:Cross(other)
    _expectInstance("Vector3", "Cross", "other", "Vector3", other)
    return Vector3.new(
        self.Y * other.Z - self.Z * other.Y,
        self.Z * other.X - self.X * other.Z,
        self.X * other.Y - self.Y * other.X
    )
end

-- Linear interpolation. `alpha = 0` returns self, `alpha = 1` returns other.
-- Values outside [0,1] extrapolate.
function Vector3:Lerp(other, alpha)
    _expectInstance("Vector3", "Lerp", "other", "Vector3", other)
    _expectType("Vector3", "Lerp", "alpha", "number", alpha)
    return Vector3.new(
        self.X + (other.X - self.X) * alpha,
        self.Y + (other.Y - self.Y) * alpha,
        self.Z + (other.Z - self.Z) * alpha
    )
end

-- Color3 -- RGB triple, components normalised to [0, 1].
local Color3 = {}
Color3.__index = Color3

-- Internal: clamp a component into [0, 1]. Out-of-range values are silently
-- clamped rather than thrown on; colour code regularly produces slight
-- floating point drift and throwing on 1.0000001 would be hostile.
local function _clamp01(n)
    if n < 0 then return 0 end
    if n > 1 then return 1 end
    return n
end

-- Construct from normalised components (each in [0, 1]).
function Color3.new(r, g, b)
    return setmetatable({
        _className = "Color3",
        R = _clamp01(r or 0),
        G = _clamp01(g or 0),
        B = _clamp01(b or 0),
    }, Color3)
end

-- Construct from byte components (each in [0, 255]). The common form when
-- pasting colours out of a design tool.
function Color3.fromRGB(r, g, b)
    return Color3.new((r or 0) / 255, (g or 0) / 255, (b or 0) / 255)
end

function Color3.__eq(a, b)
    return a.R == b.R and a.G == b.G and a.B == b.B
end

function Color3.__tostring(c)
    return string.format("Color3(%g, %g, %g)", c.R, c.G, c.B)
end

-- Linear interpolation between two colours.
function Color3:Lerp(other, alpha)
    _expectInstance("Color3", "Lerp", "other", "Color3", other)
    _expectType("Color3", "Lerp", "alpha", "number", alpha)
    return Color3.new(
        self.R + (other.R - self.R) * alpha,
        self.G + (other.G - self.G) * alpha,
        self.B + (other.B - self.B) * alpha
    )
end

-- Produce a "#RRGGBB" string. Useful for log lines and chat formatting.
function Color3:ToHex()
    return string.format("#%02X%02X%02X",
        math.floor(self.R * 255 + 0.5),
        math.floor(self.G * 255 + 0.5),
        math.floor(self.B * 255 + 0.5)
    )
end

-- MarkupText -- chainable builder for the HTML-style formatting tags that
-- intrusive popups support. The first method called becomes the innermost
-- tag; subsequent calls wrap the previous result.
--
-- The builder is PURE: each chained call returns a new MarkupText. This
-- means partially-built fragments can be reused without surprise:
--
--   local greeting = MarkupText.new("Hello"):Bold()
--   local loud = greeting:Italic()      -- <i><b>Hello</b></i>
--   local quiet = greeting:Small()      -- <small><b>Hello</b></small>
local MarkupText = {}
MarkupText.__index = MarkupText

function MarkupText.new(text)
    _expectType("MarkupText", "new", "text", "string", text)
    return setmetatable({
        _className = "MarkupText",
        _text = text,
    }, MarkupText)
end

function MarkupText.__tostring(m)
    return m._text
end

-- Internal helper: wrap the current text in the given tag and return a new
-- MarkupText. Centralises the "build a new instance" rule so each tag
-- method stays a one-liner.
local function _wrap(self, tag)
    return setmetatable({
        _className = "MarkupText",
        _text = "<" .. tag .. ">" .. self._text .. "</" .. tag .. ">",
    }, MarkupText)
end

function MarkupText:Bold()    return _wrap(self, "b")      end
function MarkupText:Strong()  return _wrap(self, "strong") end
function MarkupText:Italic()  return _wrap(self, "i")      end
function MarkupText:Em()      return _wrap(self, "em")     end
function MarkupText:Mark()    return _wrap(self, "mark")   end
function MarkupText:Small()   return _wrap(self, "small")  end

-- HTML-entity-escape any user-supplied substring. Use this before splicing
-- player names or other untrusted text into an intrusive popup body.
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
-- Leveled logging that writes to `logs.txt` in the mod's `data_dynamic/`
-- folder. Four levels in increasing severity: Debug, Info, Warn, Error.
--
-- Backing model. The host only exposes `tm.os.WriteAllText_Dynamic` (full-
-- file rewrite, no append), so Logger maintains an in-memory line buffer
-- and rewrites `logs.txt` on every emission. This is the documented Phase 1
-- tradeoff: long-running mods that log heavily can exhaust Lua memory.
-- A future phase may add rotation or a streaming sink.
--
-- Logger is obtained like any other service:
--     local Logger = engine:GetService("Logger")
--     Logger:Info("hello")
--
-- The factory also stashes the first Logger constructed on `LFTME._logger`
-- so engine-internal subsystems (notably the `Signal:Fire` pcall isolation
-- path in section 2) can route handler errors through it without holding
-- their own service handle.
--------------------------------------------------------------------------------

local Logger = {}
Logger.__index = Logger

-- Severity ordering. A message whose level is below `self._minLevel`
-- is silently dropped.
local _LOG_LEVELS = { Debug = 1, Info = 2, Warn = 3, Error = 4 }

-- Default file name inside `data_dynamic/`. The host resolves
-- WriteAllText_Dynamic paths relative to that folder, so a bare filename
-- is exactly right.
local DEFAULT_LOG_PATH = "logs.txt"

-- Internal constructor. Use the service factory below for normal access;
-- this is exposed only so tests can spin up a logger without an engine.
local function _newLogger()
    return setmetatable({
        _className = "Logger",
        _lines = {},
        _path = DEFAULT_LOG_PATH,
        _minLevel = "Debug",
        _alsoConsole = true,  -- mirror each line to tm.os.Log for console parity
    }, Logger)
end

-- Change the on-disk file name. Useful for tests; rarely used by mods.
function Logger:SetPath(path)
    _expectType("Logger", "SetPath", "path", "string", path)
    self._path = path
    return self
end

-- Drop all messages strictly below this level. Valid levels:
-- "Debug", "Info", "Warn", "Error".
function Logger:SetMinLevel(level)
    _expectType("Logger", "SetMinLevel", "level", "string", level)
    if not _LOG_LEVELS[level] then
        error(_runtimeError("Logger", "SetMinLevel",
            'unknown level "' .. level .. '". Expected Debug, Info, Warn, or Error.'), 0)
    end
    self._minLevel = level
    return self
end

-- Format a message with optional sprintf-style args. Kept separate from
-- emission so each piece can be tested in isolation. A bad format string
-- in user code is caught here and turned into a "[format error]" suffix
-- on the raw message, rather than throwing out of the logger.
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

-- Build the line: "[12.345] [INFO] message". Timestamp is host time in
-- seconds with three decimals; falls back to "?" when `tm` is absent
-- (running under a plain-Lua test harness).
local function _renderLine(level, body)
    local t
    if tm and tm.os and tm.os.GetTime then
        t = string.format("%.3f", tm.os.GetTime())
    else
        t = "?"
    end
    return "[" .. t .. "] [" .. level .. "] " .. body
end

-- Emit a message at the named level. Internal: the four public level
-- methods below are thin wrappers that bind their level.
function Logger:_emit(level, message, ...)
    if _LOG_LEVELS[level] < _LOG_LEVELS[self._minLevel] then
        return
    end
    local line = _renderLine(level, _format(message, ...))
    table.insert(self._lines, line)
    -- Rewrite the log file. The whole buffer is rewritten because the
    -- host does not expose an append primitive in Phase 1. Wrap in pcall
    -- so a host I/O failure does not crash the mod tick.
    if tm and tm.os and tm.os.WriteAllText_Dynamic then
        pcall(tm.os.WriteAllText_Dynamic, self._path, table.concat(self._lines, "\n"))
    end
    -- Mirror to the host console (the in-game log overlay) for parity.
    if self._alsoConsole and tm and tm.os and tm.os.Log then
        pcall(tm.os.Log, line)
    end
end

function Logger:Debug(message, ...) self:_emit("Debug", message, ...) end
function Logger:Info(message, ...)  self:_emit("Info",  message, ...) end
function Logger:Warn(message, ...)  self:_emit("Warn",  message, ...) end
function Logger:Error(message, ...) self:_emit("Error", message, ...) end

-- Drop the in-memory line buffer. Does NOT delete the on-disk file:
-- the next emission will rewrite `logs.txt` with whatever lines follow.
-- Mods that want a truly empty file should follow `Clear()` with one
-- emission so the rewrite lands.
function Logger:Clear()
    self._lines = {}
    return self
end

-- Register the service. Construction is lazy: the first GetService("Logger")
-- call wins, and that instance is stashed on `LFTME._logger` so the Signal
-- pcall path in section 2 can find it without a service-lookup cycle.
LFTME._registerService("Logger", function(_engine)
    local logger = _newLogger()
    LFTME._logger = logger
    return logger
end)

--------------------------------------------------------------------------------
-- 5. Scheduler, task library, and UpdateService
--
-- These three pieces are presented in one section because they are one
-- mechanism: a single queue of deferred work plus the host's `update(dt)`
-- callback that pumps it. Splitting them across sections would force the
-- reader to jump around to follow a single resume.
--
-- The queue lives on the UpdateService instance. Each entry has one of
-- three types:
--
--   * "resume"  -- payload is a coroutine; resume it at `deadline`.
--   * "after"   -- payload is a function; call it once at `deadline`.
--   * "every"   -- payload is a function; call it at `deadline`, then
--                  bump `deadline` by `interval` and keep the entry.
--
-- All deadlines are in *accumulated tick time*, not wall-clock time.
-- `UpdateService._clock` advances by `dt` on every `update(dt)` call from
-- the host, so a paused or tabbed-out host pauses scheduling too. This is
-- the same honesty principle that names the signal `OnUpdate` rather than
-- `Heartbeat`: precision is whatever the host gives.
--
-- TaskHandle is the cancellation token returned by everything in this
-- section. It is intentionally distinct from Connection (which represents
-- a signal subscription) so that the TaskManager added in a later pass
-- can dispatch the right cleanup verb (`:Cancel` vs `:Disconnect`).
--------------------------------------------------------------------------------

-- TaskHandle ---------------------------------------------------------------

local TaskHandle = {}
TaskHandle.__index = TaskHandle

-- Internal constructor. Users get TaskHandles from `task.spawn`,
-- `task.delay`, `UpdateService:After`, and `UpdateService:Every` --
-- never directly.
local function _newTaskHandle()
    return setmetatable({
        _className = "TaskHandle",
        Cancelled = false,
    }, TaskHandle)
end

-- Cancel the scheduled work this handle represents. Idempotent.
--
-- Cancellation is *lazy* on the queue side: we flip the flag and let the
-- next scheduler pump drop the entry. Eager removal would be O(N) per
-- Cancel and most TaskHandles never get cancelled, so paying that cost up
-- front would be net-negative.
function TaskHandle:Cancel()
    if self.Cancelled then
        return
    end
    self.Cancelled = true
end

-- UpdateService ------------------------------------------------------------

local UpdateService = {}
UpdateService.__index = UpdateService

-- Internal helper: route an error message to the Logger if one exists,
-- else to `tm.os.Log`, else to `print`. Scheduler callbacks are isolated
-- with `pcall` and routed through here so a thrown user callback does not
-- stop the pump.
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

-- Construct the UpdateService and install the `_G.update` hook. Called
-- via the service factory below.
local function _newUpdateService()
    local self = setmetatable({
        _className = "UpdateService",
        _clock = 0,                -- accumulated tick time, seconds
        _queue = {},               -- array of pending scheduler entries
        _previousUpdate = nil,     -- captured `_G.update` from before boot
        OnUpdate = _newSignal("UpdateService.OnUpdate"),
    }, UpdateService)

    -- Capture any pre-existing `_G.update` so a user `update` defined
    -- BEFORE `LFTME.New()` keeps working -- we wrap it. A user `update`
    -- defined AFTER engine construction will overwrite our wrapper and
    -- break scheduling silently; the design doc calls that out loudly.
    self._previousUpdate = rawget(_G, "update")
    rawset(_G, "update", function(dt)
        -- Forward to the user's previous update first, in case the mod
        -- relies on it. pcall so a thrown previous-update does not stop
        -- the engine pump.
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

-- Enqueue a scheduler entry. Internal: called by task.spawn (resume),
-- task.wait (resume), UpdateService:After (after), and
-- UpdateService:Every (every).
function UpdateService:_enqueue(entry)
    table.insert(self._queue, entry)
end

-- Drive one tick of the scheduler. Called from the `_G.update` wrapper.
--
-- Steps in order:
--   1. Advance the engine clock by `dt`.
--   2. Walk the queue. For each entry, drop it if cancelled, defer it if
--      its deadline has not arrived, otherwise fire it. "every" entries
--      are re-queued with their deadline advanced by `interval`.
--   3. Fire `UpdateService.OnUpdate` so user listeners see this tick.
--
-- The walk takes a snapshot of the queue length up front: entries
-- enqueued *during* this tick (e.g. by a callback calling `task.wait`)
-- do not fire on the same tick that scheduled them. That keeps the
-- semantics simple -- "scheduled now, fires at least one tick from now"
-- -- and avoids pathological infinite loops where a callback re-arms
-- a zero-second wait.
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
                -- If the coroutine is dead (someone resumed it elsewhere
                -- since we last touched it), coroutine.resume returns
                -- false with "cannot resume dead coroutine". We treat
                -- that as a normal end-of-life, not an error.
                if coroutine.status(co) ~= "dead" then
                    local ok, err = coroutine.resume(co)
                    if not ok then
                        _logSchedulerError("task.spawn coroutine error: " .. tostring(err))
                    end
                end
                -- If `fn` called task.wait inside, that has already
                -- enqueued a fresh resume entry before yielding.
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
                -- Re-queue from the *intended* deadline, not `now`, so
                -- the cadence does not drift on slow ticks.
                entry.deadline = entry.deadline + entry.interval
                keep[#keep + 1] = entry
            end
        end
    end

    -- Append entries that were enqueued during this tick (those live at
    -- indices > count in self._queue right now).
    local total = #self._queue
    for i = count + 1, total do
        keep[#keep + 1] = self._queue[i]
    end

    self._queue = keep

    -- Fire user listeners last so their handlers see a settled queue.
    self.OnUpdate:Fire(dt)
end

-- Run `fn` once after at least `seconds` of accumulated tick time.
-- Returns a TaskHandle whose `:Cancel()` prevents the fire.
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

-- Run `fn` on a repeating interval of `seconds` of accumulated tick
-- time. Returns a TaskHandle whose `:Cancel()` stops the interval.
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

-- Register UpdateService. The factory also stashes the new instance on
-- the file-local `_updateServiceInstance` so the `task` library below
-- can read it directly without paying a `GetService` lookup per call.
LFTME._registerService("UpdateService", function(_engine)
    local svc = _newUpdateService()
    _updateServiceInstance = svc
    return svc
end)

-- task library -------------------------------------------------------------

-- The Roblox-shaped subset: `task.spawn`, `task.wait`, `task.delay`.
-- All three sit on top of UpdateService.

local task = {}

-- Run `fn(...)` in a fresh scheduler-managed coroutine. Resumes
-- immediately; returns a TaskHandle the caller can cancel.
--
-- Cancelling the handle does NOT forcibly kill the coroutine -- Lua does
-- not give us a portable primitive for that. What it does is set
-- `handle.Cancelled = true` so any pending resume of this coroutine on
-- the scheduler queue is dropped instead of fired. A coroutine that is
-- spinning on tight non-yielding code will run to completion regardless.
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

-- Yield the current scheduler-managed coroutine for at least `seconds`
-- of accumulated tick time. `seconds` defaults to 0 (yield until next
-- tick).
--
-- Errors with the runtime-failure template when called from a coroutine
-- the scheduler does not own, because the yield would never be resumed
-- in that case.
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

-- Alias for `UpdateService:After`. The Roblox idiom is `task.delay`, and
-- a lot of pasted snippets use exactly that name; we keep it working.
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
-- A heterogeneous cleanup primitive. TaskManager tracks "things that need
-- releasing" -- connections, scheduled tasks, engine objects, plain
-- closures -- and releases them all on demand. The Roblox shape is
-- called `Maid`; we use the clearer name TaskManager because outside
-- Roblox `Maid` is opaque.
--
-- Accepted task shapes (dispatched to their natural cleanup verb):
--
--   * Connection       -> :Disconnect()
--   * TaskHandle       -> :Cancel()
--   * any { :Destroy } -> :Destroy()    (SpawnedObject, custom user types)
--   * function         -> call with no args
--
-- Raw `coroutine.create` / `coroutine.wrap` handles are NOT accepted in
-- Phase 1. Lua does not give us a portable way to cancel a yielded
-- coroutine, and silently abandoning one retains its frames and closures.
-- Code that wants cancellable background work should go through
-- `task.spawn`, which returns a real TaskHandle.
--
-- Tokens are returned by `Add` and let you target one specific task with
-- `Remove` (forget without releasing) or `CleanupTask` (release and
-- forget). They are unique by table identity, so they can never collide
-- with task values that happen to be the same shape.
--
-- The same TaskManager is used by the future `Players` service to own
-- per-player resources: `player.TaskManager:Add(connection)` causes
-- the connection to be released automatically when the player leaves.
--------------------------------------------------------------------------------

local TaskManager = {}
TaskManager.__index = TaskManager

-- Internal: guard against use-after-destroy. Throws via the runtime-failure
-- template so the call site is preserved in the message.
local function _ensureNotDestroyed(self, methodName)
    if self._isDestroyed then
        error(_runtimeError("TaskManager", methodName,
            "this TaskManager has been destroyed."), 0)
    end
end

-- Internal: dispatch one task to its appropriate cleanup verb. Returns
-- (ok, err) so the caller can decide whether to log -- a failed release
-- on one task should NOT stop the rest of a Cleanup from running.
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
    -- Unknown shape: pretend success rather than throwing. Add() validates
    -- shape at registration time, so reaching here implies the value
    -- mutated underneath us -- not worth crashing cleanup over.
    return true, nil
end

-- Construct a new TaskManager. Empty until `Add` is called.
function TaskManager.new()
    return setmetatable({
        _className = "TaskManager",
        _tasks = {},          -- ordered array of { token = ..., task = ... }
        _isDestroyed = false,
    }, TaskManager)
end

-- Register a task. Returns an opaque token for later Remove / CleanupTask.
--
-- Validates the shape up front so a Cleanup down the line can't surprise
-- the caller with an "unknown task" message at an awkward moment. Raw
-- coroutines are rejected with a specific message that points the caller
-- at `task.spawn`.
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
    -- Token identity is the empty table, which is unique per call. Using
    -- an integer counter would work but introduces a stale-token hazard
    -- if the manager is reset.
    local token = {}
    table.insert(self._tasks, { token = token, task = task })
    return token
end

-- Forget a task without releasing it. The caller takes ownership of
-- cleanup from this point on. No-op if the token is unknown -- this is
-- friendlier than throwing when a caller is racing two `Remove` calls.
function TaskManager:Remove(token)
    _ensureNotDestroyed(self, "Remove")
    for i = 1, #self._tasks do
        if self._tasks[i].token == token then
            table.remove(self._tasks, i)
            return
        end
    end
end

-- Release one specific task and forget it. Other tasks are untouched.
-- A release that throws is logged via Logger:Error (when available) and
-- the task is still considered cleaned up.
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

-- Release every registered task in REVERSE insertion order. Reverse
-- order matches the common "outer subscribes to inner" pattern where the
-- last task added usually depends on earlier ones; releasing inner-first
-- can leave outer handlers firing against torn-down state.
--
-- The task list is swapped out before iteration so a task that calls
-- `Add` during its own release does not double-fire or grow the list
-- under us. New additions land in the fresh empty list.
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

-- Run a final Cleanup and mark this manager unusable. Further calls
-- throw -- a destroyed manager that silently accepts new tasks would
-- mask resource leaks.
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
-- The live set of human players in the current session, plus the Player
-- class that wraps each host ModPlayer.
--
-- The service:
--   * Fans the host's `tm.players.OnPlayerJoined` / `OnPlayerLeft` events
--     out to the engine signals `PlayerJoinedServer` / `PlayerLeftServer`.
--   * Pre-populates from `tm.players.CurrentPlayers()` at boot so a
--     player who joined before the mod loaded is still visible.
--   * Owns a per-player TaskManager that is auto-destroyed after every
--     `PlayerLeftServer` handler has finished. Mod code that registers
--     per-player connections does not need to remember to clean them up.
--
-- The Player class:
--   * Holds `Name`, `Id`, `TaskManager` as public read-only properties.
--   * Caches the host ModPlayer reference internally so each method call
--     does not re-query the host registry.
--   * Mutator methods (`Teleport`, `Kick`, `Kill`, `Eject`, `SetTeam`,
--     `SetInvincible`, `SetJetpackEnabled`) return `self` for chaining.
--   * Queries (`GetPosition`, `IsInSeat`) return the requested value.
--   * `SpawnObjectNearby` is stubbed in this build -- it depends on the
--     ObjectSpawner service, which lands in a later slice. The stub
--     throws a runtime-failure pointing at the missing dependency rather
--     than silently no-op'ing.
--
-- Lifecycle of departure (exact order):
--   1. Host fires `tm.players.OnPlayerLeft(modPlayer)`.
--   2. Engine fires `Players.PlayerLeftServer:Fire(player)`; all
--      handlers run, with `player.TaskManager` still fully usable so
--      handlers can register last-minute cleanup tasks.
--   3. Engine calls `player.TaskManager:Destroy()`, which releases
--      everything (including those last-minute additions) and marks the
--      manager unusable.
--   4. Engine drops its reference -- subsequent FindById / FindByName
--      return `nil, err`.
--------------------------------------------------------------------------------

-- Player class -------------------------------------------------------------

local Player = {}
Player.__index = Player

-- Internal: convert a host ModVector3 (lowercase x/y/z) into an engine
-- Vector3 (uppercase X/Y/Z). Defensive against missing fields.
local function _hostVec3ToVector3(v)
    return Vector3.new(v.x or 0, v.y or 0, v.z or 0)
end

-- Internal: build a host-shaped vector from x, y, z numbers. Prefers
-- `tm.vector3.Create(x, y, z)` when the host exposes it; falls back to a
-- plain table with .x/.y/.z fields, which works for any host call that
-- just reads the components.
local function _makeHostVec3(x, y, z)
    if tm and tm.vector3 and tm.vector3.Create then
        local ok, v = pcall(tm.vector3.Create, x, y, z)
        if ok and v then
            return v
        end
    end
    return { x = x, y = y, z = z }
end

-- Internal constructor. Wraps a host ModPlayer. Called only by the
-- Players service.
local function _newPlayer(modPlayer)
    return setmetatable({
        _className = "Player",
        _modPlayer = modPlayer,
        Id = modPlayer.playerId,
        Name = modPlayer.playerName,
        TaskManager = TaskManager.new(),
    }, Player)
end

-- Teleport the player. Accepts either `Teleport(Vector3)` or
-- `Teleport(x, y, z)`. Mutator -- returns self for chaining.
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

-- Kick the player. The reason string is logged for audit -- the host
-- call `tm.players.Kick(playerId)` does not accept a reason and does not
-- show one to the kicked player. Treat the reason as audit-log only.
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

-- Kill the player. The host respawn rules then apply.
function Player:Kill()
    if tm and tm.players and tm.players.KillPlayer then
        pcall(tm.players.KillPlayer, self.Id)
    end
    return self
end

-- Force the player out of any seat they currently occupy. No-op if they
-- are not seated.
function Player:Eject()
    if tm and tm.players and tm.players.ForceExitSeat then
        pcall(tm.players.ForceExitSeat, self.Id)
    end
    return self
end

-- Move the player to a numbered team. Team semantics are host-defined;
-- the engine does not validate the id.
function Player:SetTeam(teamId)
    _expectType("Player", "SetTeam", "teamId", "number", teamId)
    if tm and tm.players and tm.players.SetPlayerTeam then
        pcall(tm.players.SetPlayerTeam, self.Id, teamId)
    end
    return self
end

function Player:SetInvincible(enabled)
    _expectType("Player", "SetInvincible", "enabled", "boolean", enabled)
    if tm and tm.players and tm.players.SetPlayerIsInvincible then
        pcall(tm.players.SetPlayerIsInvincible, self.Id, enabled)
    end
    return self
end

function Player:SetJetpackEnabled(enabled)
    _expectType("Player", "SetJetpackEnabled", "enabled", "boolean", enabled)
    if tm and tm.players and tm.players.SetJetpackEnabled then
        pcall(tm.players.SetJetpackEnabled, self.Id, enabled)
    end
    return self
end

-- Current world position as an engine Vector3. Returns Vector3(0,0,0) if
-- the host call fails or the player has no transform (e.g. between
-- death and respawn). Mods that need to distinguish those cases should
-- pair this with `IsInSeat()` or a respawn-aware signal.
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

-- True iff the player is currently in a seat. Returns false on host
-- error rather than throwing, because callers usually treat this as a
-- "is the player driving?" check that should default to "no".
function Player:IsInSeat()
    if tm and tm.players and tm.players.IsPlayerInSeat then
        local ok, seated = pcall(tm.players.IsPlayerInSeat, self.Id)
        if ok then
            return seated and true or false
        end
    end
    return false
end

-- Spawn a prefab at the player's position plus an optional offset.
-- Documented to return the spawned object (NOT self) -- the spawned
-- object is almost always what the caller wants next. Stubbed in this
-- build pending the ObjectSpawner service in a later slice.
function Player:SpawnObjectNearby(prefab, offset)
    error(_runtimeError("Player", "SpawnObjectNearby",
        "ObjectSpawner is not yet implemented in this engine build. " ..
        "Spawn directly via engine:GetService(\"ObjectSpawner\") once it ships."), 0)
end

-- Players service ----------------------------------------------------------

local Players = {}
Players.__index = Players

-- Internal: normalize a player display name for fuzzy lookup. Lowercased
-- with spaces, underscores, and hyphens stripped, so "Player 123",
-- "player_123", and "PLAYER-123" all compare equal. Used by FindByName.
local function _normalizeName(name)
    return (name:lower():gsub("[%s_%-]", ""))
end

-- Construct the Players service. Subscribes to the host lifecycle events
-- and pre-populates from the current session. Idempotent against missing
-- host APIs (everything is pcall'd so the service can boot under a
-- partial test harness).
local function _newPlayers()
    local self = setmetatable({
        _className = "Players",
        _byId = {},                    -- [playerId] = Player
        PlayerJoinedServer = _newSignal("Players.PlayerJoinedServer"),
        PlayerLeftServer = _newSignal("Players.PlayerLeftServer"),
    }, Players)

    -- Internal: wrap a host ModPlayer if not already wrapped, return the
    -- engine Player. Returns nil if the input is unusable (no playerId).
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

    -- Pre-populate from anyone already in the session. pcall because
    -- CurrentPlayers may not exist on every host build (older firmware,
    -- test harness, sandbox lacking the API).
    if tm and tm.players and tm.players.CurrentPlayers then
        local ok, list = pcall(tm.players.CurrentPlayers)
        if ok and type(list) == "table" then
            for _, modPlayer in ipairs(list) do
                self:_track(modPlayer)
            end
        end
    end

    -- Bridge host events to engine signals. Bridge functions are stored
    -- on self in case a future Destroy wants to unregister them; in
    -- practice the Players service has the same lifetime as the engine.
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
                -- Dispatch first so handlers can still touch the player
                -- AND its TaskManager (per DESIGN section 6 lifecycle).
                self.PlayerLeftServer:Fire(p)
                -- Then tear down the per-player TaskManager. This also
                -- releases any tasks the handlers above just added.
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

-- Snapshot of all currently-tracked players as an array. Ordering is
-- insertion order in the underlying hash but NOT guaranteed stable
-- across host versions; sort the result if you depend on order.
function Players:GetPlayers()
    local arr = {}
    for _, p in pairs(self._byId) do
        arr[#arr + 1] = p
    end
    return arr
end

-- Look up by numeric host id. Returns the Player or `nil, err`.
function Players:FindById(id)
    _expectType("Players", "FindById", "id", "number", id)
    local p = self._byId[id]
    if p then
        return p
    end
    return nil, _runtimeError("Players", "FindById",
        "no player with id " .. tostring(id) .. ".")
end

-- Look up by display name. An exact case-sensitive match wins first;
-- otherwise we fuzzy-match (case-insensitive, ignoring spaces / underscores
-- / hyphens) and require a UNIQUE match. Ambiguity returns `nil, err`
-- listing the candidates so the caller can disambiguate.
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

-- Stateful iterator suitable for `for player in Players:Iterate() do`.
-- Takes a snapshot of the current player set at call time so concurrent
-- joins/leaves during iteration do not skip or revisit entries.
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

-- Register the service. Construction is lazy; the eager call inside
-- `LFTME.New()` (see section 8) forces it so the host-event bridges
-- install before any mod code runs.
LFTME._registerService("Players", function(_engine)
    return _newPlayers()
end)

--------------------------------------------------------------------------------
-- 8. Chat service
--
-- Two distinct host UI surfaces, mapped to two distinct methods:
--
--   * Chat:SendMessageTo(player, message)
--       Panel-line message. Backed by `tm.playerUI.SendChatMessage`.
--       The host call is broadcast-attributed-to-sender; the engine
--       hides that quirk by using a configured sender name (default
--       "Server", change with Chat:SetSenderName).
--
--   * Chat:BroadcastToAll(header, body, duration?)
--       Centre-screen intrusive popup. Backed by
--       `tm.playerUI.ShowIntrusiveMessageForAllPlayers`. Builder form
--       (`Chat:BroadcastToAll():Header(...):Body(...):Duration(...)`)
--       is also supported.
--
-- Inbound chat fires `Chat.MessageReceived(player, message)` -- on the
-- service, NOT on the player, because the player is an actor in the
-- event rather than its owner. If the message arrives from a sender
-- that does not match any tracked player (system messages, NPCs, a
-- player who left in the same frame), the first arg is `nil`.
--
-- Echo suppression. The host's `OnChatMessage` fires for messages the
-- engine itself just sent via `SendChatMessage`. Without filtering this
-- creates a feedback loop where every outbound message bounces back as
-- an inbound MessageReceived. The engine keeps a small TTL-keyed map of
-- recently-sent (senderName, message) pairs. Inbound messages whose key
-- lives in the map within the TTL window are silently dropped.
--
-- Builder commit timing. The chain-form builder defers the host call
-- to `UpdateService:After(0)` so every setter in the same statement
-- runs before the popup is shown. This means a typical chain like
-- `:Header(...):Body(...):Duration(...)` fires the popup ONCE on the
-- next tick with the final values, not three times with progressively
-- filled fields.
--------------------------------------------------------------------------------

local ECHO_SUPPRESSION_TTL = 0.25
local DEFAULT_INTRUSIVE_DURATION = 5
local DEFAULT_SENDER_NAME = "Server"

-- IntrusiveBuilder ---------------------------------------------------------

local IntrusiveBuilder = {}
IntrusiveBuilder.__index = IntrusiveBuilder

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

-- Internal: arm the deferred host call on first setter. Idempotent --
-- later setters in the same chain see `_armed == true` and just mutate
-- the buffer. The actual `_fire` runs from a `UpdateService:After(0)`
-- callback so it observes the chain's final state.
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

function IntrusiveBuilder:Header(text)
    _expectType("IntrusiveBuilder", "Header", "text", "string", text)
    self._header = text
    _armIntrusive(self)
    return self
end

function IntrusiveBuilder:Body(text)
    _expectType("IntrusiveBuilder", "Body", "text", "string", text)
    self._body = text
    _armIntrusive(self)
    return self
end

function IntrusiveBuilder:Duration(seconds)
    _expectType("IntrusiveBuilder", "Duration", "seconds", "number", seconds)
    self._duration = seconds
    _armIntrusive(self)
    return self
end

-- Internal: actually invoke the host call with the buffered state. Only
-- runs once per builder; further setter calls after fire are no-ops on
-- the screen even though they update the buffer (the host has no API
-- to mutate an already-displayed popup).
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

local function _newChat(playersService)
    local self = setmetatable({
        _className = "Chat",
        _senderName = DEFAULT_SENDER_NAME,
        _echoMap = {},                 -- [senderName..NUL..message] = expiry clock
        _playersService = playersService,
        MessageReceived = _newSignal("Chat.MessageReceived"),
    }, Chat)

    -- Bridge host OnChatMessage to engine MessageReceived.
    if tm and tm.playerUI and tm.playerUI.OnChatMessage and tm.playerUI.OnChatMessage.add then
        self._onChatBridge = function(senderName, message, _color)
            -- Echo suppression check first -- if we just sent this and
            -- the host is bouncing it back at us, drop it silently.
            local now = (_updateServiceInstance and _updateServiceInstance._clock) or 0
            local key = tostring(senderName) .. "\0" .. tostring(message)
            local expiry = self._echoMap[key]
            if expiry and expiry > now then
                self._echoMap[key] = nil
                return
            end
            -- Look up the sender as a Player. FindByName returns
            -- (nil, err) when no match; we silently coerce to nil player
            -- because system messages and NPC chat lines are legitimate.
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

-- Change the sender name shown on engine-emitted chat lines. Default is
-- "Server". Mutator -- returns self for chaining with other Chat setters.
function Chat:SetSenderName(name)
    _expectType("Chat", "SetSenderName", "name", "string", name)
    self._senderName = name
    return self
end

-- Send a panel-line message visible to all players, attributed to the
-- engine's configured sender name. The `player` argument exists for
-- future per-player chat APIs and audit symmetry with BroadcastToAll;
-- the current host call is broadcast-only.
--
-- Returns self so calls can chain. Echo suppression is registered for
-- the next ECHO_SUPPRESSION_TTL seconds so the inbound bridge can drop
-- the host's self-echo on the next frame.
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

-- Show a centre-screen intrusive popup to every player. Two forms:
--
--   * Positional: `Chat:BroadcastToAll("Warning", "Restart in 10s", 10)`
--     Fires immediately. Duration is optional (defaults to 5 seconds).
--
--   * Builder: `Chat:BroadcastToAll():Header(...):Body(...):Duration(...)`
--     Returns an IntrusiveBuilder; each setter accumulates state and
--     the host call fires once on the next tick with the final values.
function Chat:BroadcastToAll(header, body, duration)
    -- Zero-arg form returns a builder.
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
    -- Chat depends on Players for inbound bridge name lookup. We pass
    -- the Players service in explicitly rather than reach into the
    -- engine on each callback. The eager GetService in LFTME.New
    -- already ensures Players exists by the time anyone reaches here.
    local playersService = engine:GetService("Players")
    return _newChat(playersService)
end)

--------------------------------------------------------------------------------
-- 9. ObjectSpawner service (Phase 1 skeleton)
--
-- This section ships the minimum surface needed by the rest of the
-- engine and the DESIGN.md examples:
--
--   * SpawnObject(prefab) -> SpawnedObject
--   * SpawnedObject:Position(x,y,z|Vector3)  -- mutator
--   * SpawnedObject:Scale(x,y,z|Vector3|uniform)  -- mutator
--   * SpawnedObject:Rotation(x,y,z|Vector3)  -- mutator, Euler degrees
--   * SpawnedObject:Destroy()  -- terminal
--   * ResolvePrefab(name) -> canonical, err
--
-- DEFERRED to later slices:
--   * SpawnGroup + pattern library (Grid/Circle/Ring/Cube/Sphere/...)
--   * Fuzzy prefab name resolution (exact -> canonical -> alias ->
--     normalised -> fuzzy -> suggest). Current `ResolvePrefab` is a
--     pass-through that requires the canonical host name.
--   * Alias registry / Patterns.Register
--   * Engine spawn registry for bulk Destroy
--
-- The skeleton uses `tm.physics.SpawnObject(position, name)` for the
-- host call and `ModGameObject:GetTransform()` to reach the
-- `SetPositionWorld` / `SetEulerAnglesWorld` / `SetScale` setters on
-- the underlying transform. Each host call is pcall'd because the
-- host can fail in benign ways (object despawned between two chained
-- calls, name not in the host catalogue).
--------------------------------------------------------------------------------

-- SpawnedObject ------------------------------------------------------------

local SpawnedObject = {}
SpawnedObject.__index = SpawnedObject

-- Internal constructor. Users get SpawnedObjects from
-- ObjectSpawner:SpawnObject -- never directly.
local function _newSpawnedObject(modGameObject, prefab)
    return setmetatable({
        _className = "SpawnedObject",
        _modGameObject = modGameObject,
        _prefab = prefab,
        _isDestroyed = false,
    }, SpawnedObject)
end

-- Internal: unwrap (Vector3) | (x, y, z) | (uniform-number) into three
-- numbers. `allowUniform=true` is used by Scale (a lone number maps to
-- {n, n, n}); Position and Rotation reject the uniform form because
-- "Position(5)" almost always means "I forgot the other two args".
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

-- Internal: guard against use-after-destroy. Throws with the runtime
-- failure template so the message points at the user's call site.
local function _ensureLive(self, method)
    if self._isDestroyed then
        error(_runtimeError("SpawnedObject", method,
            "this object has been destroyed."), 0)
    end
end

-- Internal: pull the ModTransform out of the wrapped game object and
-- pass it to `fn`. All transform mutators go through here so the
-- "host call may fail benignly" pcall'ing lives in one place.
local function _withTransform(self, fn)
    if not self._modGameObject or not self._modGameObject.GetTransform then
        return
    end
    local ok, transform = pcall(self._modGameObject.GetTransform, self._modGameObject)
    if ok and transform then
        pcall(fn, transform)
    end
end

-- Set world position. Mutator -- returns self.
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

-- Set scale. Accepts a uniform number (e.g. `Scale(2)` for 2x in all
-- axes), three numbers, or a Vector3. Mutator -- returns self.
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

-- Set Euler rotation in DEGREES. Mutator -- returns self. The host
-- `SetEulerAnglesWorld` is documented to take degrees.
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

-- Despawn the object. Idempotent -- a second call is a no-op rather
-- than an error, because cleanup-on-cleanup ordering can legitimately
-- destroy the same object twice (e.g. TaskManager registering both the
-- object and a function that destroys it).
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

local function _newObjectSpawner()
    return setmetatable({
        _className = "ObjectSpawner",
        _aliases = {},     -- reserved for the future alias registry
    }, ObjectSpawner)
end

-- Phase 1 stub. The full DESIGN.md resolver chain (exact enum value
-- -> exact canonical name -> registered alias -> normalised match
-- -> ambiguity check -> fuzzy fallback -> friendly "did you mean")
-- replaces this in a later slice. For now we accept only strings and
-- return them unchanged; non-string values produce the runtime-failure
-- template message that DESIGN.md uses.
function ObjectSpawner:ResolvePrefab(name)
    if type(name) == "string" then
        return name
    end
    return nil, _runtimeError("ObjectSpawner", "ResolvePrefab",
        "could not resolve prefab " .. _describeValue(name) .. ". " ..
        "Pass the canonical host name as a string (e.g. \"PFB_Metal_Crate\").")
end

-- Spawn one prefab and return a SpawnedObject with chainable mutators.
-- Defaults to position (0, 0, 0); the caller is expected to chain
-- `:Position(...)` if they want it elsewhere.
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

-- Phase 1 stub. SpawnGroup + the chainable pattern library land in a
-- later slice. We document the contract here so the call site error
-- points the user at SpawnObject as a workaround.
function ObjectSpawner:SpawnGroup(_prefab)
    error(_runtimeError("ObjectSpawner", "SpawnGroup",
        "SpawnGroup and the patterns library are not yet implemented in this engine build. " ..
        "Spawn objects individually via SpawnObject for now."), 0)
end

-- Register the service. Lazy construction is fine -- ObjectSpawner has
-- no host-event bridges to install, so the first GetService call is the
-- right moment for it to exist.
LFTME._registerService("ObjectSpawner", function(_engine)
    return _newObjectSpawner()
end)

--------------------------------------------------------------------------------
-- 10. Engine singleton
--
-- LFTME.New() constructs the engine the first time it is called and errors
-- on any subsequent call. LFTME.Get() returns the existing instance or
-- `nil, err` if New() has not yet been called.
--
-- The instance exposes:
--   engine:GetService(name)   -- look up a registered service singleton
--   engine.Settings           -- mutable settings table (see below)
--
-- Services are not implemented in this foundation pass; the registry is
-- exposed so subsequent passes can `LFTME._registerService(name, factory)`
-- without modifying this section.
--------------------------------------------------------------------------------

local Engine = {}
Engine.__index = Engine

-- The one-and-only instance, populated by New() and read by Get().
local _engineInstance = nil

-- Settings table. Mutable by user code. Defaults documented in DESIGN.md.
local function _defaultSettings()
    return {
        WarnOnRawPrefabStrings = false,
    }
end

-- Look up a service by name. Returns the same singleton table for repeated
-- calls. Throws a runtime-failure if no service with that name has been
-- registered. Services are an enumerated public surface, not arbitrary.
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
    -- Pass the engine to the factory so services can hold a backreference
    -- without reaching into the global. Factories are responsible for
    -- creating their own signals and any private state.
    local svc = factory(self)
    self._services[name] = svc
    return svc
end

-- Construct the engine singleton. Errors on the second call.
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
    -- Eagerly construct UpdateService so its `_G.update` hook installs
    -- before any user code runs. Every other scheduling primitive
    -- (task.spawn, task.wait, task.delay, signal yields) depends on it.
    self:GetService("UpdateService")
    -- Eagerly construct Players so the host event bridges install
    -- before any mod code runs and we do not miss a fast OnPlayerJoined.
    self:GetService("Players")
    return self
end

-- Return the existing engine instance, or `nil, err` if New() has not run.
-- Never throws; safe to call from library code that doesn't own the
-- engine lifecycle.
function LFTME.Get()
    if _engineInstance == nil then
        return nil, _runtimeError("LFTME", "Get", "engine has not been constructed. Call LFTME.New() first.")
    end
    return _engineInstance
end

--------------------------------------------------------------------------------
-- 11. Module surface
--
-- Datatypes are reached both via the namespace (`LFTME.Vector3.new(...)`)
-- and, by user preference, via a one-line local alias at the top of the
-- mod (`local Vector3 = LFTME.Vector3`).
--
-- Signal is exposed for advanced users who want to build their own signals
-- inside mod-side abstractions; it is not required for normal use.
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
-- Two and only two globals are created: the full namespace name and the
-- short alias. Everything else is reached through the engine instance or
-- through the namespace.
--------------------------------------------------------------------------------

rawset(_G, "LuluFluffysTrailmakersModEngine", LFTME)
rawset(_G, "LFTME", LFTME)

return LFTME
