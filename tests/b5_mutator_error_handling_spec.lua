--------------------------------------------------------------------------------
-- B5 Spec: Unified error model for extension-block mutators
--
-- Requirement: Mutators (Set* methods) wrap host calls in _hostCallWarn,
-- which logs failures instead of swallowing them. Methods must still return
-- self (chaining preserved) even if the host call fails.
--
-- Break-observe-restore: A mutable tm stub is injected before engine loads,
-- so host functions close over a __b5_host_config flag. Tests toggle this
-- flag to make host calls throw, then verify: (1) mutator returns self,
-- (2) warning is logged. Pre-fix engine logs no warnings.
--------------------------------------------------------------------------------

describe("B5: Mutator error handling and chainability", function()
    local World
    local Logger
    local e

    local function setup()
        e = get_engine()
        World = e:GetService("World")
        Logger = e:GetService("Logger")
    end

    local function cleanup()
        _G.__b5_host_config.should_throw = false
    end

    it("World:SetGravity returns self on success", function()
        setup()
        _G.__b5_host_config.should_throw = false
        local result = World:SetGravity(10)
        assert_equal(result, World, "SetGravity must return self")
        cleanup()
    end)

    it("World:SetGravity returns self even when host call fails", function()
        setup()
        _G.__b5_host_config.should_throw = true
        local result = World:SetGravity(10)
        assert_equal(result, World, "SetGravity must return self even on host failure")
        cleanup()
    end)

    it("failed host call logs a warning", function()
        setup()
        -- Intercept Logger:Warn calls to count warnings logged
        local warns = {}
        local original_warn = Logger.Warn
        Logger.Warn = function(self, msg, ...)
            warns[#warns + 1] = tostring(msg)
            return original_warn(self, msg, ...)
        end

        -- Trigger a host call failure
        _G.__b5_host_config.should_throw = true
        World:SetGravity(5)

        -- Restore original Warn
        Logger.Warn = original_warn

        -- Verify a warning was logged mentioning the failed method
        assert_true(#warns > 0, "failed host call must trigger a warning")
        local warn_msg = warns[1]
        local has_method = warn_msg:find("SetGravity") ~= nil
        local has_host = warn_msg:find("host") ~= nil
        assert_true(
            has_method or has_host,
            "warning must mention SetGravity or host failure, got: " .. warn_msg
        )
        cleanup()
    end)

    it("no warning logged when host call succeeds", function()
        setup()
        -- Intercept Logger:Warn calls
        local warns = {}
        local original_warn = Logger.Warn
        Logger.Warn = function(self, msg, ...)
            warns[#warns + 1] = tostring(msg)
            return original_warn(self, msg, ...)
        end

        -- Trigger a successful host call
        _G.__b5_host_config.should_throw = false
        World:SetGravity(10)

        -- Restore original Warn
        Logger.Warn = original_warn

        -- No warnings should have been logged
        assert_equal(#warns, 0, "successful host call must not log warnings")
        cleanup()
    end)

    it("World:SetTimeScale returns self", function()
        setup()
        _G.__b5_host_config.should_throw = false
        local result = World:SetTimeScale(1.5)
        assert_equal(result, World, "SetTimeScale must return self")
        cleanup()
    end)

    it("World:SetTimeOfDayCycleDuration returns self", function()
        setup()
        _G.__b5_host_config.should_throw = false
        local result = World:SetTimeOfDayCycleDuration(120)
        assert_equal(result, World, "SetTimeOfDayCycleDuration must return self")
        cleanup()
    end)

    it("mutator chain is associative", function()
        setup()
        _G.__b5_host_config.should_throw = false
        local result = World
            :SetGravity(9.8)
            :SetTimeScale(1.0)
            :SetTimeOfDayCycleDuration(120)
        assert_equal(result, World, "chained mutators must return World at each step")
        cleanup()
    end)

    it("chaining works even when host calls fail", function()
        setup()
        _G.__b5_host_config.should_throw = true
        local result = World
            :SetGravity(10)
            :SetTimeScale(1.0)
        assert_equal(result, World, "chaining must work even with host failures")
        cleanup()
    end)
end)
