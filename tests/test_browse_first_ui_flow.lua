---@brief [[
--- TDD Tests for Browse-First UI Flow Refactor
--- Tests that Browse is the default tab and Enter opens conversations in View tab
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

-- Test 1: Browse should be the default tab when opening CcTui
T["browse_is_default_tab"] = function()
    -- Open CcTui
    child.cmd("CcTui")
    
    -- Get the current tab from TabbedManager
    local current_tab = child.lua_get([[
        local manager = require("cc-tui.ui.tabbed_manager").get_instance()
        if manager then
            return manager.current_tab
        else
            return nil
        end
    ]])
    
    -- Browse should be the active tab, not "current"
    MiniTest.expect.equality(current_tab, "browse")
end

-- Test 2: Tab definitions should have View instead of Current
T["view_tab_replaces_current"] = function()
    -- Get tab definitions
    local tabs = child.lua_get([[
        local TabbedManager = require("cc-tui.ui.tabbed_manager")
        if TabbedManager.get_tab_definitions then
            return TabbedManager.get_tab_definitions()
        else
            return {}
        end
    ]])
    
    -- Should have a "view" tab
    local has_view_tab = false
    local has_current_tab = false
    
    for _, tab in ipairs(tabs or {}) do
        if tab.id == "view" then
            has_view_tab = true
        end
        if tab.id == "current" then
            has_current_tab = true
        end
    end
    
    MiniTest.expect.equality(has_view_tab, true, "Should have a 'view' tab")
    MiniTest.expect.equality(has_current_tab, false, "Should not have a 'current' tab")
end

-- Test 3: Pressing Enter in Browse should open conversation in View tab
T["enter_opens_conversation_in_view"] = function()
    -- Open CcTui (starts in Browse)
    child.cmd("CcTui")
    
    -- Simulate having a conversation selected in Browse
    child.lua([[
        local browse = require("cc-tui.ui.views.browse")
        local manager = require("cc-tui.ui.tabbed_manager").get_instance()
        
        -- Mock a conversation selection
        if manager and manager.views and manager.views.browse then
            local browse_view = manager.views.browse
            -- Set a test conversation path
            browse_view.selected_conversation_path = "/test/conversation.jsonl"
        end
    ]])
    
    -- Simulate pressing Enter
    child.type_keys("<CR>")
    
    -- Check that we switched to View tab
    local result = child.lua_get([[
        local manager = require("cc-tui.ui.tabbed_manager").get_instance()
        if not manager then 
            return { tab = nil, path = nil } 
        end
        
        local current_tab = manager.current_tab
        local view_tab = nil
        if manager.views then
            view_tab = manager.views.view
        end
        local conversation_path = nil
        if view_tab then
            conversation_path = view_tab.conversation_path
        end
        
        return {
            tab = current_tab,
            path = conversation_path
        }
    ]])
    
    MiniTest.expect.equality(result.tab, "view", "Should switch to view tab")
    MiniTest.expect.equality(result.path, "/test/conversation.jsonl", "View should show selected conversation")
end

-- Test 4: View tab should display the selected conversation tree
T["view_tab_shows_conversation_tree"] = function()
    -- Open CcTui
    child.cmd("CcTui")
    
    -- Load a conversation into View tab
    child.lua([[
        local manager = require("cc-tui.ui.tabbed_manager").get_instance()
        if manager then
            -- Open a specific conversation in View
            manager:open_conversation_in_view("/test/conversation.jsonl")
        end
    ]])
    
    -- Check that View tab has tree data
    local has_tree = child.lua_get([[
        local manager = require("cc-tui.ui.tabbed_manager").get_instance()
        if not manager then
            return false
        end
        if not manager.views then
            return false
        end
        if not manager.views.view then
            return false
        end
        
        local view = manager.views.view
        if view.tree_data then
            return true
        else
            return false
        end
    ]])
    
    MiniTest.expect.equality(has_tree, true, "View tab should have tree data")
end

-- Test 5: Tab navigation should work with V for View instead of C for Current
T["view_tab_keybinding"] = function()
    -- Open CcTui
    child.cmd("CcTui")
    
    -- Press 'V' to switch to View tab
    child.type_keys("V")
    
    local current_tab = child.lua_get([[
        local manager = require("cc-tui.ui.tabbed_manager").get_instance()
        if manager then
            return manager.current_tab
        else
            return nil
        end
    ]])
    
    MiniTest.expect.equality(current_tab, "view", "V key should switch to View tab")
end

-- Test 6: Browse tab should show list of conversations
T["browse_shows_conversation_list"] = function()
    -- Open CcTui (starts in Browse)
    child.cmd("CcTui")
    
    -- Check that Browse view has conversation list
    local has_conversations = child.lua_get([[
        local manager = require("cc-tui.ui.tabbed_manager").get_instance()
        if not manager then
            return false
        end
        if not manager.views then
            return false
        end
        if not manager.views.browse then
            return false
        end
        
        local browse = manager.views.browse
        if browse.conversations and type(browse.conversations) == "table" then
            return true
        else
            return false
        end
    ]])
    
    MiniTest.expect.equality(has_conversations, true, "Browse should have conversation list")
end

-- Test 7: View tab should be empty/show message when no conversation selected
T["view_tab_empty_state"] = function()
    -- Open CcTui
    child.cmd("CcTui")
    
    -- Switch to View tab without selecting a conversation
    child.type_keys("V")
    
    -- Check View tab state
    local view_state = child.lua_get([[
        local manager = require("cc-tui.ui.tabbed_manager").get_instance()
        if not manager then
            return { has_content = false, has_message = false }
        end
        if not manager.views then
            return { has_content = false, has_message = false }
        end
        if not manager.views.view then
            return { has_content = false, has_message = false }
        end
        
        local view = manager.views.view
        return {
            has_content = (view.tree_data ~= nil),
            has_message = (view.empty_message ~= nil)
        }
    ]])
    
    MiniTest.expect.equality(view_state.has_content, false, "View should have no content when no conversation selected")
    MiniTest.expect.equality(view_state.has_message, true, "View should show empty state message")
end

-- Test 8: Selecting different conversation in Browse should update View
T["browse_selection_updates_view"] = function()
    -- Open CcTui
    child.cmd("CcTui")
    
    -- Select first conversation
    child.lua([[
        local manager = require("cc-tui.ui.tabbed_manager").get_instance()
        if manager then
            manager:open_conversation_in_view("/test/conversation1.jsonl")
        end
    ]])
    
    -- Go back to Browse
    child.type_keys("B")
    
    -- Select different conversation
    child.lua([[
        local manager = require("cc-tui.ui.tabbed_manager").get_instance()
        if manager then
            manager:open_conversation_in_view("/test/conversation2.jsonl")
        end
    ]])
    
    -- Check View has updated
    local conversation_path = child.lua_get([[
        local manager = require("cc-tui.ui.tabbed_manager").get_instance()
        if not manager then
            return nil
        end
        if not manager.views then
            return nil
        end
        if not manager.views.view then
            return nil
        end
        
        return manager.views.view.conversation_path
    ]])
    
    MiniTest.expect.equality(conversation_path, "/test/conversation2.jsonl", "View should show newly selected conversation")
end

return T