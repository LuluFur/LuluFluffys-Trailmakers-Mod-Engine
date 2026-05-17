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

tm.os.Log("[mod] smoke test complete")
