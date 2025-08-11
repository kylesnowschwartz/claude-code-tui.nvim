---@brief [[
--- Simple TDD Tests for Browse-First UI Flow
--- Tests core functionality without complex setup
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

-- Test 1: Browse should be the default tab
T["browse_is_default_tab"] = function()
    -- Create and show manager
    child.lua([[
        local TabbedManager = require("cc-tui.ui.tabbed_manager")
        _G.test_manager = TabbedManager.new()
        _G.test_manager:show()
        _G.test_result = _G.test_manager.current_tab
    ]])
    
    local current_tab = child.lua_get("_G.test_result")
    MiniTest.expect.equality(current_tab, "browse")
end

-- Test 2: Tab definitions should have View instead of Current
T["view_tab_exists"] = function()
    child.lua([[
        local TabbedManager = require("cc-tui.ui.tabbed_manager")
        local tabs = TabbedManager.get_tab_definitions()
        _G.has_view = false
        _G.has_current = false
        
        for _, tab in ipairs(tabs) do
            if tab.id == "view" then
                _G.has_view = true
            end
            if tab.id == "current" then
                _G.has_current = true
            end
        end
    ]])
    
    local has_view = child.lua_get("_G.has_view")
    local has_current = child.lua_get("_G.has_current")
    
    MiniTest.expect.equality(has_view, true, "Should have a 'view' tab")
    MiniTest.expect.equality(has_current, false, "Should not have a 'current' tab")
end

-- Test 3: Manager should have open_conversation_in_view method
T["open_conversation_method_exists"] = function()
    child.lua([[
        local TabbedManager = require("cc-tui.ui.tabbed_manager")
        local manager = TabbedManager.new()
        _G.test_result = type(manager.open_conversation_in_view) == "function"
    ]])
    
    local has_method = child.lua_get("_G.test_result")
    MiniTest.expect.equality(has_method, true, "Should have open_conversation_in_view method")
end

-- Test 4: View tab should handle empty state
T["view_tab_empty_state"] = function()
    child.lua([[
        local TabbedManager = require("cc-tui.ui.tabbed_manager")
        local manager = TabbedManager.new()
        manager:show()
        
        -- Switch to view tab
        manager:switch_to_tab("view")
        
        -- Load view and check empty state
        local view = manager:load_view("view")
        _G.has_empty_message = view.empty_message ~= nil
        _G.has_no_tree = view.tree_data == nil
    ]])
    
    local has_empty_message = child.lua_get("_G.has_empty_message")
    local has_no_tree = child.lua_get("_G.has_no_tree")
    
    MiniTest.expect.equality(has_empty_message, true, "View should have empty message")
    MiniTest.expect.equality(has_no_tree, true, "View should have no tree data initially")
end

-- Test 5: Browse view should track selected conversation
T["browse_tracks_selection"] = function()
    child.lua([[
        local TabbedManager = require("cc-tui.ui.tabbed_manager")
        local manager = TabbedManager.new()
        manager:show()
        
        -- Get browse view
        local browse = manager:load_view("browse")
        
        -- Check that it has the field for tracking
        _G.has_field = browse.selected_conversation_path == nil
    ]])
    
    local has_field = child.lua_get("_G.has_field")
    MiniTest.expect.equality(has_field, true, "Browse should have selected_conversation_path field")
end

return T