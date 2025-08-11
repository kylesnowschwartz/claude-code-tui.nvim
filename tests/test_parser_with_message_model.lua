---@brief [[
--- TDD Tests for Parser Integration with Message Model
--- Tests the parser using object-oriented message classes
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

-- Test 1: Parser uses Message.from_json for line parsing
T["parser_uses_message_model"] = function()
    child.lua([[
        local Parser = require("cc-tui.parser.stream")
        local Message = require("cc-tui.models.message")

        -- Mock a JSONL line
        local line = vim.json.encode({
            type = "user",
            sessionId = "test-123",
            cwd = "/test",
            message = {
                role = "user",
                content = "Hello"
            }
        })

        -- Parse using new method
        local msg = Parser.parse_line_with_model(line)

        _G.test_result = {
            exists = msg ~= nil,
            is_message = msg and msg.get_type ~= nil,
            type = msg and msg:get_type(),
            session = msg and msg:get_session_id()
        }
    ]])

    local result = child.lua_get("_G.test_result")
    MiniTest.expect.equality(result.exists, true, "Should parse message")
    MiniTest.expect.equality(result.is_message, true, "Should be Message instance")
    MiniTest.expect.equality(result.type, "user", "Should have correct type")
    MiniTest.expect.equality(result.session, "test-123", "Should extract session")
end

-- Test 2: Build message index with Message model
T["build_index_with_message_model"] = function()
    child.lua([[
        local Parser = require("cc-tui.parser.stream")
        local AssistantMessage = require("cc-tui.models.assistant_message")
        local UserMessage = require("cc-tui.models.user_message")

        -- Create test messages
        local messages = {
            AssistantMessage.new({
                type = "assistant",
                message = {
                    content = {
                        {
                            type = "tool_use",
                            id = "toolu_test",
                            name = "TestTool"
                        }
                    }
                }
            }),
            UserMessage.new({
                type = "user",
                message = {
                    content = {
                        {
                            type = "tool_result",
                            tool_use_id = "toolu_test",
                            content = "Result"
                        }
                    }
                }
            })
        }

        local tool_uses, tool_results = Parser.build_message_index_with_model(messages)

        _G.test_result = {
            has_tool_use = tool_uses["toolu_test"] ~= nil,
            has_tool_result = tool_results["toolu_test"] ~= nil
        }
    ]])

    local result = child.lua_get("_G.test_result")
    MiniTest.expect.equality(result.has_tool_use, true, "Should index tool uses")
    MiniTest.expect.equality(result.has_tool_result, true, "Should index tool results")
end

-- Test 3: Parse lines creates Message instances
T["parse_lines_creates_messages"] = function()
    child.lua([[
        local Parser = require("cc-tui.parser.stream")

        local lines = {
            vim.json.encode({
                type = "user",
                message = { role = "user", content = "Test" }
            }),
            vim.json.encode({
                type = "assistant",
                message = { role = "assistant", content = { { type = "text", text = "Response" } } }
            })
        }

        local messages, errors = Parser.parse_lines_with_model(lines)

        _G.test_result = {
            count = #messages,
            errors = #errors,
            first_type = messages[1] and messages[1]:get_type(),
            second_type = messages[2] and messages[2]:get_type(),
            first_is_user = messages[1] and messages[1]:is_user(),
            second_is_assistant = messages[2] and messages[2]:is_assistant()
        }
    ]])

    local result = child.lua_get("_G.test_result")
    MiniTest.expect.equality(result.count, 2, "Should parse 2 messages")
    MiniTest.expect.equality(result.errors, 0, "Should have no errors")
    MiniTest.expect.equality(result.first_type, "user", "First should be user")
    MiniTest.expect.equality(result.second_type, "assistant", "Second should be assistant")
    MiniTest.expect.equality(result.first_is_user, true, "Should identify user message")
    MiniTest.expect.equality(result.second_is_assistant, true, "Should identify assistant message")
end

-- Test 4: Get text preview uses Message methods
T["text_preview_with_message_model"] = function()
    child.lua([[
        local Parser = require("cc-tui.parser.stream")
        local AssistantMessage = require("cc-tui.models.assistant_message")

        local msg = AssistantMessage.new({
            type = "assistant",
            message = {
                content = {
                    { type = "text", text = "This is a test response that is quite long and should be truncated for preview display" }
                }
            }
        })

        local preview = Parser.get_text_preview_with_model(msg)

        _G.test_result = {
            exists = preview ~= nil,
            length = preview and #preview,
            has_ellipsis = preview and preview:match("%.%.%.$") ~= nil
        }
    ]])

    local result = child.lua_get("_G.test_result")
    MiniTest.expect.equality(result.exists, true, "Should get preview")
    MiniTest.expect.equality(result.length <= 80, true, "Should truncate to 80 chars")
    MiniTest.expect.equality(result.has_ellipsis, true, "Should have ellipsis")
end

-- Test 5: Get tools uses AssistantMessage methods
T["get_tools_with_message_model"] = function()
    child.lua([[
        local Parser = require("cc-tui.parser.stream")
        local AssistantMessage = require("cc-tui.models.assistant_message")

        local msg = AssistantMessage.new({
            type = "assistant",
            message = {
                content = {
                    { type = "tool_use", id = "toolu_1", name = "Read", input = { file_path = "/test.txt" } },
                    { type = "tool_use", id = "toolu_2", name = "Write", input = { file_path = "/out.txt" } }
                }
            }
        })

        local tools = Parser.get_tools_with_model(msg)

        _G.test_result = {
            count = #tools,
            first_name = tools[1] and tools[1].name,
            second_name = tools[2] and tools[2].name
        }
    ]])

    local result = child.lua_get("_G.test_result")
    MiniTest.expect.equality(result.count, 2, "Should get 2 tools")
    MiniTest.expect.equality(result.first_name, "Read", "First tool should be Read")
    MiniTest.expect.equality(result.second_name, "Write", "Second tool should be Write")
end

-- Test 6: Session info extraction with Message model
T["session_info_with_message_model"] = function()
    child.lua([[
        local Parser = require("cc-tui.parser.stream")
        local Message = require("cc-tui.models.message")

        local messages = {
            Message.from_json({
                type = "summary",
                summary = "Test conversation about feature X"
            }),
            Message.from_json({
                type = "user",
                sessionId = "session-456",
                cwd = "/project",
                gitBranch = "main",
                version = "1.0.72"
            })
        }

        local session_info = Parser.get_session_info_with_model(messages)

        _G.test_result = {
            exists = session_info ~= nil,
            summary = session_info and session_info.summary,
            id = session_info and session_info.id,
            cwd = session_info and session_info.cwd
        }
    ]])

    local result = child.lua_get("_G.test_result")
    MiniTest.expect.equality(result.exists, true, "Should get session info")
    MiniTest.expect.equality(result.summary, "Test conversation about feature X", "Should extract summary")
    MiniTest.expect.equality(result.id, "session-456", "Should extract session ID")
    MiniTest.expect.equality(result.cwd, "/project", "Should extract cwd")
end

-- Test 7: Consolidate messages with Message model
T["consolidate_with_message_model"] = function()
    child.lua([[
        local Parser = require("cc-tui.parser.stream")
        local AssistantMessage = require("cc-tui.models.assistant_message")

        -- Create messages with same ID but different content
        local raw_messages = {
            AssistantMessage.new({
                type = "assistant",
                message = {
                    id = "msg_123",
                    content = {
                        { type = "text", text = "Part 1" }
                    }
                }
            }),
            AssistantMessage.new({
                type = "assistant",
                message = {
                    id = "msg_123",
                    content = {
                        { type = "tool_use", id = "toolu_456", name = "Test" }
                    }
                }
            })
        }

        local consolidated = Parser.consolidate_messages_with_model(raw_messages)

        _G.test_result = {
            count = #consolidated,
            has_text = false,
            has_tool = false
        }

        if consolidated[1] then
            local content = consolidated[1]:get_text_content()
            local tools = consolidated[1]:get_tool_uses()
            _G.test_result.has_text = content ~= nil
            _G.test_result.has_tool = #tools > 0
        end
    ]])

    local result = child.lua_get("_G.test_result")
    MiniTest.expect.equality(result.count, 1, "Should consolidate to one message")
    MiniTest.expect.equality(result.has_text, true, "Should have text content")
    MiniTest.expect.equality(result.has_tool, true, "Should have tool content")
end

return T
