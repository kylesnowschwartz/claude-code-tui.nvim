---@brief [[
--- TDD Tests for JSONL Message Object Model
--- Tests object-oriented message classes with field accessors
---@brief ]]

local helpers = require("tests.helpers")
local child = helpers.new_child_neovim()
local MiniTest = require("mini.test")

local T = MiniTest.new_set({
    hooks = {
        pre_case = function()
            child.restart({ "-u", "scripts/minimal_init.lua" })
            child.lua([[
                -- Load the plugin
                require("cc-tui").setup({ debug = true })
            ]])
        end,
        post_once = child.stop,
    },
})

-- Test 1: Message base class exists
T["message_base_class"] = function()
    child.lua([[
        local Message = require("cc-tui.models.message")
        _G.test_result = Message ~= nil
    ]])

    local exists = child.lua_get("_G.test_result")
    MiniTest.expect.equality(exists, true, "Message class should exist")
end

-- Test 2: Create message from JSONL data
T["create_message_from_json"] = function()
    child.lua([[
        local Message = require("cc-tui.models.message")

        local json_data = {
            type = "user",
            sessionId = "test-session-123",
            cwd = "/test/path",
            gitBranch = "main",
            version = "1.0.0",
            timestamp = "2025-01-01T12:00:00Z",
            uuid = "msg-uuid-123",
            message = {
                role = "user",
                content = "Test message"
            }
        }

        local msg = Message.from_json(json_data)

        _G.test_result = {
            exists = msg ~= nil,
            type = msg and msg:get_type(),
            session_id = msg and msg:get_session_id(),
            cwd = msg and msg:get_cwd()
        }
    ]])

    local result = child.lua_get("_G.test_result")
    MiniTest.expect.equality(result.exists, true, "Should create message")
    MiniTest.expect.equality(result.type, "user", "Should have correct type")
    MiniTest.expect.equality(result.session_id, "test-session-123", "Should extract sessionId")
    MiniTest.expect.equality(result.cwd, "/test/path", "Should extract cwd")
end

