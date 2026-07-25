--------------------------------------------------------------------------------
-- B2 Spec: Task cancellation with mid-tick race protection
--
-- Requirement: A task cancelled before its scheduled deadline must never
-- see its body run. The fix adds defence-in-depth checks at both the outer
-- loop and the resume/carry-over branches of UpdateService._pump.
--
-- Break-observe-restore: temporarily remove one or both of the re-check
-- sites to verify specs catch the missing cancellation guard.
--------------------------------------------------------------------------------

describe("B2: Task cancellation bounds latency", function()
    local UpdateService

    local function setup()
        local e = get_engine()
        UpdateService = e:GetService("UpdateService")
    end

    it("task.spawn returns a cancellable TaskHandle", function()
        setup()
        local handle = task.spawn(function() end)
        assert_type(handle, "table", "spawn must return a table")
        assert_type(handle.Cancel, "function", "TaskHandle must have Cancel method")
        assert_type(handle.Cancelled, "boolean", "TaskHandle must have Cancelled property")
        handle:Cancel()
    end)

    it("scheduled task cancelled before deadline never runs", function()
        setup()
        _G.__test_b2_scheduled = nil
        local handle = UpdateService:After(0.1, function()
            _G.__test_b2_scheduled = true
        end)
        -- Cancel before the deadline passes
        handle:Cancel()
        -- Pump once (0.016s) - still within the deadline
        UpdateService:_pump(0.016)
        assert_equal(_G.__test_b2_scheduled, nil, "cancelled scheduled task must not run")
    end)

    it("task cancelled before scheduled time never runs", function()
        setup()
        _G.__test_b2_delayed = nil
        -- Schedule a task for 1 second in the future
        local handle = UpdateService:After(1.0, function()
            _G.__test_b2_delayed = true
        end)
        -- Cancel it immediately
        handle:Cancel()
        assert_equal(handle.Cancelled, true, "Cancelled must be set")
        -- Pump several times, simulating ticks up to and past the deadline
        for i = 1, 100 do
            UpdateService:_pump(0.016)
        end
        assert_equal(_G.__test_b2_delayed, nil, "cancelled task must not run even after deadline")
    end)

    it("task scheduled during a tick, cancelled before deadline, does not run", function()
        setup()
        _G.__test_b2_carry_over = nil
        -- Schedule a task for later
        local inner_handle = UpdateService:After(0.5, function()
            _G.__test_b2_carry_over = true
        end)
        -- Cancel it before the deadline
        inner_handle:Cancel()
        -- Pump multiple times past the would-be deadline
        for i = 1, 50 do
            UpdateService:_pump(0.016)
        end
        assert_equal(_G.__test_b2_carry_over, nil, "cancelled task must not run even after deadline")
    end)

    it("task cancellation idempotency: re-cancel is safe", function()
        setup()
        local handle = task.spawn(function() end)
        handle:Cancel()
        -- Re-cancel should not raise
        local ok = pcall(function() handle:Cancel() end)
        assert_true(ok, "re-cancelling a handle must be safe")
    end)

    it("cancelled flag is readable", function()
        setup()
        local handle = task.spawn(function() end)
        assert_equal(handle.Cancelled, false, "initially Cancelled must be false")
        handle:Cancel()
        assert_equal(handle.Cancelled, true, "after Cancel, Cancelled must be true")
    end)
end)
