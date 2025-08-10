---@brief [[
--- Professional Highlight System for CC-TUI
--- Implements MCPHub-style theme integration and highlight groups
--- Auto-adapts to user's colorscheme with professional fallbacks
---@brief ]]

---@class CcTui.Utils.Highlights
local M = {}

-- Highlight group definitions following MCPHub patterns
M.highlight_groups = {
    -- Core interface highlights
    CcTuiTitle = { link = "Title", fallback = { fg = "#c792ea", bold = true } },
    CcTuiHeader = { link = "Directory", fallback = { fg = "#82aaff" } },
    CcTuiHeaderBtn = { link = "TabLineSel", fallback = { fg = "#1a1b26", bg = "#7aa2f7", bold = true } },
    CcTuiHeaderBtnShortcut = { link = "TabLineSel", fallback = { fg = "#1a1b26", bg = "#7aa2f7", bold = true } },
    CcTuiHeaderShortcut = { link = "TabLine", fallback = { fg = "#565f89" } },
    CcTuiMuted = { link = "Comment", fallback = { fg = "#565f89" } },

    -- State and status highlights
    CcTuiSuccess = { link = "DiagnosticOk", fallback = { fg = "#9ece6a" } },
    CcTuiInfo = { link = "DiagnosticInfo", fallback = { fg = "#0db9d7" } },
    CcTuiWarn = { link = "DiagnosticWarn", fallback = { fg = "#e0af68" } },
    CcTuiError = { link = "DiagnosticError", fallback = { fg = "#f44747" } },

    -- Tab interface highlights
    CcTuiTabActive = { link = "TabLineSel", fallback = { fg = "#1a1b26", bg = "#7aa2f7", bold = true } },
    CcTuiTabInactive = { link = "TabLine", fallback = { fg = "#565f89", bg = "#16161e" } },
    CcTuiTabBar = { link = "TabLineFill", fallback = { fg = "#565f89", bg = "#16161e" } },

    -- Content-specific highlights
    CcTuiTree = { link = "Directory", fallback = { fg = "#82aaff" } },
    CcTuiTreeIcon = { link = "Directory", fallback = { fg = "#7aa2f7" } },
    CcTuiMetadata = { link = "Comment", fallback = { fg = "#565f89" } },
    CcTuiTimestamp = { link = "Number", fallback = { fg = "#ff9e64" } },
    CcTuiBorder = { link = "FloatBorder", fallback = { fg = "#565f89" } },
}

---Get color value from existing highlight group
---@param group_name string Highlight group name
---@param attr string Color attribute ("fg" or "bg")
---@param fallback string Fallback color value
---@return string color Color value
local function get_color(group_name, attr, fallback)
    local ok, hl = pcall(vim.api.nvim_get_hl_by_name, group_name, true)
    if ok and hl[attr] then
        return string.format("#%06x", hl[attr])
    end
    return fallback
end

---Setup comprehensive highlight groups with theme integration
function M.setup_highlights()
    -- Auto-detect theme colors for better integration
    local normal_bg = get_color("Normal", "bg", "#1a1b26")
    local normal_fg = get_color("Normal", "fg", "#c0caf5")
    local directory_color = get_color("Directory", "fg", "#82aaff")

    -- Apply each highlight group
    for group_name, config in pairs(M.highlight_groups) do
        if config.link then
            -- Try to link to existing group first
            local ok = pcall(vim.api.nvim_set_hl, 0, group_name, { link = config.link, default = true })

            -- If linking fails or group doesn't exist, use fallback
            if not ok and config.fallback then
                vim.api.nvim_set_hl(0, group_name, config.fallback)
            end
        elseif config.fallback then
            -- Use fallback directly
            vim.api.nvim_set_hl(0, group_name, config.fallback)
        end
    end

    -- Setup special dynamic highlights based on detected theme
    vim.api.nvim_set_hl(0, "CcTuiAdaptive", {
        fg = normal_fg,
        bg = normal_bg,
    })

    -- Professional button styling with theme colors
    local button_bg = directory_color
    local button_fg = normal_bg

    vim.api.nvim_set_hl(0, "CcTuiHeaderBtn", {
        fg = button_fg,
        bg = button_bg,
        bold = true,
    })

    vim.api.nvim_set_hl(0, "CcTuiHeaderBtnShortcut", {
        fg = button_fg,
        bg = button_bg,
        bold = true,
    })
