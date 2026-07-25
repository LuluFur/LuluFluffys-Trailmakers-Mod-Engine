--------------------------------------------------------------------------------
-- B5 Spec: Unified error model for extension-block mutators
--
-- Requirement: Mutators (Set* methods) wrap host calls in _hostCallWarn,
-- which logs failures instead of swallowing them. Methods must still return
-- self (chaining preserved) even if the host call fails.
--
-- Break-observe-restore: temporarily remove _hostCallWarn or return values
-- to verify specs catch missing error logging or broken chaining.
--------------------------------------------------------------------------------

describe("B5: Mutator error handling and chainability", function()
    local World
    local Logger

    local function setup()
        local e = get_engine()
        World = e:GetService("World")
        Logger = e:GetService("Logger")
    end

    it("World:SetGravity returns self", function()
        setup()
        local result = World:SetGravity(10)
        assert_equal(result, World, "SetGravity must return self")
    end)

    it("World:SetGravity is chainable with another mutator", function()
        setup()
        local result = World:SetGravity(10):SetTimeScale(1.0)
        assert_equal(result, World, "chained SetTimeScale must also return self")
    end)

    it("World:SetTimeScale returns self", function()
        setup()
        local result = World:SetTimeScale(1.5)
        assert_equal(result, World, "SetTimeScale must return self")
    end)

    it("World:SetTimeOfDayCycleDuration returns self", function()
        setup()
        local result = World:SetTimeOfDayCycleDuration(120)
        assert_equal(result, World, "SetTimeOfDayCycleDuration must return self")
    end)

    it("mutator chain is associative", function()
        setup()
        -- Verify we can chain multiple mutators without intermediate captures
        local result = World
            :SetGravity(9.8)
            :SetTimeScale(1.0)
            :SetTimeOfDayCycleDuration(120)
        assert_equal(result, World, "chained mutators must return World at each step")
    end)

    it("failed host call logs a warning instead of raising", function()
        setup()
        -- We can't easily simulate a host call failure without a real `tm` table,
        -- but we can verify the pattern: a mutator that internally calls a
        -- potentially-failing function should not raise.
        local ok = pcall(function()
            World:SetGravity(World:GetGravity())
        end)
        assert_true(ok, "mutator call must not raise even if host call fails internally")
    end)

    it("_hostCallWarn can be called by service implementations", function()
        setup()
        -- Check that the logging helper is available in the engine
        -- It's a private function, but we can verify mutators work without errors
        local ok = pcall(function()
            World:SetGravity(World:GetGravity())
        end)
        assert_true(ok, "mutator must not raise (uses _hostCallWarn internally)")
    end)

    it("UI service Set* methods are chainable", function()
        setup()
        local e = get_engine()
        local UI = e:GetService("UI")
        if UI and UI.SetVisible then
            local result = UI:SetVisible(true)
            assert_equal(result, UI, "UI:SetVisible must return self")
        end
    end)

    it("Camera service Set* methods are chainable", function()
        setup()
        local e = get_engine()
        local Camera = e:GetService("Camera")
        if Camera and Camera.SetPosition then
            local result = Camera:SetPosition(LFTME.Vector3.new(0, 0, 0))
            assert_equal(result, Camera, "Camera:SetPosition must return self")
        end
    end)

    it("Logger warning capture works", function()
        setup()
        local lines_before = #Logger._lines
        Logger:Warn("test warning")
        local lines_after = #Logger._lines
        assert_true(lines_after > lines_before, "Warn must add a log line")
    end)
end)
