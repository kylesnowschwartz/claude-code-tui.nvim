---@brief [[
--- Base view class for CC-TUI tabbed interface views
--- Provides common interface and utilities for all tab content views
---@brief ]]

local NuiLine = require("nui.line")
local log = require("cc-tui.utils.log")

---@class CcTui.UI.View
---@field manager CcTui.UI.TabbedManager Reference to parent tabbed manager
---@field view_id string Unique identifier for this view
---@field keymaps table<string, function> View-specific keymap handlers
local BaseView = {}
BaseView.__index = BaseView

---Create a new base view instance
---@param manager CcTui.UI.TabbedManager Parent tabbed manager
---@param view_id string View identifier
---@return CcTui.UI.View view New view instance
function BaseView.new(manager, view_id)
    vim.validate({
        manager = { manager, "table" },
        view_id = { view_id, "string" },
    })

    local self = setmetatable({}, BaseView)

    self.manager = manager
    self.view_id = view_id
    self.keymaps = {}

    log.debug("BaseView", string.format("Created base view: %s", view_id))

    return self
end

---Setup view-specific keymaps (override in subclasses)
function BaseView:setup_keymaps(_)
    -- Default implementation - override in subclasses
    -- Views can add their own keymaps here
end

---Render view content (override in subclasses)
---@param available_height number Available height for content
---@return NuiLine[]? lines Content lines to render
function BaseView:render(available_height)
    vim.validate({
        available_height = { available_height, "number" },
    })

    -- Default implementation - override in subclasses
    local lines = {}

    local placeholder_line = NuiLine()
    placeholder_line:append(string.format("  %s view content goes here", self.view_id), "Comment")
    table.insert(lines, placeholder_line)

    local height_line = NuiLine()
    height_line:append(string.format("  Available height: %d lines", available_height), "Comment")
    table.insert(lines, height_line)

    return lines
end

---Refresh view content (override in subclasses)
function BaseView:refresh()
    -- Default implementation - override in subclasses
    log.debug("BaseView", string.format("Refreshed view: %s", self.view_id))
end

---Clean up view resources (override in subclasses)
function BaseView:cleanup()
    -- Default implementation - override in subclasses
    log.debug("BaseView", string.format("Cleaned up view: %s", self.view_id))
end

---Get reference to parent manager
---@return CcTui.UI.TabbedManager manager Parent tabbed manager
function BaseView:get_manager()
    return self.manager
end

---Get view identifier
---@return string view_id View identifier
function BaseView:get_view_id()
    return self.view_id
end

---Helper to create centered text line
---@param text string Text to center
---@param width number Available width
---@param highlight? string Optional highlight group
---@return NuiLine line Centered text line
function BaseView.create_centered_line(text, width, highlight)
    vim.validate({
        text = { text, "string" },
        width = { width, "number" },
        highlight = { highlight, "string", true },
    })

    local padding = math.max(0, math.floor((width - vim.api.nvim_strwidth(text)) / 2))

    local line = NuiLine()
    line:append(string.rep(" ", padding))
    line:append(text, highlight or "Normal")

    return line
end

---Helper to create padded text line
---@param text string Text content
---@param padding? number Left padding (default: 2)
---@param highlight? string Optional highlight group
---@return NuiLine line Padded text line
function BaseView.create_padded_line(text, padding, highlight)
    vim.validate({
        text = { text, "string" },
        padding = { padding, "number", true },
        highlight = { highlight, "string", true },
    })

    padding = padding or 2

    local line = NuiLine()
    line:append(string.rep(" ", padding))
    line:append(text, highlight or "Normal")

    return line
end

---Helper to create separator line
---@param width number Line width
---@param char? string Separator character (default: "─")
---@param highlight? string Optional highlight group
---@return NuiLine line Separator line
function BaseView.create_separator_line(width, char, highlight)
    vim.validate({
        width = { width, "number" },
        char = { char, "string", true },
        highlight = { highlight, "string", true },
    })

    char = char or "─"

    local line = NuiLine()
    line:append(string.rep(char, width), highlight or "Comment")

    return line
end

---Helper to create empty line
---@return NuiLine line Empty line
function BaseView.create_empty_line()
    return NuiLine()
end

---Helper to truncate text to fit width with ellipsis
---@param text string Text to truncate
---@param max_width number Maximum width
---@param ellipsis? string Ellipsis string (default: "...")
---@return string text Truncated text
function BaseView.truncate_text(text, max_width, ellipsis)
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

    -- Simple truncation - could be improved to handle multi-byte characters better
    return string.sub(text, 1, available_width) .. ellipsis
end

return BaseView
