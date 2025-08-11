---@brief [[
--- Tests for BrowseView.open_conversation_file() functionality
--- Tests the 'o' key shortcut feature that opens JSONL files directly in Neovim
--- Validates proper manager interaction, file opening, and edge cases
---@brief ]]

local Helpers = dofile("tests/helpers.lua")

local child = Helpers.new_child_neovim()

local T = MiniTest.new_set({
    hooks = {
        pre_case = function()
            child.restart({ "-u", "scripts/minimal_init.lua" })
            child.lua([[
                _G.CcTui = _G.CcTui or {}
                _G.CcTui.config = _G.CcTui.config or {}
                package.path = "./lua/?.lua;" .. package.path
                require('cc-tui').setup({})

                -- Reset global test state
                _G.test_commands_executed = {}
                _G.test_notifications = {}
                _G.test_manager_close_called = false
                _G.test_schedule_called = false
            ]])
        end,
        post_once = child.stop,
    },
})

T["open_conversation_file method"] = MiniTest.new_set()

T["open_conversation_file method"]["should exist in BrowseView"] = function()
    child.lua([[
        local BrowseView = require("cc-tui.ui.views.browse")
        _G.test_method_exists = type(BrowseView.open_conversation_file) == "function"
    ]])

    local has_method = child.lua_get("_G.test_method_exists")
    Helpers.expect.equality(has_method, true)
end