-- Test 3: UserMessage class with content accessors
T["user_message_content"] = function()
    child.lua([[
        local UserMessage = require("cc-tui.models.user_message")

        -- Test string content
        local msg1 = UserMessage.new({
            message = {
                role = "user",
                content = "Simple text"
            }
        })

        -- Test array content (tool result)
        local msg2 = UserMessage.new({
            message = {
                role = "user",
                content = {
                    {
                        type = "tool_result",
                        tool_use_id = "toolu_123",
                        content = "Tool output"
                    }
                }
            },
            toolUseResult = true
        })

        _G.test_result = {
            text = msg1:get_text_content(),
            is_tool_result = msg2:is_tool_result(),
            tool_results = msg2:get_tool_results()
        }
    ]])

    local result = child.lua_get("_G.test_result")
    MiniTest.expect.equality(result.text, "Simple text", "Should get text content")
    MiniTest.expect.equality(result.is_tool_result, true, "Should identify tool result")
    MiniTest.expect.equality(#result.tool_results, 1, "Should get tool results")
end

-- Test 4: AssistantMessage with tool uses
T["assistant_message_tools"] = function()
    child.lua([[
        local AssistantMessage = require("cc-tui.models.assistant_message")

        local msg = AssistantMessage.new({
            message = {
                role = "assistant",
                model = "claude-3-opus",
                content = {
                    {
                        type = "text",
                        text = "Let me help"
                    },
                    {
                        type = "tool_use",
                        id = "toolu_456",
                        name = "Read",
                        input = { file_path = "/test.txt" }
                    }
                }
            }
        })

        _G.test_result = {
            model = msg:get_model(),
            text = msg:get_text_content(),
            tool_uses = msg:get_tool_uses(),
            has_tools = msg:has_tool_uses()
        }
    ]])

    local result = child.lua_get("_G.test_result")
    MiniTest.expect.equality(result.model, "claude-3-opus", "Should get model")
    MiniTest.expect.equality(result.text, "Let me help", "Should get text")
    MiniTest.expect.equality(result.has_tools, true, "Should detect tool uses")
    MiniTest.expect.equality(#result.tool_uses, 1, "Should get tool uses")
end

-- Test 5: Message metadata extraction
T["message_metadata"] = function()
    child.lua([[
        local Message = require("cc-tui.models.message")

        local msg = Message.from_json({
            parentUuid = "parent-123",
            sessionId = "session-456",
            cwd = "/project",
            gitBranch = "feature/test",
            version = "1.0.72",
            timestamp = "2025-01-01T12:00:00Z",
            uuid = "msg-789",
            type = "user"
        })

        local metadata = msg:get_metadata()

        _G.test_result = {
            parent_uuid = metadata.parent_uuid,
            session_id = metadata.session_id,
            cwd = metadata.cwd,
            git_branch = metadata.git_branch,
            version = metadata.version,
            timestamp = metadata.timestamp,
            uuid = metadata.uuid
        }
    ]])

    local result = child.lua_get("_G.test_result")
    MiniTest.expect.equality(result.parent_uuid, "parent-123", "Should get parent UUID")
    MiniTest.expect.equality(result.session_id, "session-456", "Should get session ID")
    MiniTest.expect.equality(result.cwd, "/project", "Should get cwd")
    MiniTest.expect.equality(result.git_branch, "feature/test", "Should get git branch")
    MiniTest.expect.equality(result.version, "1.0.72", "Should get version")
end

-- Test 6: Summary message handling
T["summary_message"] = function()
    child.lua([[
        local Message = require("cc-tui.models.message")

        local msg = Message.from_json({
            type = "summary",
            summary = "Test conversation summary",
            leafUuid = "leaf-123"
        })

        _G.test_result = {
            type = msg:get_type(),
            is_summary = msg:is_summary(),
            summary = msg:get_summary()
        }
    ]])

    local result = child.lua_get("_G.test_result")
    MiniTest.expect.equality(result.type, "summary", "Should identify as summary")
    MiniTest.expect.equality(result.is_summary, true, "Should have is_summary method")
    MiniTest.expect.equality(result.summary, "Test conversation summary", "Should get summary text")
end

-- Test 7: System message handling
T["system_message"] = function()
    child.lua([[
        local Message = require("cc-tui.models.message")

        local msg = Message.from_json({
            type = "system",
            content = "Running PostToolUse:Write...",
            level = "info",
            toolUseID = "toolu_xyz"
        })

        _G.test_result = {
            type = msg:get_type(),
            is_system = msg:is_system(),
            content = msg:get_content(),
            level = msg:get_level()
        }
    ]])

    local result = child.lua_get("_G.test_result")
    MiniTest.expect.equality(result.type, "system", "Should identify as system")
    MiniTest.expect.equality(result.is_system, true, "Should have is_system method")
    MiniTest.expect.equality(result.content, "Running PostToolUse:Write...", "Should get content")
    MiniTest.expect.equality(result.level, "info", "Should get level")
end

-- Test 8: Tool linking capabilities
T["tool_linking"] = function()
    child.lua([[
        local AssistantMessage = require("cc-tui.models.assistant_message")
        local UserMessage = require("cc-tui.models.user_message")

        local assistant_msg = AssistantMessage.new({
            message = {
                content = {
                    {
                        type = "tool_use",
                        id = "toolu_link_test",
                        name = "TestTool"
                    }
                }
            }
        })

        local user_msg = UserMessage.new({
            message = {
                content = {
                    {
                        type = "tool_result",
                        tool_use_id = "toolu_link_test",
                        content = "Result"
                    }
                }
            }
        })

        local tool_uses = assistant_msg:get_tool_uses()
        local tool_results = user_msg:get_tool_results()

        _G.test_result = {
            tool_id = tool_uses[1] and tool_uses[1].id,
            result_id = tool_results[1] and tool_results[1].tool_use_id,
            ids_match = tool_uses[1] and tool_results[1] and
                       tool_uses[1].id == tool_results[1].tool_use_id
        }
    ]])

    local result = child.lua_get("_G.test_result")
    MiniTest.expect.equality(result.tool_id, "toolu_link_test", "Should have tool ID")
    MiniTest.expect.equality(result.result_id, "toolu_link_test", "Should have matching result ID")
    MiniTest.expect.equality(result.ids_match, true, "IDs should match for linking")
end

return T
