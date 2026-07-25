#!/usr/bin/env luajit
--------------------------------------------------------------------------------
-- LuaJIT test runner for LFTME specs
--
-- Usage: luajit tests/run.lua
--
-- Runs all *_spec.lua files in the tests/ directory, collects results,
-- and exits with status 0 if all pass, non-zero if any fail.
--------------------------------------------------------------------------------

local function dirname(path)
    return path:match("^(.*)/") or "."
end

local function basename(path)
    return path:match("([^/]*)$")
end

-- Track test results and engine state
local results = {
    passed = 0,
    failed = 0,
    tests = {},
}
local shared_engine = nil
local LFTME_lib = nil

-- Simple assertion helper
local function assert_equal(actual, expected, message)
    if actual ~= expected then
        error(string.format(
            "%s\n  expected: %s\n  actual: %s",
            message or "assertion failed",
            tostring(expected),
            tostring(actual)
        ))
    end
end

local function assert_true(value, message)
    assert_equal(value, true, message or "expected true")
end

local function assert_false(value, message)
    assert_equal(value, false, message or "expected false")
end

local function assert_type(value, expected_type, message)
    local actual_type = type(value)
    if actual_type ~= expected_type then
        error(string.format(
            "%s\n  expected type: %s\n  actual type: %s",
            message or "type assertion failed",
            expected_type,
            actual_type
        ))
    end
end

-- Initialize the engine once
local function load_engine()
    if LFTME_lib then
        return LFTME_lib
    end

    local engine_path = "data_static/engine.lua"
    local engine_chunk, engine_err = loadfile(engine_path)
    if not engine_chunk then
        error("Failed to load engine from " .. engine_path .. ": " .. engine_err)
    end

    -- Create a minimal environment for the engine
    local engine_env = {
        pairs = pairs,
        ipairs = ipairs,
        next = next,
        type = type,
        tostring = tostring,
        tonumber = tonumber,
        error = error,
        assert = assert,
        table = table,
        string = string,
        math = math,
        os = os,
        rawget = rawget,
        rawset = rawset,
        setmetatable = setmetatable,
        getmetatable = getmetatable,
        select = select,
        unpack = unpack,
        pcall = pcall,
        xpcall = xpcall,
        debug = debug,
        coroutine = coroutine,
        _G = {},  -- Will be set below
    }
    engine_env._G = engine_env

    setfenv(engine_chunk, engine_env)
    local ok, lftme_or_err = pcall(engine_chunk)
    if not ok then
        error("Engine initialization failed: " .. tostring(lftme_or_err))
    end

    LFTME_lib = lftme_or_err
    return LFTME_lib
end

-- Run a single test file
local function run_spec_file(spec_path, spec_name)
    -- Load the spec
    local spec_chunk, load_err = loadfile(spec_path)
    if not spec_chunk then
        return false, "Failed to load: " .. load_err
    end

    -- Ensure engine is loaded
    local LFTME = load_engine()

    -- Create test environment
    local test_env = {
        -- Standard globals
        pairs = pairs,
        ipairs = ipairs,
        next = next,
        type = type,
        tostring = tostring,
        tonumber = tonumber,
        error = error,
        assert = assert,
        table = table,
        string = string,
        math = math,
        os = os,
        rawget = rawget,
        rawset = rawset,
        setmetatable = setmetatable,
        getmetatable = getmetatable,
        loadfile = loadfile,
        dofile = dofile,
        pcall = pcall,
        xpcall = xpcall,
        select = select,
        debug = debug,

        -- Engine and test framework
        LFTME = LFTME,
        get_engine = function()
            if not shared_engine then
                shared_engine = LFTME.New()
            end
            return shared_engine
        end,

        -- Test framework functions
        describe = function(name, fn) fn() end,
        it = function(name, fn)
            local ok, err = pcall(fn)
            if ok then
                results.passed = results.passed + 1
            else
                results.failed = results.failed + 1
                table.insert(results.tests, {
                    spec = spec_name,
                    test = name,
                    error = tostring(err),
                })
            end
        end,

        -- Assertion helpers
        assert_equal = assert_equal,
        assert_true = assert_true,
        assert_false = assert_false,
        assert_type = assert_type,
    }
    test_env._G = test_env
    test_env.task = LFTME.task  -- Expose task module

    -- Run the spec
    setfenv(spec_chunk, test_env)
    local ok, spec_err = pcall(spec_chunk)

    if not ok then
        return false, "Spec execution failed: " .. tostring(spec_err)
    end

    return true, "OK"
end

-- Find and run all spec files
local function run_all_specs()
    local test_dir = "tests"

    -- Try to find spec files
    local specs = {}
    local popen_ok, popen = pcall(io.popen, "find " .. test_dir .. " -name '*_spec.lua' -type f 2>/dev/null")
    if popen_ok and popen then
        for spec_path in popen:lines() do
            table.insert(specs, spec_path)
        end
        popen:close()
    end

    if #specs == 0 then
        print("No spec files found in " .. test_dir)
        return  -- Not a failure to have no specs (yet)
    end

    table.sort(specs)

    for _, spec_path in ipairs(specs) do
        local spec_name = basename(spec_path):match("^(.*)%.lua$") or basename(spec_path)
        local ok, msg = run_spec_file(spec_path, spec_name)
        if not ok then
            print("ERROR: " .. spec_path .. ": " .. msg)
            results.failed = results.failed + 1
        end
    end
end

-- Main
run_all_specs()

-- Print summary
print("\n" .. string.rep("=", 70))
print(string.format("Tests: %d passed, %d failed", results.passed, results.failed))

if #results.tests > 0 then
    print("\nFailed tests:")
    for _, test_result in ipairs(results.tests) do
        print(string.format("  %s :: %s", test_result.spec, test_result.test))
        for line in test_result.error:gmatch("[^\n]+") do
            print("    " .. line)
        end
    end
end

print(string.rep("=", 70))

-- Exit with appropriate code
os.exit(results.failed > 0 and 1 or 0)
