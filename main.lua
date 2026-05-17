--------------------------------------------------------------------------------
-- LuluFluffys Trailmakers Mod Engine -- example main.lua
--
-- Bootstraps the engine and exercises every service so a single in-game
-- run validates the full surface area. The engine file lives at
-- <mod>/data_static/engine.lua and loads via tm.os.DoFile("engine")
-- (DoFile auto-appends .lua and rejects dots in the argument).
--------------------------------------------------------------------------------

local LFTME = tm.os.DoFile("engine")
local engine = LFTME.New()

tm.os.Log("[mod] LFTME engine constructed: " .. tostring(engine))

local function safe(label, fn)
    local ok, err = pcall(fn)
    if ok then
        tm.os.Log("[mod] " .. label .. " OK")
    else
        tm.os.Log("[mod] " .. label .. " FAIL: " .. tostring(err))
    end
end

safe("Logger", function()
    engine:GetService("Logger"):Info("smoke test: Logger reachable")
end)

safe("ModStorage", function()
    local ModStorage = engine:GetService("ModStorage")
    local roundtrip = ModStorage.JSON.Encode({hello = "world", n = 42, arr = {1,2,3}})
    local decoded = ModStorage.JSON.Decode(roundtrip)
    assert(decoded and decoded.hello == "world", "JSON roundtrip failed")
    assert(type(ModStorage.ReadStatic) == "function", "ReadStatic missing")
end)

safe("World", function()
    local World = engine:GetService("World")
    tm.os.Log("[mod] World: map=" .. World:GetMapName() ..
        " timeOfDay=" .. tostring(World:GetTimeOfDay()) ..
        " gravity=" .. tostring(World:GetGravity()) ..
        " timeScale=" .. tostring(World:GetTimeScale()))
    assert(type(World.SetTimeOfDayCycleDuration) == "function",
        "SetTimeOfDayCycleDuration missing")
end)

safe("UI", function()
    assert(engine:GetService("UI")._className == "UI")
end)

safe("Audio", function()
    assert(engine:GetService("Audio")._className == "Audio")
end)

safe("Camera", function()
    assert(engine:GetService("Camera")._className == "Camera")
end)

safe("ObjectSpawner", function()
    local Spawner = engine:GetService("ObjectSpawner")
    local catalog = Spawner:GetCatalog()
    tm.os.Log("[mod] ObjectSpawner: catalog size=" .. #catalog)
end)

safe("UpdateService.SetTargetDelta", function()
    engine:GetService("UpdateService"):SetTargetDelta(0.25)
end)

safe("Players + Chat", function()
    assert(engine:GetService("Players")._className == "Players")
    assert(engine:GetService("Chat")._className == "Chat")
end)

safe("Color3 presets", function()
    assert(LFTME.Color3.Red and LFTME.Color3.White and LFTME.Color3.Gray,
        "Color3 presets missing")
end)

safe("UpdateService handles cancellable", function()
    local Update = engine:GetService("UpdateService")
    local h1 = Update:After(0.1, function() end)
    local h2 = Update:Every(0.1, function() end)
    assert(h1 and h1.Cancel and h2 and h2.Cancel,
        "After/Every should return TaskHandle with :Cancel")
    h1:Cancel(); h2:Cancel()
end)

safe("B1 deprecated SendMessageTo alias", function()
    -- The old API is kept as a one-shot-warning shim that drops the
    -- player arg and forwards to SendMessage. Verify both names work
    -- and that the new primary name exists.
    local Chat = engine:GetService("Chat")
    assert(type(Chat.SendMessage) == "function", "Chat:SendMessage primary missing")
    assert(type(Chat.SendMessageTo) == "function", "Chat:SendMessageTo deprecated alias missing")
end)

safe("B2 cancelled task does not resume", function()
    -- A handle cancelled before its scheduled deadline must never see
    -- its body run. We cannot block in a smoke test, so we just check
    -- the handle is marked cancelled and that re-cancelling is safe.
    _G.__test_b2 = nil
    local h = task.spawn(function()
        task.wait(1)
        _G.__test_b2 = true
    end)
    assert(h and h.Cancel, "task.spawn must return a TaskHandle")
    h:Cancel()
    assert(h.Cancelled == true, "Cancel must flip the flag")
    h:Cancel()
end)

safe("B3 JSON numeric keys are coerced not dropped", function()
    -- Previously {[2]="a"} encoded as "{}" with silent data loss.
    -- It must now stringify the key to "2".
    local ModStorage = engine:GetService("ModStorage")
    local out = ModStorage.JSON.Encode({[2] = "a"})
    assert(out == [[{"2":"a"}]],
        'expected {"2":"a"} got ' .. tostring(out))
    local ok = pcall(ModStorage.JSON.Encode, {[true] = "x"})
    assert(ok == false, "boolean key must raise an error")
end)

safe("B4 echo map uses counter shape", function()
    -- Each send bumps a counter so N sends suppress exactly N inbound
    -- echoes. Verify the new {count,expiry} shape rather than the old
    -- flat expiry value.
    local Chat = engine:GetService("Chat")
    Chat:SendMessage("[smoke] echo-test")
    Chat:SendMessage("[smoke] echo-test")
    local senderName = Chat._senderName or "Server"
    local key = senderName .. "\0" .. "[smoke] echo-test"
    local entry = Chat._echoMap[key]
    assert(type(entry) == "table" and entry.count == 2,
        "expected echo entry with count=2 after two sends")
    -- Clean the entry so it does not eat a real player message later.
    Chat._echoMap[key] = nil
end)

safe("B5 mutator returns self and stays chainable", function()
    -- _hostCallWarn must not break chaining. Even if the host call
    -- failed (and a Warn was logged), the method still returns self.
    local World = engine:GetService("World")
    local r = World:SetGravity(World:GetGravity())
    assert(r == World, "World:SetGravity must return self for chaining")
    local ok = pcall(function() World:SetTimeScale(1) end)
    assert(ok, "mutator must not propagate host errors as exceptions")
end)

tm.os.Log("[mod] smoke test complete")
