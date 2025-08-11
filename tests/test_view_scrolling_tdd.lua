local MiniTest = require("mini.test")
local child = MiniTest.new_child_neovim()

-- Helper for test setup
local setup_plugin = function()
    child.restart({ "-u", "scripts/minimal_init.lua" })
    -- Load plugin
    child.lua([[
        require('cc-tui').setup({ debug = false })
        _G.test_data = {}
    ]])
end

local T = MiniTest.new_set({
    hooks = {
        pre_case = setup_plugin,
        post_once = child.stop,
    },
})

T["Tree scrolling behavior"] = MiniTest.new_set()

T["Tree scrolling behavior"]["cursor moves with j/k navigation"] = function()
    -- Setup: Create view with test conversation data
    child.lua([[
        local ViewView = require("cc-tui.ui.views.view")
        local TabbedManager = require("cc-tui.ui.tabbed_manager")

        -- Mock manager
        local manager = {
            window = vim.api.nvim_get_current_win(),
            buffer = vim.api.nvim_get_current_buf(),
            current_tab = "view",
            render = function() end,
            get_width = function() return 80 end
        }

        _G.test_view = ViewView.new(manager)

        -- Mock tree data with multiple items for scrolling
        local Node = require("cc-tui.models.node")
        local root = Node.create_session_node("test-session")

        -- Create 20 message nodes to test scrolling
        for i = 1, 20 do
            local msg = Node.create_message_node("msg-" .. i, "assistant", "Message " .. i)
            table.insert(root.children, msg)
        end

        _G.test_view.tree_data = root
        _G.test_view.selected_index = 1
        _G.test_view.expanded_nodes = {}

        -- Expand the root session node to show all message children
        _G.test_view.expanded_nodes[root.id] = true

        -- Store root info for test verification
        _G.test_data.root_id = root.id
    ]])

    -- Test: Navigation should update cursor position using native j keys
    child.lua([[
        -- Render the tree content to the buffer first
        local lines = _G.test_view:render(25)
        local buffer_lines = {}
        for _, line in ipairs(lines) do
            if type(line) == 'table' and line.render then
                -- Create a simple string representation of the NuiLine
                table.insert(buffer_lines, tostring(line))
            else
                table.insert(buffer_lines, tostring(line))
            end
        end

        vim.api.nvim_buf_set_lines(_G.test_view.manager.buffer, 0, -1, false, buffer_lines)

        -- Re-expand after render (which may have reset expanded state)
        _G.test_view.expanded_nodes[_G.test_data.root_id] = true

        -- Start at top (line 3 to be on first tree item after header)
        vim.api.nvim_win_set_cursor(_G.test_view.manager.window, {3, 0})
        local initial_pos = vim.api.nvim_win_get_cursor(_G.test_view.manager.window)
        _G.test_data.initial_line = initial_pos[1]
        _G.test_data.initial_selected = _G.test_view.selected_index

        -- Navigate down 5 items using native j key
        for i = 1, 5 do
            vim.api.nvim_feedkeys("j", "n", false)
            vim.api.nvim_feedkeys("", "x", false)  -- Process key
            -- Trigger cursor move handler manually for test
            local pos = vim.api.nvim_win_get_cursor(_G.test_view.manager.window)
            _G.test_view:handle_cursor_move()
        end

        local after_nav_pos = vim.api.nvim_win_get_cursor(_G.test_view.manager.window)
        _G.test_data.after_nav_line = after_nav_pos[1]
        _G.test_data.selected_index = _G.test_view.selected_index
    ]])

    -- Verify: Cursor position changed and selected_index updated
    local initial_line = child.lua_get("_G.test_data.initial_line")
    local after_nav_line = child.lua_get("_G.test_data.after_nav_line")
    local selected_index = child.lua_get("_G.test_data.selected_index")

    -- Selected index should be 6 (started at 1, moved 5 times)
    MiniTest.expect.equality(selected_index, 6)

    -- Cursor should have moved from initial position
    MiniTest.expect.no_equality(initial_line, after_nav_line)

    -- Cursor line should be ahead of initial position
    MiniTest.expect.equality(after_nav_line > initial_line, true)
end

