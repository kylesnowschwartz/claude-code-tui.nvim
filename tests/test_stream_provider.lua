local Helpers = dofile("tests/helpers.lua")

-- Tests for StreamProvider - spawns Claude CLI subprocess and streams JSON events

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

-- Tests for StreamProvider
T["StreamProvider"] = MiniTest.new_set()

T["StreamProvider"]["inherits from DataProvider"] = function()
    child.lua([[
        -- This should fail initially (TDD RED)
        local StreamProvider = require('cc-tui.providers.stream')
        local DataProvider = require('cc-tui.providers.base')

        local provider = StreamProvider:new({ command = "echo", args = {"test"} })
        _G.has_start = type(provider.start) == "function"
        _G.has_stop = type(provider.stop) == "function"
        _G.has_register_callback = type(provider.register_callback) == "function"
    ]])

    Helpers.expect.global(child, "_G.has_start", true)
    Helpers.expect.global(child, "_G.has_stop", true)
    Helpers.expect.global(child, "_G.has_register_callback", true)
end

T["StreamProvider"]["can be created with command config"] = function()
    child.lua([[
        local StreamProvider = require('cc-tui.providers.stream')

        local provider = StreamProvider:new({
            command = "claude-code",
            args = { "--output-format", "stream-json", "test prompt" },
            timeout = 30000
        })

        _G.provider_created = provider ~= nil
        _G.has_command = provider.command == "claude-code"
        _G.has_args = type(provider.args) == "table" and #provider.args == 3
        _G.has_timeout = provider.timeout == 30000
    ]])

    Helpers.expect.global(child, "_G.provider_created", true)
    Helpers.expect.global(child, "_G.has_command", true)
    Helpers.expect.global(child, "_G.has_args", true)
    Helpers.expect.global(child, "_G.has_timeout", true)
end

T["StreamProvider"]["validates required config on creation"] = function()
    child.lua([[
        local StreamProvider = require('cc-tui.providers.stream')

        -- Test missing command
        local success1 = pcall(StreamProvider.new, StreamProvider, {})
        _G.missing_command_handled = not success1

        -- Test invalid command type
        local success2 = pcall(StreamProvider.new, StreamProvider, { command = 123 })
        _G.invalid_command_handled = not success2

        -- Test valid config
        local success3 = pcall(StreamProvider.new, StreamProvider, { command = "echo" })
        _G.valid_config_works = success3
    ]])

    Helpers.expect.global(child, "_G.missing_command_handled", true)
    Helpers.expect.global(child, "_G.invalid_command_handled", true)
    Helpers.expect.global(child, "_G.valid_config_works", true)
end

T["StreamProvider"]["start spawns subprocess and triggers callbacks"] = function()
    child.lua([[
        local StreamProvider = require('cc-tui.providers.stream')

        -- Use echo command for predictable testing
        local provider = StreamProvider:new({
            command = "echo",
            args = { '{"type":"test","message":"hello world"}' }
        })

        _G.callback_calls = {
            on_start = false,
            on_data = {},
            on_error = {},
            on_complete = false
        }

        provider:register_callback("on_start", function()
            _G.callback_calls.on_start = true
        end)

        provider:register_callback("on_data", function(line)
            table.insert(_G.callback_calls.on_data, line)
        end)

        provider:register_callback("on_error", function(err)
            table.insert(_G.callback_calls.on_error, err)
        end)

        provider:register_callback("on_complete", function()
            _G.callback_calls.on_complete = true
        end)

        -- Start the provider (should be async)
        provider:start()

        -- Give it a moment to process (in real implementation this would be truly async)
        vim.wait(100)  -- 100ms should be enough for echo command
    ]])

    Helpers.expect.global(child, "_G.callback_calls.on_start", true)
    Helpers.expect.global(child, "_G.callback_calls.on_complete", true)
    -- Should have received the echo output
    child.lua([[
        _G.has_data = #_G.callback_calls.on_data > 0
        _G.first_line = _G.callback_calls.on_data[1]
    ]])
    Helpers.expect.global(child, "_G.has_data", true)
