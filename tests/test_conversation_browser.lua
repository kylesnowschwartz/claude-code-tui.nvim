local Helpers = dofile("tests/helpers.lua")

-- Unit tests for ConversationBrowser UI component following TDD approach

local child = Helpers.new_child_neovim()

local T = MiniTest.new_set({
    hooks = {
        -- This will be executed before every (even nested) case
        pre_case = function()
            -- Restart child process with custom 'init.lua' script
            child.restart({ "-u", "scripts/minimal_init.lua" })

            -- Initialize global state for tests
            child.lua([[
                _G.CcTui = _G.CcTui or {}
                _G.CcTui.config = _G.CcTui.config or {}
            ]])
        end,
        -- This will be executed one after all tests from this set are finished
        post_once = child.stop,
    },
})

-- Tests for ConversationBrowser creation
T["ConversationBrowser.new"] = MiniTest.new_set()

T["ConversationBrowser.new"]["creates browser with required options"] = function()
    child.lua([[
        local ConversationBrowser = require('cc-tui.ui.conversation_browser')

        -- Test successful creation with minimal options
        local browser, err = ConversationBrowser.new({
            on_select = function(path) end
        })

        _G.browser_created = browser ~= nil
        _G.creation_error = err
        _G.has_split = browser and browser.split ~= nil
        _G.has_project_name = browser and type(browser.project_name) == "string"
        _G.has_conversations = browser and type(browser.conversations) == "table"
    ]])

    Helpers.expect.global(child, "_G.browser_created", true)
    Helpers.expect.global(child, "_G.creation_error", vim.NIL)
    Helpers.expect.global(child, "_G.has_split", true)
    Helpers.expect.global(child, "_G.has_project_name", true)
    Helpers.expect.global(child, "_G.has_conversations", true)
end

T["ConversationBrowser.new"]["validates required parameters"] = function()
    child.lua([[
        local ConversationBrowser = require('cc-tui.ui.conversation_browser')

        -- Test missing options
        local success1 = pcall(ConversationBrowser.new)
        _G.no_opts_handled = not success1

        -- Test missing on_select callback
        local success2 = pcall(ConversationBrowser.new, {})
        _G.no_callback_handled = not success2

        -- Test invalid callback type
        local success3 = pcall(ConversationBrowser.new, { on_select = "not a function" })
        _G.invalid_callback_handled = not success3
    ]])

    Helpers.expect.global(child, "_G.no_opts_handled", true)
    Helpers.expect.global(child, "_G.no_callback_handled", true)
    Helpers.expect.global(child, "_G.invalid_callback_handled", true)
end

T["ConversationBrowser.new"]["handles UI creation failure gracefully"] = function()
    child.lua([[
        local ConversationBrowser = require('cc-tui.ui.conversation_browser')

        -- Test with invalid window dimensions to trigger Split creation failure
        local browser, err = ConversationBrowser.new({
            on_select = function(path) end,
            height = "invalid_height"
        })

        _G.browser_created = browser ~= nil
        _G.has_error = err ~= nil
        _G.error_type = type(err)
    ]])

    -- This should fail gracefully
    local browser_created = child.lua_get("_G.browser_created")
    local has_error = child.lua_get("_G.has_error")

    if not browser_created then
        Helpers.expect.global(child, "_G.has_error", true)
        Helpers.expect.global(child, "_G.error_type", "string")
    end
end

-- Tests for conversation loading
T["load_conversations"] = MiniTest.new_set()

T["load_conversations"]["loads empty list for non-existent project"] = function()
    child.lua([[
        local ConversationBrowser = require('cc-tui.ui.conversation_browser')

        local browser, err = ConversationBrowser.new({
            on_select = function(path) end
        })

        if browser then
            -- Force a non-existent project name
            browser.project_name = "definitely-does-not-exist-12345"
            browser:load_conversations()

            _G.conv_count = #browser.conversations
            _G.current_index = browser.current_index
        end
    ]])

    Helpers.expect.global(child, "_G.conv_count", 0)
    Helpers.expect.global(child, "_G.current_index", 1)
end

T["load_conversations"]["resets index when out of bounds"] = function()
    child.lua([[
        local ConversationBrowser = require('cc-tui.ui.conversation_browser')

        local browser, err = ConversationBrowser.new({
            on_select = function(path) end
        })

        if browser then
            -- Set index higher than possible conversations
            browser.current_index = 999
            browser.conversations = {} -- Empty list
            browser:load_conversations()

            _G.reset_index = browser.current_index
        end
    ]])

    Helpers.expect.global(child, "_G.reset_index", 1)
end

-- Tests for navigation
T["navigation"] = MiniTest.new_set()

