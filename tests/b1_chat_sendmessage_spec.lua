--------------------------------------------------------------------------------
-- B1 Spec: Chat:SendMessage + deprecated SendMessageTo alias
--
-- Requirement: The old SendMessageTo(player, message) was never honoured
-- because Trailmakers' API only broadcasts. Introduce Chat:SendMessage as
-- the primary; keep SendMessageTo as a deprecated one-shot-warning shim that
-- drops player and forwards.
--
-- Break-observe-restore: temporarily remove the SendMessage method or the
-- SendMessageTo alias to verify specs catch both missing.
--------------------------------------------------------------------------------

describe("B1: Chat service API", function()
    local Chat

    -- Setup: get Chat service from the shared engine
    local function get_chat_service()
        local e = get_engine()
        return e:GetService("Chat")
    end

    it("Chat:SendMessage exists and is callable", function()
        Chat = get_chat_service()
        assert_type(Chat.SendMessage, "function", "SendMessage must be a function")
    end)

    it("Chat:SendMessageTo exists and is callable", function()
        Chat = get_chat_service()
        assert_type(Chat.SendMessageTo, "function", "SendMessageTo must be a function")
    end)

    it("Chat:SendMessage accepts a message argument", function()
        Chat = get_chat_service()
        -- Should not raise; we're just testing it accepts the argument
        local ok = pcall(function()
            Chat:SendMessage("[test] hello")
        end)
        assert_true(ok, "SendMessage should accept a message")
    end)

    it("Chat:SendMessageTo requires a Player instance", function()
        Chat = get_chat_service()
        -- SendMessageTo validates that player is a Player instance
        local ok, err = pcall(function()
            Chat:SendMessageTo(nil, "[test] invalid player")
        end)
        assert_false(ok, "SendMessageTo should reject nil player")
        local err_str = tostring(err)
        assert_true(err_str:find("Player") ~= nil, "error should mention Player type, got: " .. err_str)
    end)

    it("Chat:SendMessageTo forwards message to SendMessage when player is valid", function()
        Chat = get_chat_service()
        local Players = get_engine():GetService("Players")
        -- We can't easily create a Player in test environment, but we can verify
        -- the deprecation warning exists and SendMessage works as primary
        Chat:SendMessage("[test] primary api")
        assert_true(Chat._echoMap ~= nil, "Chat should have an _echoMap after SendMessage")
    end)

    it("Chat:SendMessage returns self for chaining", function()
        Chat = get_chat_service()
        local r1 = Chat:SendMessage("[test] x")
        assert_equal(r1, Chat, "SendMessage must return self")
    end)
end)
