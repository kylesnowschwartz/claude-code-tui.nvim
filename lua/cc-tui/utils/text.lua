---@brief [[
--- Professional Text Utilities for CC-TUI
--- Implements MCPHub-style spacing, alignment, and layout functions
--- Provides consistent professional appearance across all views
---@brief ]]

local NuiLine = require("nui.line")

---@class CcTui.Utils.Text
local M = {}

-- MCPHub-inspired spacing constants
M.HORIZONTAL_PADDING = 2
M.DEFAULT_DIVIDER_CHAR = "─"

---Create professionally padded line with consistent spacing
---@param content string Text content to display
---@param highlight? string Optional highlight group
---@param padding? number Left padding (default: HORIZONTAL_PADDING)
---@return NuiLine line Padded line with professional spacing
function M.pad_line(content, highlight, padding)
    vim.validate({
        content = { content, "string" },
        highlight = { highlight, "string", true },
        padding = { padding, "number", true },
    })

    padding = padding or M.HORIZONTAL_PADDING
    highlight = highlight or "Normal"

    local line = NuiLine()
    line:append(string.rep(" ", padding))
    line:append(content, highlight)

    return line
end

---Create centered text with professional alignment
---@param text string Text to center
---@param width number Available width for centering
---@param highlight? string Optional highlight group
---@return NuiLine line Centered text line
function M.align_text(text, width, alignment, highlight)
    vim.validate({
        text = { text, "string" },
        width = { width, "number" },
        alignment = { alignment, "string", true },
        highlight = { highlight, "string", true },
    })

    alignment = alignment or "center"
    highlight = highlight or "Normal"

    local text_width = vim.api.nvim_strwidth(text)
    local line = NuiLine()

    if alignment == "center" then
        local padding = math.max(0, math.floor((width - text_width) / 2))
        line:append(string.rep(" ", padding))
        line:append(text, highlight)
    elseif alignment == "right" then
        local padding = math.max(0, width - text_width)
        line:append(string.rep(" ", padding))
        line:append(text, highlight)
    else -- left alignment
        line:append(text, highlight)
    end

    return line
end

---Create professional divider line with consistent styling
---@param width number Line width
---@param is_full? boolean Whether to use full width (default: true)
---@param char? string Divider character (default: DEFAULT_DIVIDER_CHAR)
---@param highlight? string Optional highlight group
---@return NuiLine line Professional divider line
function M.divider(width, is_full, char, highlight)
    vim.validate({
        width = { width, "number" },
        is_full = { is_full, "boolean", true },
        char = { char, "string", true },
        highlight = { highlight, "string", true },
    })

    is_full = is_full ~= false -- default to true
    char = char or M.DEFAULT_DIVIDER_CHAR
    highlight = highlight or "CcTuiMuted"

    local line = NuiLine()

    if is_full then
        line:append(string.rep(char, width), highlight)
    else
        -- Add padding for partial dividers
        line:append(string.rep(" ", M.HORIZONTAL_PADDING))
        local divider_width = width - (M.HORIZONTAL_PADDING * 2)
        line:append(string.rep(char, math.max(0, divider_width)), highlight)
    end

    return line
end

---Create empty line with consistent padding
---@param padding? number Optional padding (default: 0 for true empty line)
---@return NuiLine line Empty line with optional padding
function M.empty_line(padding)
    vim.validate({
        padding = { padding, "number", true },
    })

    local line = NuiLine()
    if padding and padding > 0 then
        line:append(string.rep(" ", padding))
    end

    return line
end

---Create professional button-style text (MCPHub pattern)
---@param label string Button label text
---@param shortcut string Keyboard shortcut key
---@param selected boolean Whether button is selected/active
---@param highlights table Highlight configuration table
---@return NuiLine line Professional button line
function M.create_button(label, shortcut, selected, highlights)
    vim.validate({
        label = { label, "string" },
        shortcut = { shortcut, "string" },
        selected = { selected, "boolean" },
        highlights = { highlights, "table" },
    })

    local line = NuiLine()

    if selected then
        line:append(" " .. shortcut, highlights.header_btn_shortcut or "CcTuiHeaderBtnShortcut")
        line:append(" " .. label .. " ", highlights.header_btn or "CcTuiHeaderBtn")
    else
        line:append(" " .. shortcut, highlights.header_shortcut or "CcTuiHeaderShortcut")
        line:append(" " .. label .. " ", highlights.header or "CcTuiHeader")
    end

    return line