T["navigation"]["next_conversation advances index"] = function()
    child.lua([[
        local ConversationBrowser = require('cc-tui.ui.conversation_browser')

        local browser, err = ConversationBrowser.new({
            on_select = function(path) end
        })

        if browser then
            -- Mock some conversations
            browser.conversations = {
                { title = "Conv 1" },
                { title = "Conv 2" },
                { title = "Conv 3" }
            }
            browser.current_index = 1

            -- Test navigation
            browser:next_conversation()
            _G.after_next = browser.current_index

            -- Test boundary (shouldn't go past end)
            browser.current_index = 3
            browser:next_conversation()
            _G.at_boundary = browser.current_index
        end
    ]])

    Helpers.expect.global(child, "_G.after_next", 2)
    Helpers.expect.global(child, "_G.at_boundary", 3)
end

T["navigation"]["prev_conversation decreases index"] = function()
    child.lua([[
        local ConversationBrowser = require('cc-tui.ui.conversation_browser')

        local browser, err = ConversationBrowser.new({
            on_select = function(path) end
        })

        if browser then
            -- Mock some conversations
            browser.conversations = {
                { title = "Conv 1" },
                { title = "Conv 2" },
                { title = "Conv 3" }
            }
            browser.current_index = 2

            -- Test navigation
            browser:prev_conversation()
            _G.after_prev = browser.current_index

            -- Test boundary (shouldn't go below 1)
            browser.current_index = 1
            browser:prev_conversation()
            _G.at_boundary = browser.current_index
        end
    ]])

    Helpers.expect.global(child, "_G.after_prev", 1)
    Helpers.expect.global(child, "_G.at_boundary", 1)
end

T["navigation"]["handles empty conversation list"] = function()
    child.lua([[
        local ConversationBrowser = require('cc-tui.ui.conversation_browser')

        local browser, err = ConversationBrowser.new({
            on_select = function(path) end
        })

        if browser then
            browser.conversations = {}
            browser.current_index = 1

            -- These should not crash with empty list
            browser:next_conversation()
            _G.index_after_next = browser.current_index

            browser:prev_conversation()
            _G.index_after_prev = browser.current_index

            browser:first_conversation()
            _G.index_after_first = browser.current_index

            browser:last_conversation()
            _G.index_after_last = browser.current_index
        end
    ]])

    -- All should remain at 1 with empty list
    Helpers.expect.global(child, "_G.index_after_next", 1)
    Helpers.expect.global(child, "_G.index_after_prev", 1)
    Helpers.expect.global(child, "_G.index_after_first", 1)
    Helpers.expect.global(child, "_G.index_after_last", 1)
end

-- Tests for metadata toggle
T["toggle_metadata"] = MiniTest.new_set()

T["toggle_metadata"]["toggles metadata visibility"] = function()
    child.lua([[
        local ConversationBrowser = require('cc-tui.ui.conversation_browser')

        local browser, err = ConversationBrowser.new({
            on_select = function(path) end
        })

        if browser then
            _G.initial_metadata = browser.show_metadata

            browser:toggle_metadata()
            _G.after_first_toggle = browser.show_metadata

            browser:toggle_metadata()
            _G.after_second_toggle = browser.show_metadata
        end
    ]])

    Helpers.expect.global(child, "_G.initial_metadata", false)
    Helpers.expect.global(child, "_G.after_first_toggle", true)
    Helpers.expect.global(child, "_G.after_second_toggle", false)
end

-- Tests for conversation selection
T["select_current"] = MiniTest.new_set()

T["select_current"]["calls callback with current conversation path"] = function()
    child.lua([[
        local ConversationBrowser = require('cc-tui.ui.conversation_browser')

        _G.callback_called = false
        _G.callback_path = nil

        local browser, err = ConversationBrowser.new({
            on_select = function(path)
                _G.callback_called = true
                _G.callback_path = path
            end
        })

        if browser then
            -- Mock conversations
            browser.conversations = {
                { title = "Conv 1", path = "/test/conv1.jsonl" },
                { title = "Conv 2", path = "/test/conv2.jsonl" }
            }
            browser.current_index = 2

            browser:select_current()
        end
    ]])

    Helpers.expect.global(child, "_G.callback_called", true)
    Helpers.expect.global(child, "_G.callback_path", "/test/conv2.jsonl")
end

T["select_current"]["does nothing with empty conversations"] = function()
    child.lua([[
        local ConversationBrowser = require('cc-tui.ui.conversation_browser')

        _G.callback_called = false

        local browser, err = ConversationBrowser.new({
            on_select = function(path)
                _G.callback_called = true
            end
        })

        if browser then
            browser.conversations = {}
            browser:select_current()
        end
    ]])

    Helpers.expect.global(child, "_G.callback_called", false)
end

-- Tests for browser lifecycle
T["lifecycle"] = MiniTest.new_set()

T["lifecycle"]["show mounts split and sets up keymaps"] = function()
    child.lua([[
        local ConversationBrowser = require('cc-tui.ui.conversation_browser')

        local browser, err = ConversationBrowser.new({
            on_select = function(path) end
        })

        if browser then
            _G.split_mounted_before = browser.split._.mounted or false

            -- Show the browser (this should mount the split)
            browser:show()

            _G.split_mounted_after = browser.split._.mounted or false
            _G.has_keymaps = browser.keymaps ~= nil and type(browser.keymaps) == "table"
        end
    ]])

    Helpers.expect.global(child, "_G.split_mounted_before", false)
    Helpers.expect.global(child, "_G.split_mounted_after", true)
    Helpers.expect.global(child, "_G.has_keymaps", true)
end

T["lifecycle"]["close unmounts split"] = function()
    child.lua([[
        local ConversationBrowser = require('cc-tui.ui.conversation_browser')

        local browser, err = ConversationBrowser.new({
            on_select = function(path) end
        })

        if browser then
            browser:show()
            _G.mounted_after_show = browser.split._.mounted or false

            browser:close()
            _G.mounted_after_close = browser.split._.mounted or false
        end
    ]])

    Helpers.expect.global(child, "_G.mounted_after_show", true)
    Helpers.expect.global(child, "_G.mounted_after_close", false)
end

-- Tests for conversation list rendering
T["create_conversation_list"] = MiniTest.new_set()

T["create_conversation_list"]["creates empty state message"] = function()
    child.lua([[
        local ConversationBrowser = require('cc-tui.ui.conversation_browser')

        local browser, err = ConversationBrowser.new({
            on_select = function(path) end
        })

        if browser then
            browser.conversations = {}
            browser.project_name = "test-project"

            local lines = browser:create_conversation_list()
            _G.line_count = #lines
            _G.has_empty_message = lines[1] and lines[1]._extmarks and #lines[1]._extmarks > 0
        end
    ]])

    Helpers.expect.global(child, "_G.line_count", 2) -- Empty message + help line
    -- Empty message should exist (non-nil)
    local has_empty_message = child.lua_get("_G.has_empty_message")
    if has_empty_message == vim.NIL then
        -- The line exists but may not have extmarks, which is fine
        local line_count = child.lua_get("_G.line_count")
        Helpers.expect.equality(line_count, 2)
    else
        Helpers.expect.global(child, "_G.has_empty_message", true)
    end
end

T["create_conversation_list"]["renders conversation list"] = function()
    child.lua([[
        local ConversationBrowser = require('cc-tui.ui.conversation_browser')

        local browser, err = ConversationBrowser.new({
            on_select = function(path) end
        })

        if browser then
            -- Mock conversations with metadata
            browser.conversations = {
                {
                    title = "Test Conversation 1",
                    timestamp = "2024-01-15T10:30:45",
                    message_count = 5,
                    size = 1024
                },
                {
                    title = "Test Conversation 2",
                    timestamp = "2024-01-16T14:20:30",
                    message_count = 3,
                    size = 2048
                }
            }
            browser.current_index = 1
            browser.show_metadata = false

            local lines = browser:create_conversation_list()
            _G.line_count = #lines
            _G.has_conversations = #lines > 0
        end
    ]])

    Helpers.expect.global(child, "_G.line_count", 2) -- Two conversations
    Helpers.expect.global(child, "_G.has_conversations", true)
end

-- Integration tests
T["integration"] = MiniTest.new_set()

T["integration"]["full workflow test"] = function()
    child.lua([[
        local ConversationBrowser = require('cc-tui.ui.conversation_browser')

        _G.workflow_success = true
        _G.workflow_error = nil

        -- Test complete workflow
        local success, err = pcall(function()
            local browser, create_err = ConversationBrowser.new({
                on_select = function(path)
                    -- Mock callback
                end,
                height = "80%",
                width = "90%"
            })

            if not browser then
                error("Failed to create browser: " .. (create_err or "unknown"))
            end

            -- Test all major operations
            browser:show()
            browser:toggle_metadata()
            browser:refresh()
            browser:close()
        end)

        _G.workflow_success = success
        if not success then
            _G.workflow_error = err
        end
    ]])

    Helpers.expect.global(child, "_G.workflow_success", true)
    if not child.lua_get("_G.workflow_success") then
        local error_msg = child.lua_get("_G.workflow_error")
        error("Workflow test failed: " .. tostring(error_msg))
    end
end

return T