end

T["StreamProvider"]["stop terminates subprocess gracefully"] = function()
    child.lua([[
        local StreamProvider = require('cc-tui.providers.stream')

        -- Use sleep command for testing stop functionality
        local provider = StreamProvider:new({
            command = "sleep",
            args = { "5" }  -- Shorter command for testing
        })

        _G.stop_test = {
            started = false,
            stopped = false
        }

        provider:register_callback("on_start", function()
            _G.stop_test.started = true
        end)

        -- Start provider
        provider:start()
        vim.wait(100)  -- More time to start

        -- Check job started
        _G.stop_test.job_started = provider.job_id ~= nil and provider.job_id > 0

        -- Stop provider
        provider:stop()
        _G.stop_test.stopped = true
        _G.stop_test.job_cleaned_up = provider.job_id == nil

        vim.wait(100)  -- More time to clean up
    ]])

    Helpers.expect.global(child, "_G.stop_test.started", true)
    Helpers.expect.global(child, "_G.stop_test.job_started", true)
    Helpers.expect.global(child, "_G.stop_test.stopped", true)
    Helpers.expect.global(child, "_G.stop_test.job_cleaned_up", true)
end

T["StreamProvider"]["handles subprocess errors gracefully"] = function()
    child.lua([[
        local StreamProvider = require('cc-tui.providers.stream')

        -- Use non-existent command to trigger error
        local provider = StreamProvider:new({
            command = "non_existent_command_xyz123",
            args = {}
        })

        _G.error_test = {
            started = false,
            error_received = false,
            error_message = nil
        }

        provider:register_callback("on_start", function()
            _G.error_test.started = true
        end)

        provider:register_callback("on_error", function(err)
            _G.error_test.error_received = true
            _G.error_test.error_message = err
        end)

        -- Start provider (should fail)
        provider:start()
        vim.wait(200)  -- Give it time to fail
    ]])

    Helpers.expect.global(child, "_G.error_test.started", true)
    Helpers.expect.global(child, "_G.error_test.error_received", true)
    -- Should have meaningful error message
    child.lua([[
        _G.has_error_message = type(_G.error_test.error_message) == "string" and #_G.error_test.error_message > 0
    ]])
    Helpers.expect.global(child, "_G.has_error_message", true)
end

T["StreamProvider"]["integrates with EventBridge for message mapping"] = function()
    child.lua([[
        local StreamProvider = require('cc-tui.providers.stream')

        -- Echo valid Claude CLI JSON
        local provider = StreamProvider:new({
            command = "echo",
            args = { '{"type":"system","subtype":"init","session_id":"test-123","model":"claude-3-5-sonnet"}' }
        })

        _G.bridge_test = {
            raw_events = {},
            mapped_events = {}
        }

        provider:register_callback("on_data", function(line)
            -- StreamProvider already handles EventBridge mapping internally
            -- The line we receive should already be mapped JSON
            table.insert(_G.bridge_test.raw_events, line)

            -- Parse the line to verify it's valid JSON
            local ok, parsed = pcall(vim.json.decode, line)
            if ok then
                table.insert(_G.bridge_test.mapped_events, parsed)
            end
        end)

        provider:start()
        vim.wait(100)
    ]])

    -- Check that we received raw events
    child.lua([[
        _G.has_raw_events = #_G.bridge_test.raw_events > 0
    ]])
    Helpers.expect.global(child, "_G.has_raw_events", true)
    child.lua([[
        _G.has_mapped_events = #_G.bridge_test.mapped_events > 0
        _G.mapped_type = _G.bridge_test.mapped_events[1] and _G.bridge_test.mapped_events[1].type
    ]])
    Helpers.expect.global(child, "_G.has_mapped_events", true)
    Helpers.expect.global(child, "_G.mapped_type", "system")
end

return T
