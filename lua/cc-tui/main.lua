---@brief [[
--- Main module for CC-TUI
--- Manages the plugin's core functionality and UI state
---@brief ]]

local Keymaps = require("cc-tui.keymaps")
local Parser = require("cc-tui.parser.stream")
local Popup = require("nui.popup")
local TestData = require("cc-tui.parser.test_data")
local Tree = require("cc-tui.ui.tree")
local TreeBuilder = require("cc-tui.models.tree_builder")
local log = require("cc-tui.util.log")
local state = require("cc-tui.state")

---@class CcTui.Main
local M = {}

---@class CcTui.MainState
---@field popup NuiPopup? Main popup window
---@field tree NuiTree? Active tree component
---@field tree_data CcTui.BaseNode? Tree data structure
---@field messages CcTui.Message[] Parsed messages

---Internal state
---@type CcTui.MainState
local main_state = {
    popup = nil,
    tree = nil,
    tree_data = nil,
    messages = {},
}

---Toggle the plugin by calling the `enable`/`disable` methods respectively.
---@param scope string Internal identifier for logging purposes
---@private
function M.toggle(scope)
    vim.validate({
        scope = { scope, "string" },
    })

    if state:get_enabled() then
        log.debug(scope, "cc-tui is now disabled!")
        return M.disable(scope)
    end

    log.debug(scope, "cc-tui is now enabled!")
    M.enable(scope)
end

---Load and parse test data
---@return CcTui.BaseNode? root Root node or nil
---@return string? error Error message if failed
local function load_test_data()
    -- Load sample lines
    local lines = TestData.load_sample_lines(500)
    if #lines == 0 then
        return nil, "Failed to load test data"
    end

    -- Parse lines
    local messages, errors = Parser.parse_lines(lines)
    if #errors > 0 then
        log.debug("main", string.format("Parse errors: %s", table.concat(errors, ", ")))
    end

    -- Store messages
    main_state.messages = messages

    -- Get session info
    local session_info = Parser.get_session_info(messages)

    -- Build tree
    local root = TreeBuilder.build_tree(messages, session_info)

    return root, nil
end

---Initialize the plugin, sets event listeners and internal state
---@param scope string Internal identifier for logging purposes
---@private
function M.enable(scope)
    vim.validate({
        scope = { scope, "string" },
    })

    if state:get_enabled() then
        log.debug(scope, "cc-tui is already enabled")
        return
    end

    state:set_enabled()

    -- Load test data
    local root, err = load_test_data()
    if not root then
        log.debug("main", "Failed to load test data: " .. (err or "unknown error"))
        vim.notify("CC-TUI: Failed to load test data", vim.log.levels.ERROR)
        state:set_disabled()
        return
    end

    main_state.tree_data = root

    -- Setup highlights
    Tree.setup_highlights()

    -- Create main popup window
    local session_info = Parser.get_session_info(main_state.messages)
    local title = session_info and session_info.model and (" CC-TUI [" .. session_info.model .. "] ") or " CC-TUI "

    main_state.popup = Popup({
        relative = "editor",
        position = "50%",
        size = {
            width = "90%",
            height = "90%",
        },
        enter = true,
        focusable = true,
        border = {
            style = "rounded",
            text = {
                top = title,
                top_align = "center",
            },
        },
        buf_options = {
            modifiable = false,
            readonly = true,
            filetype = "cc-tui",
        },
        win_options = {
            cursorline = true,
            number = false,
            relativenumber = false,
            signcolumn = "no",
            wrap = false,
        },
    })

    -- Mount the popup
    main_state.popup:mount()

    -- Create tree with the popup's buffer
    main_state.tree = Tree.create_tree(root, {
        icons = {
            expanded = "▼",
            collapsed = "▶",
            empty = " ",
        },
    })

    -- Set the tree's buffer to our popup buffer
    main_state.tree.bufnr = main_state.popup.bufnr

    -- Render tree in popup buffer
    main_state.tree:render()

    -- Setup tree keybindings
    local tree_handlers = {
        toggle_node = function()
            local node = main_state.tree:get_node()
            if node and node:has_children() then
                if node:is_expanded() then
                    node:collapse()
                else
                    node:expand()
                end
                main_state.tree:render()
            end
        end,
        close_window = function()
            M.disable("keymap_close")
        end,
        expand_all = function()
            for _, node in pairs(main_state.tree.nodes.by_id) do
                if node:has_children() then
                    node:expand()
                end
            end
            main_state.tree:render()
        end,
        collapse_all = function()
            for _, node in pairs(main_state.tree.nodes.by_id) do
                if node:has_children() and node:get_depth() > 0 then
                    node:collapse()
                end
            end
            main_state.tree:render()
        end,
        next_node = function()
            vim.cmd("normal! j")
        end,
        prev_node = function()
            vim.cmd("normal! k")
        end,
        copy_text = function()
            local node = Tree.get_focused_node(main_state.tree)
            if node and node.text then
                vim.fn.setreg("+", node.text)
                vim.notify("Copied to clipboard", vim.log.levels.INFO)
            end
        end,
        refresh = function()
            M.refresh()
        end,
        help = function()
            Keymaps.show_help("tree")
        end,
        -- Add missing handlers for keymap compatibility
        parent_node = function()
            vim.cmd("normal! h")
        end,
        child_node = function()
            vim.cmd("normal! l")
        end,
        first_sibling = function()
            vim.cmd("normal! ^")
        end,
        last_sibling = function()
            vim.cmd("normal! $")
        end,
        copy_all = function()
            -- Copy entire tree content
            vim.cmd("normal! ggyG")
        end,
        search = function()
            vim.cmd("normal! /")
        end,
        next_match = function()
            vim.cmd("normal! n")
        end,
        prev_match = function()
            vim.cmd("normal! N")
        end,
    }

    -- Get keymap config
    local keymap_config = Keymaps.get_config()

    -- Setup buffer keymaps
    Keymaps.setup_tree_buffer(main_state.popup.bufnr, keymap_config.tree, tree_handlers)

    -- Store popup reference in state for compatibility
    state:set_ui_component(main_state.popup)

    -- Save state
    state:save()

    log.debug("main", "CC-TUI enabled successfully")
