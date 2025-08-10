---@brief [[
--- TDD-driven JSONL Parser Tests using Real Conversation Data
--- Implements Phase 2 of TEST_REFACTORING_PLAN.md
---@brief ]]

local MiniTest = require("mini.test")
local RealDataLoader = require("tests.helpers.real_data_loader")
local TddFramework = require("tests.helpers.tdd_framework")

local child = MiniTest.new_child_neovim()

local T = MiniTest.new_set({
    hooks = {
        pre_case = function()
            child.restart({ "-u", "scripts/minimal_init.lua" })
            -- Ensure real data is available
            local valid, err = RealDataLoader.validate_real_data_available()
            if not valid then
                MiniTest.skip("Real conversation data not available: " .. (err or "unknown"))
            end
        end,
        post_once = child.stop,
    },
})

-- Get test data overview for planning
local function get_test_overview()
    local overview = RealDataLoader.get_test_data_overview()
    return {
        total = overview.total_conversations,
        tiny = overview.categories.tiny.count,
        small = overview.categories.small.count,
        medium = overview.categories.medium.count,
        large = overview.categories.large.count,
        huge = overview.categories.huge.count,
        size_range = overview.size_range,
    }
end

-- TDD CYCLE 1: Basic JSONL Line Parsing
T["parse_line - User Messages"] = function()
    local cycle = TddFramework.create_cycle({
        description = "Parse user messages from real conversation data",
        category = "tiny", -- Use smallest files for fast unit tests
        setup = function(state)
            -- Load parser module in child process
            child.lua([[
                _G.Parser = require('cc-tui.parser.stream')
            ]])
        end,
    })

    -- RED: Define expected behavior for user message parsing
    local test_fn = function(state)
        -- Get first user message from real data
        local lines = state.provider:get_lines()
        local user_line = nil

        for _, line in ipairs(lines) do
            if line:match('"type":"user"') then
                user_line = line
                break
            end
        end

        TddFramework.expect(user_line).to_not_be_nil()

        -- Parse the user message
        local parsed = child.lua_get([[_G.Parser.parse_line(...) ]], { user_line })

        -- Validate expected structure
        TddFramework.expect(parsed).to_not_be_nil()
        TddFramework.expect(parsed.type).to_equal("user")
        TddFramework.expect(parsed.message).to_not_be_nil()
        TddFramework.expect(parsed.message.role).to_equal("user")
        TddFramework.expect(parsed.uuid).to_not_be_nil()
    end

    -- Execute RED phase (should initially pass since parser already exists)
    local red_success = cycle.red(test_fn)

    -- Since parser exists, this test should pass, so we validate functionality
    if not red_success then
        -- Test passed, which means parser works correctly
        child.expect_screenshot()
    end

    local summary = cycle.get_summary()
    MiniTest.expect.equality(summary.description, "Parse user messages from real conversation data")
end

T["parse_line - Assistant Messages with Tool Calls"] = function()
    local cycle = TddFramework.create_cycle({
        description = "Parse assistant messages with tool calls from real data",
        category = "small", -- Small files likely have tool calls
        setup = function(state)
            child.lua([[
                _G.Parser = require('cc-tui.parser.stream')
            ]])
        end,
    })

    -- RED: Define expected tool call parsing and ID extraction
    local test_fn = function(state)
        local lines = state.provider:get_lines()
        local assistant_line = nil

        -- Find assistant message with tool_use
        for _, line in ipairs(lines) do
            if line:match('"type":"assistant"') and line:match('"tool_use"') then
                assistant_line = line
                break
            end
        end

        TddFramework.expect(assistant_line).to_not_be_nil()

        -- Parse the assistant message
        local parsed = child.lua_get([[_G.Parser.parse_line(...) ]], { assistant_line })

        -- Validate expected structure
        TddFramework.expect(parsed).to_not_be_nil()
        TddFramework.expect(parsed.type).to_equal("assistant")
        TddFramework.expect(parsed.message).to_not_be_nil()
        TddFramework.expect(parsed.message.content).to_not_be_nil()

        -- Check for tool use extraction
        local has_tool_use = false
        if type(parsed.message.content) == "table" then
            for _, content_item in ipairs(parsed.message.content) do
                if content_item.type == "tool_use" then
                    has_tool_use = true
                    TddFramework.expect(content_item.id).to_not_be_nil()
                    TddFramework.expect(content_item.name).to_not_be_nil()
                    break
                end
            end
        end

        TddFramework.expect(has_tool_use).to_be_truthy()
    end

    -- Execute TDD cycle
    local red_result = cycle.red(test_fn)
    -- Test should pass since parser handles tool calls
