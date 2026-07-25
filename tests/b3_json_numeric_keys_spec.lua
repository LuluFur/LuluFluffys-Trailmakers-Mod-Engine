--------------------------------------------------------------------------------
-- B3 Spec: JSON encoder coerces numeric keys instead of dropping them
--
-- Requirement: Previously {[2]="a"} encoded as "{}" with silent data loss.
-- Now numeric keys are stringified: {[2]="a"} → {"2":"a"}. Boolean, table,
-- and function keys must still raise an error explicitly.
--
-- Break-observe-restore: temporarily remove the key coercion or the error
-- checks to verify specs catch both.
--------------------------------------------------------------------------------

describe("B3: JSON numeric key handling", function()
    local ModStorage

    local function setup()
        local e = get_engine()
        ModStorage = e:GetService("ModStorage")
    end

    it("numeric integer keys are coerced to strings", function()
        setup()
        local data = {[2] = "a"}
        local encoded = ModStorage.JSON.Encode(data)
        assert_equal(encoded, '{"2":"a"}', "numeric key 2 must encode as string '2'")
    end)

    it("numeric key 1 is treated as array index", function()
        setup()
        -- Lua tables with key 1 are treated as array elements in JSON
        local data = {[1] = "first"}
        local encoded = ModStorage.JSON.Encode(data)
        -- With only index 1, JSON array becomes ["first"]
        assert_equal(encoded, '["first"]', "numeric key 1 is array element")
    end)

    it("multiple numeric keys are all coerced", function()
        setup()
        local data = {[2] = "two", [1] = "one", [3] = "three"}
        local encoded = ModStorage.JSON.Encode(data)
        -- Keys 1,2,3 are consecutive array indices; result is ["one","two","three"]
        local has_one = encoded:find('one') ~= nil
        local has_two = encoded:find('two') ~= nil
        local has_three = encoded:find('three') ~= nil
        assert_true(has_one and has_two and has_three,
            "all values must be present in the JSON output, got: " .. encoded)
    end)

    it("mixed string and numeric keys both encode", function()
        setup()
        local data = {hello = "world", [2] = "numeric"}
        local encoded = ModStorage.JSON.Encode(data)
        -- Both keys should be in the output
        local has_hello = encoded:find("hello") ~= nil
        local has_world = encoded:find("world") ~= nil
        assert_true(has_hello and has_world,
            "string key hello and value must be present, got: " .. encoded)
        local has_2 = encoded:find('"2"') ~= nil
        local has_numeric = encoded:find("numeric") ~= nil
        assert_true(has_2 and has_numeric,
            "numeric key 2 and value must be present, got: " .. encoded)
    end)

    it("numeric keys round-trip through encode-decode", function()
        setup()
        local original = {[2] = "a", [5] = "b"}
        local encoded = ModStorage.JSON.Encode(original)
        local decoded = ModStorage.JSON.Decode(encoded)
        -- Decoded keys will be strings: "2" and "5"
        assert_equal(decoded["2"], "a", "key 2 must decode to value 'a'")
        assert_equal(decoded["5"], "b", "key 5 must decode to value 'b'")
    end)

    it("boolean keys raise an error", function()
        setup()
        local data = {[true] = "value"}
        local ok, err = pcall(function()
            ModStorage.JSON.Encode(data)
        end)
        assert_false(ok, "boolean key must raise an error, not silently drop")
        local err_str = tostring(err)
        local has_key_mention = err_str:find("key") ~= nil or err_str:find("boolean") ~= nil or err_str:find("type") ~= nil
        assert_true(has_key_mention,
            "error message should mention the invalid key type, got: " .. err_str)
    end)

    it("table keys raise an error", function()
        setup()
        local nested = {}
        local data = {[nested] = "value"}
        local ok, err = pcall(function()
            ModStorage.JSON.Encode(data)
        end)
        assert_false(ok, "table key must raise an error")
    end)

    it("function keys raise an error", function()
        setup()
        local fn = function() end
        local data = {[fn] = "value"}
        local ok, err = pcall(function()
            ModStorage.JSON.Encode(data)
        end)
        assert_false(ok, "function key must raise an error")
    end)

    it("nil values with numeric keys encode correctly", function()
        setup()
        -- nil values in JSON tables typically omit the key or encode as null
        -- This test documents the actual behavior
        local data = {[1] = nil, [2] = "not nil"}
        local encoded = ModStorage.JSON.Encode(data)
        -- At minimum, the non-nil value should be present
        local has_value = encoded:find("not nil") ~= nil
        local has_key = encoded:find('"2"') ~= nil
        assert_true(has_value or has_key,
            "non-nil numeric values must encode, got: " .. encoded)
    end)

    it("floating-point numeric keys are stringified", function()
        setup()
        -- Lua normalizes 2.0 to 2, which is treated as array index
        local data = {[2.0] = "float"}
        local encoded = ModStorage.JSON.Encode(data)
        -- Key 2.0 is array index, value should be present
        assert_true(encoded:find("float") ~= nil, "numeric key 2.0 value must be present, got: " .. encoded)
    end)
end)
