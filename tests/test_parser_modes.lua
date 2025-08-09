local Helpers = dofile("tests/helpers.lua")

-- Tests to validate parser works in both streaming and batch modes with identical results

local child = Helpers.new_child_neovim()

local T = MiniTest.new_set({
    hooks = {
        -- This will be executed before every (even nested) case
        pre_case = function()
            -- Restart child process with custom 'init.lua' script
            child.restart({ "-u", "scripts/minimal_init.lua" })
        end,
        -- This will be executed one after all tests from this set are finished
        post_once = child.stop,
    },
})

-- Tests for parser dual-mode compatibility
T["Parser Modes"] = MiniTest.new_set()

T["Parser Modes"]["parse_line handles single line correctly"] = function()
    child.lua([[
        local Parser = require('cc-tui.parser.stream')

        local line = '{"type":"system","subtype":"init","session_id":"test-123","model":"claude-3-5-sonnet"}'
        local msg, err = Parser.parse_line(line)

        _G.has_message = msg ~= nil
        _G.has_error = err ~= nil
        _G.message_type = msg and msg.type or nil
        _G.session_id = msg and msg.session_id or nil
    ]])

    Helpers.expect.global(child, "_G.has_message", true)
    Helpers.expect.global(child, "_G.has_error", false)
    Helpers.expect.global(child, "_G.message_type", "system")
    Helpers.expect.global(child, "_G.session_id", "test-123")
end

T["Parser Modes"]["parse_lines handles batch correctly"] = function()
    child.lua([[
        local Parser = require('cc-tui.parser.stream')

        local lines = {
            '{"type":"system","subtype":"init","session_id":"test-123","model":"claude-3-5-sonnet"}',
            '{"type":"assistant","message":{"id":"msg1","role":"assistant","content":[{"type":"text","text":"Test"}]}}',
            '{"type":"result","subtype":"success","total_cost_usd":0.01}'
        }

        local messages, errors = Parser.parse_lines(lines)

        _G.message_count = #messages
        _G.error_count = #errors
        _G.first_type = messages[1] and messages[1].type or nil
        _G.last_type = messages[#messages] and messages[#messages].type or nil
    ]])

    Helpers.expect.global(child, "_G.message_count", 3)
    Helpers.expect.global(child, "_G.error_count", 0)
    Helpers.expect.global(child, "_G.first_type", "system")
    Helpers.expect.global(child, "_G.last_type", "result")
end

T["Parser Modes"]["both modes produce identical results for same input"] = function()
    child.lua([[
        local Parser = require('cc-tui.parser.stream')

        local test_lines = {
            '{"type":"system","subtype":"init","session_id":"test-123"}',
            '{"type":"assistant","message":{"id":"msg1","role":"assistant","content":[{"type":"text","text":"Hello"}]}}',
            '{"type":"result","subtype":"success","total_cost_usd":0.01}'
        }

        -- Method 1: Batch parsing
        local batch_messages, batch_errors = Parser.parse_lines(test_lines)

        -- Method 2: Line-by-line parsing (simulating streaming)
        local line_messages = {}
        local line_errors = {}

        for i, line in ipairs(test_lines) do
            local msg, err = Parser.parse_line(line)
            if msg then
                table.insert(line_messages, msg)
            elseif err then
                table.insert(line_errors, string.format("Line %d: %s", i, err))
            end
        end

        -- Apply same consolidation as batch method
        local consolidated_line_messages = Parser.consolidate_messages(line_messages)

        -- Compare results
        _G.batch_count = #batch_messages
        _G.line_count = #consolidated_line_messages
        _G.batch_error_count = #batch_errors
        _G.line_error_count = #line_errors

        -- Deep comparison of first message
        local batch_first = batch_messages[1]
        local line_first = consolidated_line_messages[1]

        _G.types_match = batch_first.type == line_first.type
        _G.session_ids_match = batch_first.session_id == line_first.session_id
    ]])

    Helpers.expect.global(child, "_G.batch_count", 3)
    Helpers.expect.global(child, "_G.line_count", 3)
    Helpers.expect.global(child, "_G.batch_error_count", 0)
    Helpers.expect.global(child, "_G.line_error_count", 0)
    Helpers.expect.global(child, "_G.types_match", true)
    Helpers.expect.global(child, "_G.session_ids_match", true)
end

T["Parser Modes"]["consolidation works identically in both modes"] = function()
    child.lua([[
        local Parser = require('cc-tui.parser.stream')

        -- Test data with duplicated message IDs (common in streaming)
        local test_lines = {
            '{"type":"assistant","message":{"id":"msg1","role":"assistant","content":[{"type":"text","text":"Hello"}]}}',
            '{"type":"assistant","message":{"id":"msg1","role":"assistant","content":[{"type":"text","text":" World"}]}}',
            '{"type":"result","subtype":"success"}'
        }

        -- Method 1: Batch parsing (includes consolidation)
        local batch_messages, _ = Parser.parse_lines(test_lines)

        -- Method 2: Line-by-line with manual consolidation
        local raw_messages = {}
        for _, line in ipairs(test_lines) do
            local msg, _ = Parser.parse_line(line)
            if msg then
                table.insert(raw_messages, msg)
            end
        end
        local line_messages = Parser.consolidate_messages(raw_messages)

        _G.batch_consolidated_count = #batch_messages
        _G.line_consolidated_count = #line_messages

        -- Check that message with same ID was consolidated
        local batch_assistant = batch_messages[1]
        local line_assistant = line_messages[1]

        _G.batch_content_count = batch_assistant.message and #batch_assistant.message.content or 0
        _G.line_content_count = line_assistant.message and #line_assistant.message.content or 0
    ]])

    Helpers.expect.global(child, "_G.batch_consolidated_count", 2) -- msg1 consolidated + result
    Helpers.expect.global(child, "_G.line_consolidated_count", 2)
    Helpers.expect.global(child, "_G.batch_content_count", 2) -- Two text blocks consolidated
    Helpers.expect.global(child, "_G.line_content_count", 2)
end

T["Parser Modes"]["error handling consistent between modes"] = function()
    child.lua([[
        local Parser = require('cc-tui.parser.stream')

        local test_lines = {
            '{"type":"system","session_id":"test"}', -- Valid
            'invalid json line',                     -- Invalid JSON
            '',                                      -- Empty line (should be skipped)
            '{"missing_type":"true"}',               -- Missing required field
        }

        -- Method 1: Batch parsing
        local batch_messages, batch_errors = Parser.parse_lines(test_lines)

        -- Method 2: Line-by-line parsing
        local line_messages = {}
        local line_errors = {}

        for i, line in ipairs(test_lines) do
            local msg, err = Parser.parse_line(line)
            if msg then
                table.insert(line_messages, msg)
            elseif err then
                table.insert(line_errors, string.format("Line %d: %s", i, err))
            end
            -- Note: empty lines return nil, nil - no error recorded
        end

        _G.batch_message_count = #batch_messages
        _G.line_message_count = #line_messages
        _G.batch_error_count = #batch_errors
        _G.line_error_count = #line_errors
    ]])

    Helpers.expect.global(child, "_G.batch_message_count", 1) -- Only valid system message
    Helpers.expect.global(child, "_G.line_message_count", 1)
    Helpers.expect.global(child, "_G.batch_error_count", 2) -- JSON error + missing type error
    Helpers.expect.global(child, "_G.line_error_count", 2)
end

return T
