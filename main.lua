--------------------------------------------------------------------------------
-- LuluFluffys Trailmakers Mod Engine -- example main.lua
--
-- Bootstraps the engine and then exercises every service so a single
-- in-game run validates the full surface area. The engine file lives at
-- <mod>/data_static/engine.lua and loads via tm.os.DoFile("engine")
-- (DoFile auto-appends .lua and rejects dots in the argument).
--------------------------------------------------------------------------------

local LFTME = tm.os.DoFile("engine")
local engine = LFTME.New()

tm.os.Log("[mod] LFTME engine constructed: " .. tostring(engine))

-- Smoke-test the new services -- look up each one and log a non-mutating
-- read where possible. Any error here gets a traceback in the mod log.
local function safe(label, fn)
    local ok, err = pcall(fn)
    if ok then
        tm.os.Log("[mod] " .. label .. " OK")
    else
        tm.os.Log("[mod] " .. label .. " FAIL: " .. tostring(err))
    end
end

safe("Logger", function()
    local Logger = engine:GetService("Logger")
    Logger:Info("smoke test: Logger reachable")
end)

safe("ModStorage", function()
    local ModStorage = engine:GetService("ModStorage")
    local roundtrip = ModStorage.JSON.Encode({hello = "world", n = 42, arr = {1,2,3}})
    local decoded = ModStorage.JSON.Decode(roundtrip)
    assert(decoded and decoded.hello == "world", "JSON roundtrip failed")
end)

safe("World", function()
    local World = engine:GetService("World")
    tm.os.Log("[mod] World: map=" .. World:GetMapName() ..
        " timeOfDay=" .. tostring(World:GetTimeOfDay()) ..
        " gravity=" .. tostring(World:GetGravity()) ..
        " timeScale=" .. tostring(World:GetTimeScale()))
end)

safe("UI", function()
    local UI = engine:GetService("UI")
    assert(UI._className == "UI")
end)

safe("Audio", function()
    local Audio = engine:GetService("Audio")
    assert(Audio._className == "Audio")
end)

safe("ObjectSpawner", function()
    local Spawner = engine:GetService("ObjectSpawner")
    local catalog = Spawner:GetCatalog()
    tm.os.Log("[mod] ObjectSpawner: catalog size=" .. #catalog)
end)

safe("UpdateService.SetTargetDelta", function()
    local UpdateService = engine:GetService("UpdateService")
    UpdateService:SetTargetDelta(0.25)
end)

safe("Players + Chat", function()
    local Players = engine:GetService("Players")
    local Chat = engine:GetService("Chat")
    assert(Players._className == "Players")
    assert(Chat._className == "Chat")
end)

tm.os.Log("[mod] smoke test complete")