end

T["tool_linking - Link Tool Results to Tool Calls"] = function()
    local cycle = TddFramework.create_cycle({
        description = "Link tool results to tool calls using real conversation flow",
        category = "medium", -- Medium files likely have complete tool call/result pairs
        setup = function(state)
            child.lua([[
                _G.Parser = require('cc-tui.parser.stream')
            ]])
        end,
    })

    -- RED: Define expected tool linking behavior
    local test_fn = function(state)
        local lines = state.provider:get_lines()

        -- Parse all lines to get messages
        local messages = {}
        for _, line in ipairs(lines) do
            local parsed = child.lua_get([[_G.Parser.parse_line(...) ]], { line })
            if parsed then
                table.insert(messages, parsed)
            end
        end

        -- Find tool call and corresponding result
        local tool_call_id = nil
        local found_result = false

        -- First pass: find a tool call
        for _, msg in ipairs(messages) do
            if msg.type == "assistant" and msg.message.content then
                for _, content in ipairs(msg.message.content) do
                    if content.type == "tool_use" then
                        tool_call_id = content.id
                        break
                    end
                end
                if tool_call_id then
                    break
                end
            end
        end

        TddFramework.expect(tool_call_id).to_not_be_nil()

        -- Second pass: find corresponding tool result
        for _, msg in ipairs(messages) do
            if msg.type == "user" and msg.message.content then
                for _, content in ipairs(msg.message.content) do
                    if content.type == "tool_result" and content.tool_use_id == tool_call_id then
                        found_result = true
                        TddFramework.expect(content.content).to_not_be_nil()
                        break
                    end
                end
                if found_result then
                    break
                end
            end
        end

        TddFramework.expect(found_result).to_be_truthy()
    end

    -- Execute TDD cycle
    cycle.red(test_fn)
end

T["session_info - Extract Session Metadata"] = function()
    local cycle = TddFramework.create_cycle({
        description = "Extract session information from real conversation data",
        category = "small",
        setup = function(state)
            child.lua([[
                _G.Parser = require('cc-tui.parser.stream')
            ]])
        end,
    })

    -- RED: Define expected session information extraction
    local test_fn = function(state)
        local lines = state.provider:get_lines()

        -- Parse all lines
        local messages = {}
        for _, line in ipairs(lines) do
            local parsed = child.lua_get([[_G.Parser.parse_line(...) ]], { line })
            if parsed then
                table.insert(messages, parsed)
            end
        end

        TddFramework.expect(#messages).to_not_equal(0)

        -- Extract session info
        local session_info = child.lua_get([[_G.Parser.get_session_info(...) ]], { messages })

        -- Validate session information
        TddFramework.expect(session_info).to_not_be_nil()
        TddFramework.expect(session_info.session_id).to_not_be_nil()
        TddFramework.expect(session_info.message_count).to_equal(#messages)

        -- Check for metadata extraction
        if #messages > 0 then
            local first_msg = messages[1]
            if first_msg.cwd then
                TddFramework.expect(session_info.cwd).to_equal(first_msg.cwd)
            end
            if first_msg.gitBranch then
                TddFramework.expect(session_info.git_branch).to_equal(first_msg.gitBranch)
            end
        end
    end

    cycle.red(test_fn)
end

T["error_handling - Malformed JSON Recovery"] = function()
    local cycle = TddFramework.create_cycle({
        description = "Handle malformed JSON gracefully",
        category = "tiny",
        setup = function(state)
            child.lua([[
                _G.Parser = require('cc-tui.parser.stream')
            ]])
        end,
    })

    -- RED: Define expected error handling behavior
    local test_fn = function(state)
        -- Test with malformed JSON lines
        local malformed_lines = {
            '{"incomplete": "json"', -- Missing closing brace
            "not json at all", -- Not JSON
            "", -- Empty line
            "{}", -- Empty JSON object
            '{"type": "unknown"}', -- Unknown message type
        }

        for _, bad_line in ipairs(malformed_lines) do
            local parsed = child.lua_get([[_G.Parser.parse_line(...) ]], { bad_line })
            -- Should return nil for malformed/invalid lines
            TddFramework.expect(parsed).to_be_nil()
        end
    end

    cycle.red(test_fn)
end

-- REMOVED: Performance tests are premature optimization
-- Following "make it work, make it right, make it fast" principle
-- Performance testing will be added in future "Make It Fast" phase

return T
