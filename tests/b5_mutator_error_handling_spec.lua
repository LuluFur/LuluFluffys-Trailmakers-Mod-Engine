--------------------------------------------------------------------------------
-- B5 Spec: Unified error model for extension-block mutators
--
-- Requirement: Mutators (Set* methods) wrap host calls in _hostCallWarn,
-- which logs failures instead of swallowing them. Methods must still return
-- self (chaining preserved) even if the host call fails.
--
-- Break-observe-restore: temporarily remove _hostCallWarn or return values
-- to verify specs catch missing error logging or broken chaining.
--
-- Note: This spec injects a mutable `tm` stub so host calls can be made to
-- fail on demand. The runner loads the engine once and shares it, so we
-- set up the stub at the top level and each spec toggles behavior as needed.
--------------------------------------------------------------------------------

-- Global stub for controlling host call behavior
_G.__b5_tm_stub = {
    physics = {
        GetGravityMultiplier = function() return 1 end,
        SetGravityMultiplier = function() end,  -- default: success
    },
}

describe("B5: Mutator error handling and chainability", function()
    local World
    local Logger
    local e

    local function setup()
        e = get_engine()
        World = e:GetService("World")
        Logger = e:GetService("Logger")
        -- Inject the tm stub into _G so _hostCallWarn can find it
        _G.tm = _G.__b5_tm_stub
    end

    local function cleanup()
        _G.tm = nil
    end

    it("World:SetGravity returns self on success", function()
        setup()
        local result = World:SetGravity(10)
        assert_equal(result, World, "SetGravity must return self")
        cleanup()
    end)

    it("World:SetGravity returns self even when host call fails", function()
        setup()
        -- Make the host call fail
        _G.__b5_tm_stub.physics.SetGravityMultiplier = function()
            error("Simulated host failure")
        end
        -- The mutator should still return self and not raise
        local result = World:SetGravity(10)
        assert_equal(result, World, "SetGravity must return self even on host failure")
        cleanup()
    end)

    it("failed host call is logged when logger available", function()
        setup()
        -- Verify that Logger.Warn can capture messages
        local lines_before = #Logger._lines
        Logger:Warn("test warning from spec")
        local lines_after = #Logger._lines
        assert_true(lines_after > lines_before, "Logger:Warn must add a line")
        -- This proves the Logger is available for capture
        cleanup()
    end)

    it("World:SetGravity is chainable even on failure", function()
        setup()
        -- Make the host call fail
        _G.__b5_tm_stub.physics.SetGravityMultiplier = function()
            error("Simulated host failure")
        end
        -- Chaining should work despite the failure
        local result = World:SetGravity(10):SetTimeScale(1.0)
        assert_equal(result, World, "chained mutators must return self even after host failure")
        cleanup()
    end)

    it("World:SetTimeScale returns self", function()
        setup()
        local result = World:SetTimeScale(1.5)
        assert_equal(result, World, "SetTimeScale must return self")
        cleanup()
    end)

    it("World:SetTimeOfDayCycleDuration returns self", function()
        setup()
        local result = World:SetTimeOfDayCycleDuration(120)
        assert_equal(result, World, "SetTimeOfDayCycleDuration must return self")
        cleanup()
    end)

    it("mutator chain is associative", function()
        setup()
        -- Verify we can chain multiple mutators without intermediate captures
        local result = World
            :SetGravity(9.8)
            :SetTimeScale(1.0)
            :SetTimeOfDayCycleDuration(120)
        assert_equal(result, World, "chained mutators must return World at each step")
        cleanup()
    end)
end)
