--------------------------------------------------------------------------------
-- LuluFluffy's Trailmakers Mod Engine -- example main.lua
--
-- This is the file Trailmakers auto-loads. It bootstraps the engine and
-- then runs the modder's code.
--
-- IMPORTANT: `tm.os.DoFile("engine")` (DoFile auto-appends .lua and forbids dots in the
--     argument) resolves paths relative to the
-- mod's `data_static/` folder. The engine lives at:
--
--     <mod>/data_static/engine.lua
--
-- KNOWN-UNKNOWNS to verify on first in-game run:
--   * That `tm.os.DoFile` returns the module table (the `return LFTME` at
--     the bottom of engine.lua). If it returns nil or errors, fall back to
--     inlining engine.lua directly above this code as a prelude.
--   * That `data_static/` siblings are reachable by bare filename (not
--     `"data_static/engine.lua"`). The wiki says relative-to-data_static,
--     but this should be confirmed.
--   * That the two globals (`LuluFluffysTrailmakersModEngine`, `LFTME`)
--     actually appear on `_G` and persist for the rest of the session.
--
-- If DoFile turns out not to work, replace lines 24-25 with the full
-- contents of `data_static/engine.lua` pasted in place (Architecture A:
-- inline prelude).
--------------------------------------------------------------------------------

local LFTME = tm.os.DoFile("engine")
local engine = LFTME.New()

--------------------------------------------------------------------------------
-- Modder code goes below this line.
--------------------------------------------------------------------------------

-- Example: log that the engine booted successfully.
tm.os.Log("[mod] LFTME engine constructed: " .. tostring(engine))
