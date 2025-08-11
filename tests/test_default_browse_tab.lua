---@brief [[
--- Test that CC-TUI opens to Browse tab by default
--- Verifies the browse-first UI flow
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

-- Test 1: Plugin opens to Browse tab by default
T["default_browse_tab"] = function()
    child.lua([[
        -- Open the plugin without specifying a tab
        require("cc-tui").toggle()

        -- Get the state to check current tab
        local main = require("cc-tui.main")
        local state = main.get_state()

        _G.test_result = {
            is_active = state.is_active,
            current_tab = state.current_tab
        }
    ]])

    local result = child.lua_get("_G.test_result")
    MiniTest.expect.equality(result.is_active, true, "Plugin should be active")
    MiniTest.expect.equality(result.current_tab, "browse", "Should open to Browse tab by default")
end

-- Test 2: Can specify different default tab
T["custom_default_tab"] = function()
    child.lua([[
        -- Close any existing instance
        require("cc-tui").disable()

        -- Open with specific tab
        require("cc-tui").enable("logs")

        -- Get the state to check current tab
        local main = require("cc-tui.main")
        local state = main.get_state()

        _G.test_result = {
            is_active = state.is_active,
            current_tab = state.current_tab
        }
    ]])

    local result = child.lua_get("_G.test_result")
    MiniTest.expect.equality(result.is_active, true, "Plugin should be active")
    MiniTest.expect.equality(result.current_tab, "logs", "Should open to specified tab")
end

-- Test 3: No error when opening to Browse with no conversations
T["browse_no_error"] = function()
    child.lua([[
        -- Open the plugin
        require("cc-tui").toggle()

        -- Check that Browse view is rendered without error
        local main = require("cc-tui.main")
        local state = main.get_state()

        -- Try to get the browse view
        local tabbed_manager = state.tabbed_manager
        local browse_view = nil
        local error_msg = nil

        if tabbed_manager then
            local success, view = pcall(function()
                return tabbed_manager.views["browse"]
            end)
            if success then
                browse_view = view
            else
                error_msg = tostring(view)
            end
        end

        _G.test_result = {
            has_manager = tabbed_manager ~= nil,
            has_browse_view = browse_view ~= nil,
            error = error_msg
        }
    ]])

    local result = child.lua_get("_G.test_result")
    MiniTest.expect.equality(result.has_manager, true, "Should have tabbed manager")
    MiniTest.expect.equality(result.has_browse_view, true, "Should have browse view")
    MiniTest.expect.equality(result.error, nil, "Should have no error")
end

-- Test 4: View tab shows empty state when no conversation selected
T["view_empty_state"] = function()
    child.lua([[
        -- Open the plugin
        require("cc-tui").toggle()

        -- Switch to view tab
        local main = require("cc-tui.main")
        local state = main.get_state()

        if state.tabbed_manager then
            state.tabbed_manager:switch_to_tab("view")
        end

        -- Check current tab
        local new_state = main.get_state()

        _G.test_result = {
            current_tab = new_state.current_tab,
            has_conversation = state.tabbed_manager and
                            state.tabbed_manager.current_conversation_path ~= nil
        }
    ]])

    local result = child.lua_get("_G.test_result")
    MiniTest.expect.equality(result.current_tab, "view", "Should be on View tab")
    MiniTest.expect.equality(result.has_conversation, false, "Should have no conversation selected")
end

return T
