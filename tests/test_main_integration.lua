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

T["Main Integration"]["enable loads data with tabbed manager"] = function()
    child.lua([[
        require('cc-tui').setup()
        local Main = require('cc-tui.main')

        -- Enable the plugin
        local success = Main.enable("test")
        _G.enable_success = success

        -- Check state after enabling
        local state = Main.get_state()
        _G.has_tabbed_manager = state.tabbed_manager ~= nil
        _G.manager_is_active = state.tabbed_manager and state.tabbed_manager:is_active() or false
        _G.current_tab = state.current_tab
        _G.is_active = state.is_active

        -- Clean up
        Main.disable("test")
    ]])

    Helpers.expect.global(child, "_G.enable_success", true)
    Helpers.expect.global(child, "_G.has_tabbed_manager", true)
    Helpers.expect.global(child, "_G.manager_is_active", true)
    Helpers.expect.global(child, "_G.is_active", true)
end

T["Main Integration"]["disable cleans up tabbed manager resources"] = function()
    child.lua([[
        require('cc-tui').setup()
        local Main = require('cc-tui.main')

        -- Enable then disable
        Main.enable("test")
        local enabled_state = Main.get_state()
        _G.enabled_is_active = enabled_state.is_active
        _G.enabled_has_tabbed_manager = enabled_state.tabbed_manager ~= nil

        Main.disable("test")
        local disabled_state = Main.get_state()
        _G.disabled_is_active = disabled_state.is_active
        _G.disabled_has_tabbed_manager = disabled_state.tabbed_manager == nil
        _G.disabled_has_messages = #disabled_state.messages == 0
        _G.disabled_has_tree_data = disabled_state.tree_data == nil
    ]])

    Helpers.expect.global(child, "_G.enabled_is_active", true)
    Helpers.expect.global(child, "_G.enabled_has_tabbed_manager", true)
    Helpers.expect.global(child, "_G.disabled_is_active", false)
    Helpers.expect.global(child, "_G.disabled_has_tabbed_manager", true)
    Helpers.expect.global(child, "_G.disabled_has_messages", true)
    Helpers.expect.global(child, "_G.disabled_has_tree_data", true)
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

T["Main Integration"]["refresh works with tabbed manager"] = function()
    child.lua([[
        require('cc-tui').setup()
        local Main = require('cc-tui.main')

        -- Enable plugin
        Main.enable("test")
        local initial_state = Main.get_state()
        _G.initial_is_active = initial_state.is_active

        -- Refresh should work when manager is active
        Main.refresh()
        local refreshed_state = Main.get_state()
        _G.refreshed_is_active = refreshed_state.is_active
        _G.refresh_worked = true -- If refresh doesn't crash, it worked

        -- Clean up
        Main.disable("test")

        -- Refresh should be no-op when manager is not active
        Main.refresh()
        local disabled_state = Main.get_state()
        _G.disabled_is_active = disabled_state.is_active
    ]])

    Helpers.expect.global(child, "_G.initial_is_active", true)
    Helpers.expect.global(child, "_G.refreshed_is_active", true)
    Helpers.expect.global(child, "_G.refresh_worked", true)
    Helpers.expect.global(child, "_G.disabled_is_active", false)
end

return T