end

---Create section header with professional styling
---@param title string Section title
---@param icon? string Optional icon/prefix
---@param highlight? string Optional highlight group
---@return NuiLine line Professional section header
function M.section_header(title, icon, highlight)
    vim.validate({
        title = { title, "string" },
        icon = { icon, "string", true },
        highlight = { highlight, "string", true },
    })

    highlight = highlight or "CcTuiTitle"
    local content = icon and (icon .. " " .. title) or title

    return M.pad_line(content, highlight)
end

---Truncate text professionally with ellipsis
---@param text string Text to truncate
---@param max_width number Maximum width
---@param ellipsis? string Ellipsis string (default: "...")
---@return string text Truncated text with ellipsis
function M.truncate_text(text, max_width, ellipsis)
    vim.validate({
        text = { text, "string" },
        max_width = { max_width, "number" },
        ellipsis = { ellipsis, "string", true },
    })

    ellipsis = ellipsis or "..."
    local text_width = vim.api.nvim_strwidth(text)

    if text_width <= max_width then
        return text
    end

    local ellipsis_width = vim.api.nvim_strwidth(ellipsis)
    local available_width = max_width - ellipsis_width

    if available_width <= 0 then
        return string.sub(ellipsis, 1, max_width)
    end

    -- Simple truncation - handles basic cases well
    return string.sub(text, 1, available_width) .. ellipsis
end

---Create action bar with professional styling
---@param actions table<string, string> Key-value pairs of actions {"key": "description"}
---@param width number Available width
---@param highlight? string Optional highlight group
---@return NuiLine line Professional action bar
function M.action_bar(actions, width, highlight)
    vim.validate({
        actions = { actions, "table" },
        width = { width, "number" },
        highlight = { highlight, "string", true },
    })

    highlight = highlight or "CcTuiMuted"
    local action_parts = {}

    for key, description in pairs(actions) do
        table.insert(action_parts, string.format("[%s] %s", key, description))
    end

    local content = table.concat(action_parts, "  ")
    content = M.truncate_text(content, width - (M.HORIZONTAL_PADDING * 2))

    return M.pad_line(content, highlight)
end

---Create status indicator with professional styling
---@param status string Status text
---@param state "active"|"inactive"|"success"|"error"|"warning" Status state
---@return table {text: string, highlight: string} Status indicator data
function M.status_indicator(status, state)
    vim.validate({
        status = { status, "string" },
        state = { state, "string" },
    })

    local indicators = {
        active = { text = "●", highlight = "CcTuiSuccess" },
        inactive = { text = "○", highlight = "CcTuiMuted" },
        success = { text = "✓", highlight = "CcTuiSuccess" },
        error = { text = "✗", highlight = "CcTuiError" },
        warning = { text = "⚠", highlight = "CcTuiWarn" },
    }

    local indicator = indicators[state] or indicators.inactive
    return {
        text = indicator.text .. " " .. status,
        highlight = indicator.highlight,
    }
end

---Create professional list item
---@param text string Item text
---@param index? number Optional item number
---@param status? "active"|"inactive"|"success"|"error"|"warning" Optional status
---@param highlight? string Optional base highlight group
---@return NuiLine line Professional list item line
function M.list_item(text, index, status, highlight)
    vim.validate({
        text = { text, "string" },
        index = { index, "number", true },
        status = { status, "string", true },
        highlight = { highlight, "string", true },
    })

    highlight = highlight or "CcTuiInfo"
    local line = NuiLine()
    line:append(string.rep(" ", M.HORIZONTAL_PADDING))

    -- Add index if provided
    if index then
        line:append(string.format("%d. ", index), "CcTuiMuted")
    end

    -- Add status indicator if provided
    if status then
        local indicator = M.status_indicator("", status)
        line:append(indicator.text .. " ", indicator.highlight)
    end

    -- Add main text
    line:append(text, highlight)

    return line
end

return M
