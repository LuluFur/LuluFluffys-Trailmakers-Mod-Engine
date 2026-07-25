--------------------------------------------------------------------------------
-- B2 Spec: Task cancellation with mid-tick race protection
--
-- Requirement: A task cancelled before its scheduled deadline must never
-- see its body run. The fix adds defence-in-depth checks at two sites:
--
--   1. Resume branch: re-check Cancelled before resuming a coroutine
--   2. Carry-over loop: skip entries with Cancelled=true when promoting
--      entries added during the current tick to the next tick's queue
--
-- Break-observe-restore: Site 1 (resume branch) is unreachable dead code;
-- the outer loop check makes it impossible for any entry to reach resume
-- with Cancelled already true. Site 2 (carry-over) IS testable: schedule
-- a task from within a callback, cancel it in that same tick, then observe
-- that it does not survive to the next tick's queue.
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

    it("carry-over entries: scheduled task cancelled mid-tick does not survive", function()
        setup()
        -- This is Site 2 of the fix: the carry-over loop must check Cancelled.
        --
        -- Pattern: Schedule a task from INSIDE a callback running in the
        -- current tick, cancel it in that same tick. The inner task becomes
        -- a carry-over entry (added to the queue AFTER the main loop started).
        -- On a pre-fix engine, the cancelled carry-over entry would be kept.
        -- On the fixed engine, it is dropped.
        --
        -- Observe via queue occupancy: after the pump completes, #_queue
        -- should be 0 on the fixed engine, 1 on the buggy one.

        local hInner
        -- Clear the queue before testing
        UpdateService._queue = {}

        -- Outer callback: runs at t=0.01, spawns inner callback and cancels it
        UpdateService:After(0.01, function()
            hInner = UpdateService:After(5.0, function()
                _G.__test_b2_inner_ran = true
            end)
            hInner:Cancel()
        end)

        -- Pump to t=0.05 (past the outer callback's deadline)
        UpdateService:_pump(0.05)

        -- The inner task was scheduled for t=5.0 (far future), but cancelled
        -- in the same tick. On the fixed engine, it is dropped from the queue.
        -- On the pre-fix engine, it remains as a carry-over entry.
        local queue_count = #UpdateService._queue
        assert_equal(queue_count, 0, "cancelled carry-over entry must be dropped from queue")
        assert_equal(_G.__test_b2_inner_ran, nil, "inner task must not run")
    end)

    it("Every callback entries in queue are skipped when handle is cancelled", function()
        setup()
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
