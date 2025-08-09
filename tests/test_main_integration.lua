local Helpers = dofile("tests/helpers.lua")

-- Integration tests for main.lua refactoring with StaticProvider

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

-- Tests for main.lua integration with StaticProvider
T["Main Integration"] = MiniTest.new_set()

T["Main Integration"]["can load plugin with provider abstraction"] = function()
    child.lua([[
        require('cc-tui').setup()
        local Main = require('cc-tui.main')

        -- Test the main state is accessible
        local state = Main.get_state()
        _G.main_state_exists = state ~= nil
        _G.has_popup = state.popup == nil -- Should be nil when disabled
        _G.has_tree = state.tree == nil -- Should be nil when disabled
    ]])

    Helpers.expect.global(child, "_G.main_state_exists", true)
    Helpers.expect.global(child, "_G.has_popup", true)
    Helpers.expect.global(child, "_G.has_tree", true)
end

T["Main Integration"]["enable loads data with provider pattern"] = function()
    child.lua([[
        require('cc-tui').setup()
        local Main = require('cc-tui.main')

        -- Mock the test data file to ensure predictable behavior
        local TestData = require('cc-tui.parser.test_data')
        local original_load = TestData.load_sample_lines
        TestData.load_sample_lines = function(limit)
            return {
                '{"type":"system","subtype":"init","session_id":"test-123","model":"claude-3-5-sonnet"}',
                '{"type":"assistant","message":{"id":"msg1","role":"assistant","content":[{"type":"text","text":"Test message"}]},"session_id":"test-123"}',
                '{"type":"result","subtype":"success","session_id":"test-123","total_cost_usd":0.01}'
            }
        end

        -- Enable the plugin
        Main.enable("test")

        -- Check state after enabling
        local state = Main.get_state()
        _G.plugin_enabled = state.popup ~= nil
        _G.has_messages = #state.messages > 0
        _G.has_tree_data = state.tree_data ~= nil

        -- Clean up
        Main.disable("test")
        TestData.load_sample_lines = original_load
    ]])

    Helpers.expect.global(child, "_G.plugin_enabled", true)
    Helpers.expect.global(child, "_G.has_messages", true)
    Helpers.expect.global(child, "_G.has_tree_data", true)
end

T["Main Integration"]["disable cleans up provider resources"] = function()
    child.lua([[
        require('cc-tui').setup()
        local Main = require('cc-tui.main')

        -- Mock test data
        local TestData = require('cc-tui.parser.test_data')
        local original_load = TestData.load_sample_lines
        TestData.load_sample_lines = function(limit)
            return {'{"type":"system","subtype":"init","session_id":"test-123"}'}
        end

        -- Enable then disable
        Main.enable("test")
        local enabled_state = Main.get_state()
        _G.enabled_has_popup = enabled_state.popup ~= nil

        Main.disable("test")
        local disabled_state = Main.get_state()
        _G.disabled_has_popup = disabled_state.popup == nil
        _G.disabled_has_tree = disabled_state.tree == nil
        _G.disabled_has_messages = #disabled_state.messages == 0

        -- Clean up
        TestData.load_sample_lines = original_load
    ]])

    Helpers.expect.global(child, "_G.enabled_has_popup", true)
    Helpers.expect.global(child, "_G.disabled_has_popup", true)
    Helpers.expect.global(child, "_G.disabled_has_tree", true)
    Helpers.expect.global(child, "_G.disabled_has_messages", true)
end

T["Main Integration"]["handles empty data gracefully with provider"] = function()
    child.lua([[
        require('cc-tui').setup()
        local Main = require('cc-tui.main')

        -- Mock empty test data
        local TestData = require('cc-tui.parser.test_data')
        local original_load = TestData.load_sample_lines
        TestData.load_sample_lines = function(limit)
            return {} -- Empty data
        end

        -- Try to enable with empty data
        Main.enable("test")

        local state = Main.get_state()
        _G.failed_gracefully = state.popup == nil -- Should not create popup on failure
        _G.no_messages = #state.messages == 0

        -- Clean up
        TestData.load_sample_lines = original_load
    ]])

    Helpers.expect.global(child, "_G.failed_gracefully", true)
    Helpers.expect.global(child, "_G.no_messages", true)
end

T["Main Integration"]["refresh works with provider pattern"] = function()
    child.lua([[
        require('cc-tui').setup()
        local Main = require('cc-tui.main')

        -- Mock test data
        local TestData = require('cc-tui.parser.test_data')
        local original_load = TestData.load_sample_lines
        local call_count = 0
        TestData.load_sample_lines = function(limit)
            call_count = call_count + 1
            return {'{"type":"system","subtype":"init","session_id":"test-' .. call_count .. '"}'}
        end

        -- Enable plugin
        Main.enable("test")
        local initial_messages = #Main.get_state().messages

        -- Refresh
        Main.refresh()
        local refreshed_messages = #Main.get_state().messages

        _G.initial_count = initial_messages
        _G.refreshed_count = refreshed_messages
        _G.load_called_twice = call_count == 2

        -- Clean up
        Main.disable("test")
        TestData.load_sample_lines = original_load
    ]])

    Helpers.expect.global(child, "_G.initial_count", 1)
    Helpers.expect.global(child, "_G.refreshed_count", 1)
    Helpers.expect.global(child, "_G.load_called_twice", true)
end

return T
