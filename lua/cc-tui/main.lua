local Popup = require("nui.popup")
local log = require("cc-tui.util.log")
local state = require("cc-tui.state")

---@class CcTui.Main
local M = {}

-- Toggle the plugin by calling the `enable`/`disable` methods respectively.
--
---@param scope string: internal identifier for logging purposes.
---@private
function M.toggle(scope)
    if state:get_enabled() then
        log.debug(scope, "cc-tui is now disabled!")

        return M.disable(scope)
    end

    log.debug(scope, "cc-tui is now enabled!")

    M.enable(scope)
end

--- Initializes the plugin, sets event listeners and internal state.
---
--- @param scope string: internal identifier for logging purposes.
---@private
function M.enable(scope)
    if state:get_enabled() then
        log.debug(scope, "cc-tui is already enabled")

        return
    end

    state:set_enabled()

    -- Create full screen popup
    local popup = Popup({
        relative = "editor",
        position = "50%",
        size = {
            width = "100%",
            height = "100%",
        },
        enter = true,
        focusable = true,
        border = {
            style = "rounded",
            text = {
                top = " CC-TUI Main ",
                top_align = "center",
            },
        },
        buf_options = {
            modifiable = true,
            readonly = false,
        },
    })

    -- Mount the popup
    popup:mount()

    -- Set initial content
    vim.api.nvim_buf_set_lines(popup.bufnr, 0, -1, false, {
        "CC-TUI Main Interface",
        "",
        "Welcome to CC-TUI!",
        "",
        "Press 'q' to close or use :CcTui to toggle.",
    })

    -- Set buffer name
    vim.api.nvim_buf_set_name(popup.bufnr, "[CC-TUI Main]")

    -- Add keymap to close with 'q'
    popup:map("n", "q", function()
        M.disable("keymap_q")
    end, { noremap = true })

    -- Store popup reference
    state:set_ui_component(popup)

    -- saves the state globally to `_G.CcTui.state`
    state:save()
end

--- Disables the plugin for the given tab, clear highlight groups and autocmds, closes side buffers and resets the internal state.
---
--- @param scope string: internal identifier for logging purposes.
---@private
function M.disable(scope)
    if not state:get_enabled() then
        log.debug(scope, "cc-tui is already disabled")

        return
    end

    -- Get the popup reference and unmount it
    local popup = state:get_ui_component()
    if popup then
        popup:unmount()
        state:set_ui_component(nil)
    end

    state:set_disabled()

    -- saves the state globally to `_G.CcTui.state`
    state:save()

    return true, nil
end

return M
