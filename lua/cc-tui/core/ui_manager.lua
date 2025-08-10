---@brief [[
--- UI Management and Window Operations
--- Extracted from main.lua for better separation of concerns
--- Handles popup creation, tree rendering, and UI lifecycle
---@brief ]]

local Parser = require("cc-tui.parser.stream")
local Popup = require("nui.popup")
local Tree = require("cc-tui.ui.tree")
local log = require("cc-tui.util.log")
local state = require("cc-tui.state")

---@class CcTui.Core.UIManager
local M = {}

---@class CcTui.UIState
---@field popup NuiPopup? Main popup window
---@field tree NuiTree? Active tree component

---Internal UI state
---@type CcTui.UIState
local ui_state = {
    popup = nil,
    tree = nil,
}

---Initialize UI with tree data
---@param tree_data CcTui.BaseNode Root tree node
---@param messages? CcTui.Message[] Optional messages for session info
---@return boolean success True if UI initialized successfully
function M.initialize(tree_data, messages)
    vim.validate({
        tree_data = { tree_data, "table" },
        messages = { messages, "table", true },
    })

    -- Setup highlights first
    Tree.setup_highlights()

    -- Create main popup window
    local session_info = messages and Parser.get_session_info(messages)
    local title = session_info and session_info.model and (" CC-TUI [" .. session_info.model .. "] ") or " CC-TUI "

    ui_state.popup = Popup({
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
            wrap = true,
            linebreak = true,
            breakindent = true,
            breakindentopt = "shift:2",
        },
    })

    -- Mount the popup
    local success = pcall(function()
        ui_state.popup:mount()
    end)

    if not success then
        log.debug("ui_manager", "Failed to mount popup window")
        return false
    end

    -- Create tree with the popup's buffer
    ui_state.tree = Tree.create_tree(tree_data, {
        icons = {
            expanded = "▼",
            collapsed = "▶",
            empty = " ",
        },
    }, ui_state.popup.bufnr)

    -- Render tree in popup buffer
    ui_state.tree:render()

    -- Setup tree keybindings
    M.setup_keybindings()

    -- Store popup reference in state for compatibility
    state:set_ui_component(ui_state.popup)

    -- Save state
    state:save()

    log.debug("ui_manager", "UI initialized successfully")
    return true
end

---Setup keybindings for tree and popup
---@param on_close? function Optional close callback
---@return nil
function M.setup_keybindings(on_close)
    if not ui_state.popup or not ui_state.tree then
        return
    end

    -- Setup tree keybindings using Tree module
    local tree_config = {
        keymaps = {
            toggle = { "<Tab>", "<CR>" },
            close = { "q", "<Esc>" },
            expand_all = "E",
            collapse_all = "C",
            focus_next = { "j", "<Down>" },
            focus_prev = { "k", "<Up>" },
            copy_text = "y",
            close_content = "x",
            close_all_content = "X",
            search = "/",
            help = "?",
        },
        icons = {
            expanded = "▼",
            collapsed = "▶",
            empty = " ",
        },
        colors = {
            session = "CcTuiSession",
            message = "CcTuiMessage",
            tool = "CcTuiTool",
            result = "CcTuiResult",
            text = "CcTuiText",
            error = "CcTuiError",
        },
    }

    Tree.setup_keybindings(ui_state.tree, ui_state.popup.bufnr, tree_config)

    -- Add close window handlers
    local close_handler = on_close or function()
        M.cleanup()
    end

    vim.keymap.set("n", "q", close_handler, {
        buffer = ui_state.popup.bufnr,
        desc = "Close CC-TUI window",
        nowait = true,
    })

    vim.keymap.set("n", "<Esc>", close_handler, {
        buffer = ui_state.popup.bufnr,
        desc = "Close CC-TUI window",
        nowait = true,
    })
end

---Update UI with new data (conversation switch, refresh, etc.)
---@param tree_data CcTui.BaseNode New tree data
---@param messages? CcTui.Message[] Optional messages for title update
---@param conversation_path? string Optional path for title
---@return boolean success True if update succeeded
function M.update(tree_data, messages, conversation_path)
    vim.validate({
        tree_data = { tree_data, "table" },
        messages = { messages, "table", true },
        conversation_path = { conversation_path, "string", true },
    })

    if not ui_state.popup or not ui_state.tree then
        log.debug("ui_manager", "Cannot update UI - not initialized")
        return false
    end

    -- Update title if conversation path provided
    if conversation_path then
        local conv_name = vim.fn.fnamemodify(conversation_path, ":t:r")
        local title = string.format(" CC-TUI [%s] ", conv_name)
        ui_state.popup.border:set_text("top", title, "center")
    end

    -- Recreate tree with new data
    ui_state.tree = Tree.create_tree(tree_data, {
        icons = {
            expanded = "▼",
            collapsed = "▶",
            empty = " ",
        },
    }, ui_state.popup.bufnr)

    -- Re-render
    ui_state.tree:render()

    -- Re-setup keybindings
    M.setup_keybindings()

    return true
end

---Cleanup UI components
---@return nil
function M.cleanup()
    -- Close popup
    if ui_state.popup then
        ui_state.popup:unmount()
        ui_state.popup = nil
    end

    -- Clean up tree
    if ui_state.tree then
        -- Tree cleanup is handled by popup unmount
        ui_state.tree = nil
    end

    -- Clear state reference
    state:set_ui_component(nil)

    log.debug("ui_manager", "UI cleanup completed")
end

---Get current UI state
---@return CcTui.UIState ui_state Current UI state
function M.get_state()
    return {
        popup = ui_state.popup,
        tree = ui_state.tree,
    }
end

---Check if UI is currently active
---@return boolean active True if UI components exist
function M.is_active()
    return ui_state.popup ~= nil and ui_state.tree ~= nil
end

---Refresh/re-render current UI
---@return boolean success True if refresh succeeded
function M.refresh()
    if not ui_state.tree then
        return false
    end

    ui_state.tree:render()
    return true
end

return M