T["open_conversation_file method"]["should call manager:close() when manager exists"] = function()
    child.lua([[
        local BrowseView = require("cc-tui.ui.views.browse")

        -- Mock manager with close method
        local mock_manager = {
            close = function(self)
                _G.test_manager_close_called = true
            end,
            get_width = function() return 80 end
        }

        -- Create browse view with mock manager
        local browse_view = BrowseView.new(mock_manager)
        browse_view.manager = mock_manager

        -- Add test conversation
        browse_view.conversations = {
            {
                path = "/test/path/conversation.jsonl",
                title = "Test Conversation",
                filename = "conversation.jsonl"
            }
        }
        browse_view.current_index = 1

        -- Mock vim.schedule to capture the scheduled function
        local original_schedule = vim.schedule
        vim.schedule = function(fn)
            _G.test_schedule_called = true
            _G.test_scheduled_function = fn
        end

        -- Mock vim.cmd and vim.notify to track calls
        local original_cmd = vim.cmd
        local original_notify = vim.notify
        vim.cmd = function(cmd)
            table.insert(_G.test_commands_executed, cmd)
        end
        vim.notify = function(msg, level)
            table.insert(_G.test_notifications, {msg = msg, level = level})
        end

        -- Test the method
        browse_view:open_conversation_file()

        -- Execute the scheduled function if it was created
        if _G.test_scheduled_function then
            _G.test_scheduled_function()
        end

        -- Restore original functions
        vim.schedule = original_schedule
        vim.cmd = original_cmd
        vim.notify = original_notify
    ]])

    local manager_close_called = child.lua_get("_G.test_manager_close_called")
    local schedule_called = child.lua_get("_G.test_schedule_called")
    local commands_executed = child.lua_get("_G.test_commands_executed")
    local notifications = child.lua_get("_G.test_notifications")

    Helpers.expect.equality(manager_close_called, true)
    Helpers.expect.equality(schedule_called, true)
    Helpers.expect.equality(#commands_executed, 1)
    Helpers.expect.equality(#notifications, 1)

    -- Check that the correct edit command was executed
    Helpers.expect.match(commands_executed[1], "edit.*conversation%.jsonl")

    -- Check notification content
    Helpers.expect.match(notifications[1].msg, "Opened conversation file")
end

T["open_conversation_file method"]["should handle no conversations gracefully"] = function()
    child.lua([[
        local BrowseView = require("cc-tui.ui.views.browse")

        -- Mock manager
        local mock_manager = {
            close = function(self)
                _G.test_manager_close_called = true
            end,
            get_width = function() return 80 end
        }

        -- Create browse view with no conversations
        local browse_view = BrowseView.new(mock_manager)
        browse_view.manager = mock_manager
        browse_view.conversations = {} -- Empty conversations list
        browse_view.current_index = 1

        -- Test the method - should return early without error
        local success = pcall(browse_view.open_conversation_file, browse_view)

        _G.test_result = {
            success = success,
            manager_close_called = _G.test_manager_close_called or false
        }
    ]])

    local result = child.lua_get("_G.test_result")
    Helpers.expect.equality(result.success, true)
    Helpers.expect.equality(result.manager_close_called, false) -- Should not call close when no conversations
end

T["keymap integration"] = MiniTest.new_set()

T["keymap integration"]["should register 'o' key in BrowseView keymaps"] = function()
    child.lua([[
        local BrowseView = require("cc-tui.ui.views.browse")

        -- Mock manager
        local mock_manager = {
            get_width = function() return 80 end
        }

        -- Create browse view
        local browse_view = BrowseView.new(mock_manager)

        -- Check if 'o' keymap exists and is a function
        _G.test_has_o_keymap = type(browse_view.keymaps["o"]) == "function"
    ]])

    local has_o_keymap = child.lua_get("_G.test_has_o_keymap")
    Helpers.expect.equality(has_o_keymap, true)
end

T["keymap integration"]["should call open_conversation_file when 'o' key is pressed"] = function()
    child.lua([[
        local BrowseView = require("cc-tui.ui.views.browse")

        -- Mock manager
        local mock_manager = {
            close = function(self)
                _G.test_manager_close_called = true
            end,
            get_width = function() return 80 end
        }

        -- Create browse view
        local browse_view = BrowseView.new(mock_manager)
        browse_view.manager = mock_manager

        -- Add test conversation
        browse_view.conversations = {
            {
                path = "/test/path/conversation.jsonl",
                title = "Test Conversation",
                filename = "conversation.jsonl"
            }
        }
        browse_view.current_index = 1

        -- Mock vim functions
        vim.schedule = function(fn) fn() end
        vim.cmd = function(cmd) _G.test_command_executed = cmd end
        vim.notify = function(msg, level) _G.test_notification = msg end

        -- Execute the 'o' keymap function
        local o_keymap = browse_view.keymaps["o"]
        o_keymap()
    ]])

    local manager_close_called = child.lua_get("_G.test_manager_close_called")
    local command_executed = child.lua_get("_G.test_command_executed")
    local notification = child.lua_get("_G.test_notification")

    Helpers.expect.equality(manager_close_called, true)
    Helpers.expect.truthy(command_executed, "command should be executed")
    Helpers.expect.match(command_executed, "edit")
    Helpers.expect.match(notification, "Opened conversation file")
end

T["edge cases"] = MiniTest.new_set()

T["edge cases"]["should handle current_index out of bounds"] = function()
    child.lua([[
        local BrowseView = require("cc-tui.ui.views.browse")

        -- Mock manager
        local mock_manager = {
            close = function(self) end,
            get_width = function() return 80 end
        }

        -- Create browse view
        local browse_view = BrowseView.new(mock_manager)
        browse_view.manager = mock_manager

        -- Add conversations but set current_index out of bounds
        browse_view.conversations = {
            {
                path = "/test/path/conversation1.jsonl",
                title = "Test Conversation 1",
                filename = "conversation1.jsonl"
            }
        }
        browse_view.current_index = 5 -- Out of bounds (only 1 conversation)

        -- Test the method - should handle gracefully
        local success = pcall(browse_view.open_conversation_file, browse_view)

        _G.test_result = {
            success = success,
            conversations_count = #browse_view.conversations,
            current_index = browse_view.current_index
        }
    ]])

    local result = child.lua_get("_G.test_result")
    Helpers.expect.equality(result.success, true) -- Should not error
    Helpers.expect.equality(result.conversations_count, 1)
    Helpers.expect.equality(result.current_index, 5) -- Index unchanged
end

T["edge cases"]["should handle conversation without path field"] = function()
    child.lua([[
        local BrowseView = require("cc-tui.ui.views.browse")

        -- Mock manager
        local mock_manager = {
            close = function(self)
                _G.test_manager_close_called = true
            end,
            get_width = function() return 80 end
        }

        -- Create browse view
        local browse_view = BrowseView.new(mock_manager)
        browse_view.manager = mock_manager

        -- Add conversation without path field
        browse_view.conversations = {
            {
                -- Missing path field (nil)
                path = nil,
                title = "Test Conversation",
                filename = "conversation.jsonl"
            }
        }
        browse_view.current_index = 1

        -- Mock vim functions to detect if they're called
        local command_executed = false
        local warn_message = nil
        vim.schedule = function(fn) fn() end
        vim.cmd = function(cmd)
            command_executed = true
            _G.test_command = cmd
        end
        vim.notify = function(msg, level)
            if level == vim.log.levels.WARN then
                warn_message = msg
            end
        end

        -- Test the method - should show warning and not execute command
        local success = pcall(browse_view.open_conversation_file, browse_view)

        _G.test_result = {
            success = success,
            manager_close_called = _G.test_manager_close_called or false,
            command_executed = command_executed,
            warn_message = warn_message
        }
    ]])

    local result = child.lua_get("_G.test_result")

    Helpers.expect.equality(result.success, true) -- The method call itself succeeds
    Helpers.expect.equality(result.manager_close_called, false) -- Manager close should NOT be called
    Helpers.expect.equality(result.command_executed, false) -- Command should NOT be executed
    -- Should show a warning about missing path
    Helpers.expect.match(result.warn_message, "path not available")
end

return T
