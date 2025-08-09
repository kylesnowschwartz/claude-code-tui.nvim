local Helpers = dofile("tests/helpers.lua")

-- Tests for EventBridge - maps Claude CLI JSON events to internal message format

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

-- Tests for EventBridge
T["EventBridge"] = MiniTest.new_set()

T["EventBridge"]["module exists and has required methods"] = function()
    child.lua([[
        -- This should fail initially (TDD RED)
        local EventBridge = require('cc-tui.bridge.event_bridge')
        _G.module_exists = type(EventBridge) == "table"
        _G.has_map_event = type(EventBridge.map_event) == "function"
        _G.has_is_valid_event = type(EventBridge.is_valid_event) == "function"
    ]])

    Helpers.expect.global(child, "_G.module_exists", true)
    Helpers.expect.global(child, "_G.has_map_event", true)
    Helpers.expect.global(child, "_G.has_is_valid_event", true)
end

T["EventBridge"]["maps system.init event correctly"] = function()
    child.lua([[
        local EventBridge = require('cc-tui.bridge.event_bridge')

        local cli_event = {
            type = "system",
            subtype = "init",
            session_id = "test-session-123",
            model = "claude-3-5-sonnet",
            cwd = "/path/to/project"
        }

        local mapped = EventBridge.map_event(cli_event)

        _G.mapped_type = mapped and mapped.type
        _G.mapped_subtype = mapped and mapped.subtype
        _G.mapped_session_id = mapped and mapped.session_id
        _G.mapped_model = mapped and mapped.model
    ]])

    Helpers.expect.global(child, "_G.mapped_type", "system")
    Helpers.expect.global(child, "_G.mapped_subtype", "init")
    Helpers.expect.global(child, "_G.mapped_session_id", "test-session-123")
    Helpers.expect.global(child, "_G.mapped_model", "claude-3-5-sonnet")
end

T["EventBridge"]["maps assistant message event correctly"] = function()
    child.lua([[
        local EventBridge = require('cc-tui.bridge.event_bridge')

        local cli_event = {
            type = "assistant",
            message = {
                id = "msg_123",
                role = "assistant",
                content = {
                    {
                        type = "text",
                        text = "I'll help you with that."
                    }
                }
            },
            session_id = "test-session"
        }

        local mapped = EventBridge.map_event(cli_event)

        _G.mapped_type = mapped and mapped.type
        _G.mapped_message_id = mapped and mapped.message and mapped.message.id
        _G.mapped_content_count = mapped and mapped.message and mapped.message.content and #mapped.message.content or 0
        _G.first_text = mapped and mapped.message and mapped.message.content and mapped.message.content[1] and mapped.message.content[1].text
    ]])

    Helpers.expect.global(child, "_G.mapped_type", "assistant")
    Helpers.expect.global(child, "_G.mapped_message_id", "msg_123")
    Helpers.expect.global(child, "_G.mapped_content_count", 1)
    Helpers.expect.global(child, "_G.first_text", "I'll help you with that.")
end

T["EventBridge"]["maps tool use event correctly"] = function()
    child.lua([[
        local EventBridge = require('cc-tui.bridge.event_bridge')

        local cli_event = {
            type = "assistant",
            message = {
                id = "msg_456",
                role = "assistant",
                content = {
                    {
                        type = "tool_use",
                        id = "tool_789",
                        name = "Read",
                        input = { file_path = "/path/to/file.lua" }
                    }
                }
            },
            session_id = "test-session"
        }

        local mapped = EventBridge.map_event(cli_event)

        _G.has_tool_use = false
        if mapped and mapped.message and mapped.message.content then
            for _, content in ipairs(mapped.message.content) do
                if content.type == "tool_use" and content.name == "Read" then
                    _G.has_tool_use = true
                    _G.tool_id = content.id
                    _G.tool_input_file = content.input and content.input.file_path
                    break
                end
            end
        end
    ]])

    Helpers.expect.global(child, "_G.has_tool_use", true)
    Helpers.expect.global(child, "_G.tool_id", "tool_789")
    Helpers.expect.global(child, "_G.tool_input_file", "/path/to/file.lua")
end

T["EventBridge"]["maps result event correctly"] = function()
    child.lua([[
        local EventBridge = require('cc-tui.bridge.event_bridge')

        local cli_event = {
            type = "result",
            subtype = "success",
            session_id = "test-session",
            total_cost_usd = 0.025,
            duration_ms = 1500,
            num_turns = 3
        }

        local mapped = EventBridge.map_event(cli_event)

        _G.mapped_type = mapped and mapped.type
        _G.mapped_subtype = mapped and mapped.subtype
        _G.mapped_cost = mapped and mapped.total_cost_usd
        _G.mapped_duration = mapped and mapped.duration_ms
    ]])

    Helpers.expect.global(child, "_G.mapped_type", "result")
    Helpers.expect.global(child, "_G.mapped_subtype", "success")
    Helpers.expect.global(child, "_G.mapped_cost", 0.025)
    Helpers.expect.global(child, "_G.mapped_duration", 1500)
end

T["EventBridge"]["validates event format correctly"] = function()
    child.lua([[
        local EventBridge = require('cc-tui.bridge.event_bridge')

        local valid_event = { type = "system", session_id = "test" }
        local invalid_event_no_type = { session_id = "test" }
        local invalid_event_wrong_type = { type = 123 }

        _G.valid_is_valid = EventBridge.is_valid_event(valid_event)
        _G.no_type_invalid = not EventBridge.is_valid_event(invalid_event_no_type)
        _G.wrong_type_invalid = not EventBridge.is_valid_event(invalid_event_wrong_type)
    ]])

    Helpers.expect.global(child, "_G.valid_is_valid", true)
    Helpers.expect.global(child, "_G.no_type_invalid", true)
    Helpers.expect.global(child, "_G.wrong_type_invalid", true)
end

T["EventBridge"]["handles unknown event types gracefully"] = function()
    child.lua([[
        local EventBridge = require('cc-tui.bridge.event_bridge')

        local unknown_event = {
            type = "unknown_future_type",
            session_id = "test",
            some_data = "value"
        }

        local mapped = EventBridge.map_event(unknown_event)

        -- Should pass through unknown events unchanged for forward compatibility
        _G.mapped_type = mapped and mapped.type
        _G.mapped_session_id = mapped and mapped.session_id
        _G.mapped_data = mapped and mapped.some_data
    ]])

    Helpers.expect.global(child, "_G.mapped_type", "unknown_future_type")
    Helpers.expect.global(child, "_G.mapped_session_id", "test")
    Helpers.expect.global(child, "_G.mapped_data", "value")
end

return T
