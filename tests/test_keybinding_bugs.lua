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

        -- Enable plugin with test data
        Main.enable("test")

        -- Wait for tree to be created
        vim.wait(100)

        local state = Main.get_state()
        _G.plugin_enabled = state.popup ~= nil and state.tree ~= nil

        if not _G.plugin_enabled then
            _G.error_msg = "Plugin not enabled properly"
            return
        end

        -- Check if Tab is mapped in the buffer
        local bufnr = state.popup.bufnr
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
    ]])

    Helpers.expect.global(child, "_G.plugin_enabled", true)
    Helpers.expect.global(child, "_G.tab_is_mapped", true)
    Helpers.expect.global(child, "_G.tab_handler_exists", true)
end

T["Keybinding Bugs"]["Question mark should show help menu"] = function()
    child.lua([[
        require('cc-tui').setup()
        local Main = require('cc-tui.main')

        -- Enable plugin with test data
        Main.enable("test")

        -- Wait for tree to be created
        vim.wait(100)

        local state = Main.get_state()
        _G.plugin_enabled = state.popup ~= nil and state.tree ~= nil

        if not _G.plugin_enabled then
            _G.error_msg = "Plugin not enabled properly"
            return
        end

        -- Check if ? is mapped in the buffer
        local bufnr = state.popup.bufnr
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

T["Keybinding Bugs"]["Tab toggle actually changes tree state"] = function()
    child.lua([[
        require('cc-tui').setup()
        local Main = require('cc-tui.main')

        -- Enable plugin with test data
        Main.enable("test")

        -- Wait for tree to be created
        vim.wait(100)

        local state = Main.get_state()
        _G.has_tree = state.tree ~= nil

        if not _G.has_tree then
            _G.error_msg = "No tree found"
            return
        end

        -- Set cursor to first line with a node
        vim.api.nvim_win_set_cursor(0, {1, 0})

        -- Get initial node state
        local initial_node = state.tree:get_node()
        _G.has_initial_node = initial_node ~= nil

        if not initial_node then
            _G.error_msg = "No initial node found"
            return
        end

        local initial_expanded = initial_node:is_expanded()
        _G.initial_expanded = initial_expanded

        -- Simulate Tab key press to toggle
        -- This should call the toggle handler
        local tab_pressed = pcall(function()
            -- Find the Tab keymap and call its handler
            local keymaps = vim.api.nvim_buf_get_keymap(state.popup.bufnr, 'n')
            for _, keymap in ipairs(keymaps) do
                if keymap.lhs == '<Tab>' and keymap.callback then
                    keymap.callback()
                    return true
                end
            end
            return false
        end)

        _G.tab_handler_called = tab_pressed

        -- Check if node state changed
        local final_node = state.tree:get_node()
        local final_expanded = final_node and final_node:is_expanded()
        _G.final_expanded = final_expanded
        _G.state_changed = initial_expanded ~= final_expanded
    ]])

    Helpers.expect.global(child, "_G.has_tree", true)
    Helpers.expect.global(child, "_G.has_initial_node", true)
    Helpers.expect.global(child, "_G.tab_handler_called", true)
    -- The state should change when Tab is pressed
    Helpers.expect.global(child, "_G.state_changed", true)
end

T["Keybinding Bugs"]["Question mark actually shows help window"] = function()
    child.lua([[
        require('cc-tui').setup()
        local Main = require('cc-tui.main')

        -- Enable plugin with test data
        Main.enable("test")

        -- Wait for tree to be created
        vim.wait(100)

        local state = Main.get_state()

        -- Count windows before help
        local windows_before = #vim.api.nvim_list_wins()
        _G.windows_before = windows_before

        -- Simulate ? key press to show help
        local help_shown = pcall(function()
            -- Find the ? keymap and call its handler
            local keymaps = vim.api.nvim_buf_get_keymap(state.popup.bufnr, 'n')
            for _, keymap in ipairs(keymaps) do
                if keymap.lhs == '?' and keymap.callback then
                    keymap.callback()
                    return true
                end
            end
            return false
        end)

        _G.help_handler_called = help_shown

        -- Check if help window opened
        vim.wait(50)  -- Give time for window to open
        local windows_after = #vim.api.nvim_list_wins()
        _G.windows_after = windows_after
        _G.help_window_opened = windows_after > windows_before
    ]])

    Helpers.expect.global(child, "_G.help_handler_called", true)
    Helpers.expect.global(child, "_G.help_window_opened", true)
end

return T
