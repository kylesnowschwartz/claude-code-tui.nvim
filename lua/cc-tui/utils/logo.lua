---@brief [[
--- Logo and Header System for CC-TUI
--- Provides placeholder logo system that can be enhanced later
--- Creates professional header layout following MCPHub patterns
---@brief ]]

local text_utils = require("cc-tui.utils.text")

---@class CcTui.Utils.Logo
local M = {}

---Create simple placeholder logo (can be enhanced later)
---@param width number Available width for centering
---@return NuiLine[] lines Logo lines
function M.create_logo(width)
    vim.validate({
        width = { width, "number" },
    })

    local lines = {}

    -- Simple placeholder logo - can be replaced with ASCII art later
    local logo_text = "CC-TUI"
    local logo_line = text_utils.align_text(logo_text, width, "center", "CcTuiTitle")
    table.insert(lines, logo_line)

    return lines
end

---Create professional header with logo and spacing
---@param width number Available width
---@return NuiLine[] lines Complete header section
function M.create_header(width)
    vim.validate({
        width = { width, "number" },
    })

    local lines = {}

    -- Add logo
    local logo_lines = M.create_logo(width)
    for _, line in ipairs(logo_lines) do
        table.insert(lines, line)
    end

    -- Add spacing after logo
    table.insert(lines, text_utils.empty_line())

    return lines
end

---Create compact header (just title, no logo)
---@param width number Available width
---@return NuiLine[] lines Compact header lines
function M.create_compact_header(width)
    vim.validate({
        width = { width, "number" },
    })

    local lines = {}

    -- Just the title without extra spacing
    local title_line = text_utils.align_text("CC-TUI", width, "center", "CcTuiTitle")
    table.insert(lines, title_line)

    return lines
end

---Create header section with optional subtitle
---@param width number Available width
---@param subtitle? string Optional subtitle text
---@return NuiLine[] lines Header with subtitle
function M.create_header_with_subtitle(width, subtitle)
    vim.validate({
        width = { width, "number" },
        subtitle = { subtitle, "string", true },
    })

    local lines = {}

    -- Add main header
    local header_lines = M.create_header(width)
    for _, line in ipairs(header_lines) do
        table.insert(lines, line)
    end

    -- Add subtitle if provided
    if subtitle then
        local subtitle_line = text_utils.align_text(subtitle, width, "center", "CcTuiMuted")
        table.insert(lines, subtitle_line)
        table.insert(lines, text_utils.empty_line())
    end

    return lines
end

---Create professional section divider with title
---@param title string Section title
---@param width number Available width
---@return NuiLine[] lines Section divider with title
function M.create_section_divider(title, width)
    vim.validate({
        title = { title, "string" },
        width = { width, "number" },
    })

    local lines = {}

    -- Add section title
    local title_line = text_utils.pad_line(title, "CcTuiTitle")
    table.insert(lines, title_line)

    -- Add divider line
    local divider_line = text_utils.divider(width, false)
    table.insert(lines, divider_line)

    -- Add spacing
    table.insert(lines, text_utils.empty_line())

    return lines
end

return M