T["Tree scrolling behavior"]["cursor stays in view during navigation"] = function()
    -- Setup: Create large tree that requires scrolling
    child.lua([[
        local ViewView = require("cc-tui.ui.views.view")
        local TabbedManager = require("cc-tui.ui.tabbed_manager")

        local manager = {
            window = vim.api.nvim_get_current_win(),
            buffer = vim.api.nvim_get_current_buf(),
            current_tab = "view",
            render = function() end,
            get_width = function() return 80 end
        }

        _G.test_view = ViewView.new(manager)

        local Node = require("cc-tui.models.node")
        local root = Node.create_session_node("test-session")

        -- Create 50 message nodes to force scrolling
        for i = 1, 50 do
            local msg = Node.create_message_node("msg-" .. i, "assistant", "Message " .. i)
            table.insert(root.children, msg)
        end

        _G.test_view.tree_data = root
        _G.test_view.selected_index = 1
        _G.test_view.expanded_nodes = {}

        -- Expand the root session node to show all message children
        _G.test_view.expanded_nodes[root.id] = true

        -- Get window height to understand viewport
        _G.test_data.win_height = vim.api.nvim_win_get_height(_G.test_view.manager.window)
    ]])

    -- Test: Navigate beyond visible area using native navigation
    child.lua([[
        -- Render the large tree content to the buffer
        local lines = _G.test_view:render(60) -- Large enough for 50 items
        local buffer_lines = {}
        for _, line in ipairs(lines) do
            table.insert(buffer_lines, tostring(line))
        end

        vim.api.nvim_buf_set_lines(_G.test_view.manager.buffer, 0, -1, false, buffer_lines)

        -- Start at top (line 3 to be on first tree item)
        vim.api.nvim_win_set_cursor(_G.test_view.manager.window, {3, 0})

        local win_height = _G.test_data.win_height
        local navigate_count = math.min(win_height + 10, 30) -- Don't exceed buffer bounds

        -- Navigate down many items using native j
        for i = 1, navigate_count do
            vim.api.nvim_feedkeys("j", "n", false)
            vim.api.nvim_feedkeys("", "x", false)  -- Process key
            _G.test_view:handle_cursor_move()
        end

        local cursor_pos = vim.api.nvim_win_get_cursor(_G.test_view.manager.window)
        local topline = vim.fn.line('w0', _G.test_view.manager.window)
        local botline = vim.fn.line('w$', _G.test_view.manager.window)

        _G.test_data.cursor_line = cursor_pos[1]
        _G.test_data.topline = topline
        _G.test_data.botline = botline
        _G.test_data.cursor_visible = (cursor_pos[1] >= topline and cursor_pos[1] <= botline)
        _G.test_data.selected_index = _G.test_view.selected_index
    ]])

    local cursor_line = child.lua_get("_G.test_data.cursor_line")
    local topline = child.lua_get("_G.test_data.topline")
    local botline = child.lua_get("_G.test_data.botline")
    local cursor_visible = child.lua_get("_G.test_data.cursor_visible")
    local selected_index = child.lua_get("_G.test_data.selected_index")

    -- Cursor should still be visible in the viewport
    MiniTest.expect.equality(cursor_visible, true)

    -- Selected index should have moved significantly
    MiniTest.expect.equality(selected_index > 10, true)
end

T["Tree scrolling behavior"]["native j/k keys work in buffer"] = function()
    -- This test verifies that standard Neovim navigation works
    child.lua([[
        local ViewView = require("cc-tui.ui.views.view")

        local manager = {
            window = vim.api.nvim_get_current_win(),
            buffer = vim.api.nvim_get_current_buf(),
            current_tab = "view",
            render = function() end,
            get_width = function() return 80 end
        }

        _G.test_view = ViewView.new(manager)

        -- Render some content to the buffer
        local lines = {}
        for i = 1, 30 do
            table.insert(lines, "Line " .. i .. " content")
        end

        vim.api.nvim_buf_set_lines(_G.test_view.manager.buffer, 0, -1, false, lines)

        -- Start at top
        vim.api.nvim_win_set_cursor(_G.test_view.manager.window, {1, 0})
        _G.test_data.start_line = vim.api.nvim_win_get_cursor(_G.test_view.manager.window)[1]

        -- Use native Neovim j key
        vim.api.nvim_feedkeys("10j", "n", false)
        vim.api.nvim_feedkeys("", "x", false)  -- Process keys

        _G.test_data.end_line = vim.api.nvim_win_get_cursor(_G.test_view.manager.window)[1]
    ]])

    local start_line = child.lua_get("_G.test_data.start_line")
    local end_line = child.lua_get("_G.test_data.end_line")

    -- Native j should have moved cursor down 10 lines
    MiniTest.expect.equality(end_line, start_line + 10)
end

return T
