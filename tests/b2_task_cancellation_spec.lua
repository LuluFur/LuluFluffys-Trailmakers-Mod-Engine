--------------------------------------------------------------------------------
-- B2 Spec: Task cancellation with mid-tick race protection
--
-- Requirement: A task cancelled before its scheduled deadline must never
-- see its body run. The fix adds defence-in-depth checks at both the outer
-- loop and the resume/carry-over branches of UpdateService._pump.
--
-- Break-observe-restore: The test is designed to exercise the carry-over
-- branch: a task that waits (creating a resume entry for the next tick)
-- is cancelled before that next tick, so its continuation should not resume.
--
-- Note: With LuaJIT running the raw engine (no game/stubs), task.wait()
-- is difficult to test without the full coroutine suspension machinery.
-- This spec tests the core scenarios: pre-deadline cancellation (outer check),
-- and scheduled-but-not-yet-run cancellation (would be caught by outer check
-- before resume). The midtick race (callback A cancels B's resume entry
-- before B is processed in the same _pump call) is the trickiest to set up
-- without actual coroutine yield machinery.
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

    it("UpdateService.After returns cancellable handle", function()
        setup()
        local handle = UpdateService:After(1.0, function() end)
        assert_type(handle, "table", "After must return a handle")
        assert_type(handle.Cancel, "function", "Handle must have Cancel")
        assert_type(handle.Cancelled, "boolean", "Handle must have Cancelled")
        handle:Cancel()
    end)

    it("task cancelled before deadline never runs (outer loop check)", function()
        setup()
        _G.__test_b2_delayed = nil
        local handle = UpdateService:After(1.0, function()
            _G.__test_b2_delayed = true
        end)
        handle:Cancel()
        assert_equal(handle.Cancelled, true, "Cancelled must be set")
        -- Pump several times past the deadline
        for i = 1, 100 do
            UpdateService:_pump(0.016)
        end
        assert_equal(_G.__test_b2_delayed, nil, "cancelled task must not run even after deadline")
    end)

    it("cancelled flag is readable", function()
        setup()
        local handle = UpdateService:After(0.1, function() end)
        assert_equal(handle.Cancelled, false, "initially Cancelled must be false")
        handle:Cancel()
        assert_equal(handle.Cancelled, true, "after Cancel, Cancelled must be true")
    end)

    it("re-cancelling a handle is safe (idempotent)", function()
        setup()
        local handle = UpdateService:After(0.1, function() end)
        handle:Cancel()
        -- Re-cancel should not raise
        local ok = pcall(function() handle:Cancel() end)
        assert_true(ok, "re-cancelling a handle must be safe")
    end)

    it("Every callback entries in queue are skipped when handle is cancelled", function()
        setup()
        -- Every entries are scheduled and can be cancelled. Verify that
        -- after cancellation, the Every callback doesn't fire.
        _G.__test_b2_every_count = 0
        local handle = UpdateService:Every(0.016, function()
            _G.__test_b2_every_count = _G.__test_b2_every_count + 1
        end)

        -- Cancel before the first firing
        handle:Cancel()

        -- Pump past the firing time
        UpdateService:_pump(0.032)

        -- The Every callback should not have fired
        assert_equal(_G.__test_b2_every_count, 0, "cancelled Every must not fire")
    end)

    it("Every fires until cancelled, then stops", function()
        setup()
        _G.__test_b2_every_fires = 0
        local handle = UpdateService:Every(0.01, function()
            _G.__test_b2_every_fires = _G.__test_b2_every_fires + 1
        end)

        -- First pump: t=0 to t=0.01, Every fires once
        UpdateService:_pump(0.01)
        assert_equal(_G.__test_b2_every_fires, 1, "Every fires on schedule")

        -- Cancel before the next firing
        handle:Cancel()

        -- Second pump: t=0.01 to t=0.02, Every should NOT fire
        UpdateService:_pump(0.01)
        assert_equal(_G.__test_b2_every_fires, 1, "cancelled Every must not fire again")
    end)

    it("outer loop catches Cancelled entries", function()
        setup()
        -- Verify the outer loop check: schedule multiple entries,
        -- cancel one, verify it doesn't run
        _G.__test_b2_outer_1 = nil
        _G.__test_b2_outer_2 = nil
        _G.__test_b2_outer_3 = nil

        local h1 = UpdateService:After(0.01, function() _G.__test_b2_outer_1 = true end)
        local h2 = UpdateService:After(0.01, function() _G.__test_b2_outer_2 = true end)
        local h3 = UpdateService:After(0.01, function() _G.__test_b2_outer_3 = true end)

        -- Cancel the middle one
        h2:Cancel()

        UpdateService:_pump(0.016)

        assert_equal(_G.__test_b2_outer_1, true, "h1 must run")
        assert_equal(_G.__test_b2_outer_2, nil, "h2 must not run (cancelled)")
        assert_equal(_G.__test_b2_outer_3, true, "h3 must run")
    end)

    it("immediate cancellation before any pump", function()
        setup()
        _G.__test_b2_immediate = nil
        local handle = UpdateService:After(0.01, function()
            _G.__test_b2_immediate = true
        end)
        -- Cancel before any pump
        handle:Cancel()
        UpdateService:_pump(0.016)
        assert_equal(_G.__test_b2_immediate, nil, "task cancelled before pump must not run")
    end)
end)