end

---Disable the plugin, clear highlight groups and autocmds, closes windows and resets state
---@param scope string Internal identifier for logging purposes
---@private
function M.disable(scope)
    vim.validate({
        scope = { scope, "string" },
    })

    if not state:get_enabled() then
        log.debug(scope, "cc-tui is already disabled")
        return
    end

    -- Close popup
    if main_state.popup then
        main_state.popup:unmount()
        main_state.popup = nil
    end

    -- Clear tree and data
    main_state.tree = nil
    main_state.tree_data = nil
    main_state.messages = {}

    state:set_disabled()

    -- Save state
    state:save()

    log.debug("main", "CC-TUI disabled")

    return true, nil
end

---Refresh the tree with new data
---@return nil
function M.refresh()
    if not state:get_enabled() then
        log.debug("main", "Cannot refresh: plugin disabled")
        return
    end

    log.debug("main", "Refreshing tree...")

    -- Reload test data
    local root, err = load_test_data()
    if not root then
        log.debug("main", "Failed to reload test data: " .. (err or "unknown error"))
        vim.notify("CC-TUI: Failed to reload test data", vim.log.levels.ERROR)
        return
    end

    main_state.tree_data = root

    -- Update tree
    if main_state.tree then
        Tree.update_tree(main_state.tree, root, {
            icons = {
                expanded = "▼",
                collapsed = "▶",
                empty = " ",
            },
        })
    end

    log.debug("main", "Tree refreshed")
    vim.notify("CC-TUI: Tree refreshed", vim.log.levels.INFO)
end

---Process a new JSONL line (for streaming support)
---@param line string JSONL line to process
---@return nil
function M.process_line(line)
    vim.validate({
        line = { line, "string" },
    })

    if not state:get_enabled() then
        log.debug("main", "Cannot process line: plugin disabled")
        return
    end

    -- Parse the line
    local msg, err = Parser.parse_line(line)
    if not msg then
        log.debug("main", "Failed to parse line: " .. (err or "unknown error"))
        return
    end

    -- Add to messages
    table.insert(main_state.messages, msg)

    -- Rebuild tree
    local session_info = Parser.get_session_info(main_state.messages)
    local root = TreeBuilder.build_tree(main_state.messages, session_info)
    main_state.tree_data = root

    -- Update tree display
    if main_state.tree then
        Tree.update_tree(main_state.tree, root, {
            icons = {
                expanded = "▼",
                collapsed = "▶",
                empty = " ",
            },
        })
    end

    log.debug("main", string.format("Processed message type: %s", msg.type))
end

---Get current state for debugging
---@return CcTui.MainState state
function M.get_state()
    return main_state
end

return M
