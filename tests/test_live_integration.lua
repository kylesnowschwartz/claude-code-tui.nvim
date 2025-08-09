local Helpers = dofile("tests/helpers.lua")

-- Tests for live streaming integration with UI

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

-- Tests for live streaming integration
T["Live Integration"] = MiniTest.new_set()

T["Live Integration"]["main module can start streaming provider"] = function()
    child.lua([[
        require('cc-tui').setup()
        local Main = require('cc-tui.main')

        -- Test streaming capability exists
        _G.has_start_streaming = type(Main.start_streaming) == "function"
        _G.has_stop_streaming = type(Main.stop_streaming) == "function"
    ]])

    Helpers.expect.global(child, "_G.has_start_streaming", true)
    Helpers.expect.global(child, "_G.has_stop_streaming", true)
end

T["Live Integration"]["streaming updates tree incrementally"] = function()
    child.lua([[
        require('cc-tui').setup()
        local Main = require('cc-tui.main')

        -- Enable plugin first (required for process_line to work)
        Main.enable("test")

        -- Mock streaming with echo for testing
        _G.streaming_test = {
            messages_received = 0,
            tree_updates = 0
        }

        -- Start streaming with test command
        Main.start_streaming({
            command = "echo",
            args = { '{"type":"system","subtype":"init","session_id":"stream-test","model":"claude-3-5-sonnet"}' }
        })

        -- Check if streaming provider was created immediately
        local state_immediate = Main.get_state()
        _G.streaming_started = state_immediate.streaming_provider ~= nil

        -- Wait for processing
        vim.wait(200)

        -- Check if data was received (provider may be nil after completion)
        local state = Main.get_state()
        _G.has_messages = #state.messages > 0
        _G.first_message_type = state.messages[1] and state.messages[1].type
    ]])

    Helpers.expect.global(child, "_G.streaming_started", true)
    Helpers.expect.global(child, "_G.has_messages", true)
    Helpers.expect.global(child, "_G.first_message_type", "system")
end

T["Live Integration"]["stop streaming cleans up resources"] = function()
    child.lua([[
        require('cc-tui').setup()
        local Main = require('cc-tui.main')

        -- Start streaming
        Main.start_streaming({
            command = "sleep",
            args = { "5" }
        })

        vim.wait(100)  -- Let it start

        local state_before = Main.get_state()
        _G.was_streaming = state_before.streaming_provider ~= nil

        -- Stop streaming
        Main.stop_streaming()

        local state_after = Main.get_state()
        _G.streaming_stopped = state_after.streaming_provider == nil
    ]])

    Helpers.expect.global(child, "_G.was_streaming", true)
    Helpers.expect.global(child, "_G.streaming_stopped", true)
end

T["Live Integration"]["uses vim.schedule for thread-safe UI updates"] = function()
    child.lua([[
        require('cc-tui').setup()
        local Main = require('cc-tui.main')

        -- Enable plugin first
        Main.enable("test")

        -- Mock vim.schedule to track calls
        local original_schedule = vim.schedule
        _G.schedule_calls = 0
        vim.schedule = function(fn)
            _G.schedule_calls = _G.schedule_calls + 1
            original_schedule(fn)
        end

        -- Start streaming
        Main.start_streaming({
            command = "echo",
            args = { '{"type":"assistant","message":{"id":"msg1","role":"assistant","content":[{"type":"text","text":"Live update"}]}}' }
        })

        vim.wait(200)

        -- Restore original function
        vim.schedule = original_schedule

        _G.used_schedule = _G.schedule_calls > 0
    ]])

    Helpers.expect.global(child, "_G.used_schedule", true)
end

return T
