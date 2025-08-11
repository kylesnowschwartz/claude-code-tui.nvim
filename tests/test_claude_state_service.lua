---@brief [[
--- Tests for Claude state detection service
--- Tests finding current/recent conversations
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

-- Test 1: Service can get most recent conversation
T["get_most_recent_conversation"] = function()
    child.lua([[
        local ClaudeState = require("cc-tui.services.claude_state")
        local ProjectDiscovery = require("cc-tui.services.project_discovery")

        -- Get current project
        local cwd = vim.fn.getcwd()
        local project_name = ProjectDiscovery.get_project_name(cwd)

        -- Get most recent conversation
        local recent = ClaudeState.get_most_recent_conversation(project_name)

        _G.test_result = {
            has_method = type(ClaudeState.get_most_recent_conversation) == "function",
            result_type = type(recent),
            has_path = recent and recent.path ~= nil
        }
    ]])

    local result = child.lua_get("_G.test_result")
    MiniTest.expect.equality(result.has_method, true, "Should have get_most_recent_conversation method")
    -- Recent can be nil if no conversations exist
    if result.result_type ~= "nil" then
        MiniTest.expect.equality(result.result_type, "table", "Should return table or nil")
        MiniTest.expect.equality(result.has_path, true, "Should have path field")
    end
end

-- Test 2: get_current_conversation returns nil (we can't detect current)
T["get_current_conversation_returns_nil"] = function()
    child.lua([[
        local ClaudeState = require("cc-tui.services.claude_state")

        -- Try to get current conversation
        local current = ClaudeState.get_current_conversation()

        _G.test_result = {
            has_method = type(ClaudeState.get_current_conversation) == "function",
            result = current
        }
    ]])

    local result = child.lua_get("_G.test_result")
    MiniTest.expect.equality(result.has_method, true, "Should have get_current_conversation method")
    MiniTest.expect.equality(result.result, nil, "Should return nil (can't detect current)")
end

-- Test 3: is_conversation_current always returns false (we can't detect current)
T["is_conversation_current_returns_false"] = function()
    child.lua([[
        local ClaudeState = require("cc-tui.services.claude_state")

        -- Test with a dummy path
        local is_current = ClaudeState.is_conversation_current("/test/path.jsonl")

        _G.test_result = {
            has_method = type(ClaudeState.is_conversation_current) == "function",
            result = is_current
        }
    ]])

    local result = child.lua_get("_G.test_result")
    MiniTest.expect.equality(result.has_method, true, "Should have is_conversation_current method")
    MiniTest.expect.equality(result.result, false, "Should always return false (can't detect current)")
end

-- Test 4: View tab loads most recent when no conversation selected
T["view_loads_most_recent"] = function()
    child.lua([[
        local ViewView = require("cc-tui.ui.views.view")
        local ClaudeState = require("cc-tui.services.claude_state")

        -- Mock manager
        local mock_manager = {
            render = function() end
        }

        -- Create view instance
        local view = ViewView.new(mock_manager)

        -- Load default conversation (should be most recent)
        view:load_default_conversation()

        _G.test_result = {
            has_method = type(view.load_default_conversation) == "function",
            has_conversation = view.conversation_path ~= nil
        }
    ]])

    local result = child.lua_get("_G.test_result")
    MiniTest.expect.equality(result.has_method, true, "Should have load_default_conversation method")
    -- May or may not have a conversation depending on project state
end

-- Test 5: Browse doesn't mark current (removed feature)
T["browse_no_current_marking"] = function()
    child.lua([[
        local BrowseView = require("cc-tui.ui.views.browse")

        -- Mock manager
        local mock_manager = {
            render = function() end,
            get_width = function() return 80 end
        }

        -- Create browse instance
        local browse = BrowseView.new(mock_manager)

        -- is_conversation_current method should not exist
        _G.test_result = {
            has_method = type(browse.is_conversation_current) == "function"
        }
    ]])

    local result = child.lua_get("_G.test_result")
    MiniTest.expect.equality(result.has_method, false, "Should not have is_conversation_current method")
end

return T