end

---Handle colorscheme changes to maintain professional appearance
function M.on_colorscheme_changed()
    -- Re-setup highlights when colorscheme changes
    M.setup_highlights()
end

---Get highlight configuration table for text utilities
---@return table highlights Professional highlight configuration
function M.get_highlights()
    return {
        header = "CcTuiHeader",
        header_btn = "CcTuiHeaderBtn",
        header_btn_shortcut = "CcTuiHeaderBtnShortcut",
        header_shortcut = "CcTuiHeaderShortcut",
        title = "CcTuiTitle",
        muted = "CcTuiMuted",
        success = "CcTuiSuccess",
        info = "CcTuiInfo",
        warn = "CcTuiWarn",
        error = "CcTuiError",
        tree = "CcTuiTree",
        tree_icon = "CcTuiTreeIcon",
        metadata = "CcTuiMetadata",
        timestamp = "CcTuiTimestamp",
        border = "CcTuiBorder",
    }
end

---Setup autocommand to handle colorscheme changes
function M.setup_autocommands()
    -- Create autocmd group for highlight management
    local group_id = vim.api.nvim_create_augroup("CcTuiHighlights", { clear = true })

    -- Re-setup highlights on colorscheme change
    vim.api.nvim_create_autocmd("ColorScheme", {
        group = group_id,
        pattern = "*",
        callback = M.on_colorscheme_changed,
        desc = "Update CC-TUI highlights on colorscheme change",
    })
end

---Initialize the highlight system
function M.init()
    M.setup_highlights()
    M.setup_autocommands()
end

---Get highlight for specific UI element
---@param element string UI element identifier
---@return string highlight Highlight group name
function M.get_highlight(element)
    local highlights = M.get_highlights()
    return highlights[element] or "Normal"
end

---Apply professional styling to a line
---@param line NuiLine Line to style
---@param style string Style identifier
---@return NuiLine line Styled line
function M.apply_style(line, style)
    vim.validate({
        line = { line, "table" },
        style = { style, "string" },
    })

    -- Note: NuiLine styling is applied during creation, not after
    -- This function exists for API consistency but returns line unchanged
    return line
end

---Get status-specific highlight
---@param status "active"|"inactive"|"success"|"error"|"warning"|"info" Status type
---@return string highlight Appropriate highlight group
function M.get_status_highlight(status)
    local status_map = {
        active = M.get_highlight("success"),
        inactive = M.get_highlight("muted"),
        success = M.get_highlight("success"),
        error = M.get_highlight("error"),
        warning = M.get_highlight("warn"),
        info = M.get_highlight("info"),
    }

    return status_map[status] or M.get_highlight("muted")
end

---Create professional badge/tag styling
---@param text string Badge text
---@param type "info"|"success"|"warning"|"error" Badge type
---@return table badge Badge configuration {text: string, highlight: string}
function M.create_badge(text, type)
    vim.validate({
        text = { text, "string" },
        type = { type, "string" },
    })

    local badges = {
        info = { prefix = "[", suffix = "]", highlight = M.get_highlight("info") },
        success = { prefix = "✓ ", suffix = "", highlight = M.get_highlight("success") },
        warning = { prefix = "⚠ ", suffix = "", highlight = M.get_highlight("warn") },
        error = { prefix = "✗ ", suffix = "", highlight = M.get_highlight("error") },
    }

    local badge_config = badges[type] or badges.info

    return {
        text = badge_config.prefix .. text .. badge_config.suffix,
        highlight = badge_config.highlight,
    }
end

return M
