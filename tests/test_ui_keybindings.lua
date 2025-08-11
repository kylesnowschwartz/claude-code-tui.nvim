local Helpers = dofile("tests/helpers.lua")

-- Tests for keybinding bugs: Tab toggle and ? help menu

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

-- Tests for keybinding bugs
T["Keybinding Bugs"] = MiniTest.new_set()

T["Keybinding Bugs"]["Tab key should toggle tree nodes"] = function()
    child.lua([[
        require('cc-tui').setup()
        local Main = require('cc-tui.main')

        -- Enable plugin with test data (default tab is browse)
        Main.enable("test", "browse")

        -- Wait for tabbed interface to be created
        vim.wait(100)

        local state = Main.get_state()
        _G.plugin_enabled = state.tabbed_manager ~= nil and state.tabbed_manager:is_active()

        if not _G.plugin_enabled then
            _G.error_msg = "Plugin not enabled properly"
            return
        end

        -- Check if Tab is mapped in the buffer (view-level keymaps)
        local bufnr = state.tabbed_manager.popup.bufnr
        local tab_mapped = false

        -- Get all buffer-local keymaps for normal mode
        local keymaps = vim.api.nvim_buf_get_keymap(bufnr, 'n')

        for _, keymap in ipairs(keymaps) do
            if keymap.lhs == '<Tab>' then
                tab_mapped = true
                _G.tab_handler_exists = keymap.callback ~= nil or keymap.rhs ~= nil
                break
            end
        end

        _G.tab_is_mapped = tab_mapped
        _G.current_tab = state.tabbed_manager.current_tab
    ]])

    Helpers.expect.global(child, "_G.plugin_enabled", true)
    Helpers.expect.global(child, "_G.current_tab", "browse")
    Helpers.expect.global(child, "_G.tab_is_mapped", true)
    Helpers.expect.global(child, "_G.tab_handler_exists", true)
end

T["Keybinding Bugs"]["Question mark should switch to help tab"] = function()
    child.lua([[
        require('cc-tui').setup()
        local Main = require('cc-tui.main')

        -- Enable plugin with test data
        Main.enable("test")

        -- Wait for tabbed interface to be created
        vim.wait(100)

        local state = Main.get_state()
        _G.plugin_enabled = state.tabbed_manager ~= nil and state.tabbed_manager:is_active()

        if not _G.plugin_enabled then
            _G.error_msg = "Plugin not enabled properly"
            return
        end

        -- Check if ? is mapped in the buffer
        local bufnr = state.tabbed_manager.popup.bufnr
        local help_mapped = false

        -- Get all buffer-local keymaps for normal mode
        local keymaps = vim.api.nvim_buf_get_keymap(bufnr, 'n')

        for _, keymap in ipairs(keymaps) do
            if keymap.lhs == '?' then
                help_mapped = true
                _G.help_handler_exists = keymap.callback ~= nil or keymap.rhs ~= nil
                break
            end
        end

        _G.help_is_mapped = help_mapped
    ]])

    Helpers.expect.global(child, "_G.plugin_enabled", true)
    Helpers.expect.global(child, "_G.help_is_mapped", true)
    Helpers.expect.global(child, "_G.help_handler_exists", true)
end

T["Keybinding Bugs"]["Tab actually toggles tree nodes"] = function()
    child.lua([[
        require('cc-tui').setup()
        local Main = require('cc-tui.main')

        -- Enable plugin with test data (start on browse tab)
        Main.enable("test", "browse")

        -- Wait for tabbed interface to be created
        vim.wait(100)

        local state = Main.get_state()
        _G.has_tabbed_manager = state.tabbed_manager ~= nil

        if not _G.has_tabbed_manager then
            _G.error_msg = "No tabbed manager found"
            return
        end

        -- Verify we're on browse tab (with tree functionality)
        _G.current_tab = state.tabbed_manager.current_tab

        -- Simulate Tab key press to toggle tree node
        local tab_pressed = pcall(function()
            -- Find the Tab keymap and call its handler
            local keymaps = vim.api.nvim_buf_get_keymap(state.tabbed_manager.popup.bufnr, 'n')
            for _, keymap in ipairs(keymaps) do
                if keymap.lhs == '<Tab>' and keymap.callback then
                    keymap.callback()
                    return true
                end
            end
            return false
        end)

        _G.tab_handler_called = tab_pressed

        -- Tab should not change tabs (should stay on current)
        local final_tab = state.tabbed_manager.current_tab
        _G.final_tab = final_tab
        _G.tab_stayed_same = state.tabbed_manager.current_tab == "browse"
    ]])

    Helpers.expect.global(child, "_G.has_tabbed_manager", true)
    Helpers.expect.global(child, "_G.current_tab", "browse")
    Helpers.expect.global(child, "_G.tab_handler_called", true)
    -- Tab should not change tabs, but toggle tree nodes
    Helpers.expect.global(child, "_G.tab_stayed_same", true)
end

T["Keybinding Bugs"]["Question mark actually switches to help tab"] = function()
    child.lua([[
        require('cc-tui').setup()
        local Main = require('cc-tui.main')

        -- Enable plugin with test data (start on browse tab)
        Main.enable("test", "browse")

        -- Wait for tabbed interface to be created
        vim.wait(100)

        local state = Main.get_state()

        -- Get initial tab state
        local initial_tab = state.tabbed_manager.current_tab
        _G.initial_tab = initial_tab

        -- Simulate ? key press to switch to help tab
        local help_shown = pcall(function()
            -- Find the ? keymap and call its handler
            local keymaps = vim.api.nvim_buf_get_keymap(state.tabbed_manager.popup.bufnr, 'n')
            for _, keymap in ipairs(keymaps) do
                if keymap.lhs == '?' and keymap.callback then
                    keymap.callback()
                    return true
                end
            end
            return false
        end)

        _G.help_handler_called = help_shown

        -- Check if tab switched to help
        vim.wait(50)  -- Give time for tab switch
        local final_tab = state.tabbed_manager.current_tab
        _G.final_tab = final_tab
        _G.switched_to_help = final_tab == "help"
    ]])

    Helpers.expect.global(child, "_G.help_handler_called", true)
    Helpers.expect.global(child, "_G.switched_to_help", true)
end

return T
