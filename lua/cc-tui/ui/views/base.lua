---@brief [[
--- Base view class for CC-TUI tabbed interface views
--- Provides common interface and utilities for all tab content views
---@brief ]]

local NuiLine = require("nui.line")
local highlights = require("cc-tui.utils.highlights")
local log = require("cc-tui.utils.log")
local text_utils = require("cc-tui.utils.text")

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

---Professional helper to create centered text line
---@param text string Text to center
---@param width number Available width
---@param highlight? string Optional highlight group
---@return NuiLine line Professional centered text line
function BaseView:create_centered_line(text, width, highlight)
    return text_utils.align_text(text, width, "center", highlight)
end

---Professional helper to create padded text line
---@param text string Text content
---@param padding? number Left padding (default: professional standard)
---@param highlight? string Optional highlight group
---@return NuiLine line Professional padded text line
function BaseView:create_padded_line(text, padding, highlight)
    return text_utils.pad_line(text, highlight, padding)
end

---Professional helper to create separator line
---@param width number Line width
---@param char? string Separator character (default: professional standard)
---@param highlight? string Optional highlight group
---@return NuiLine line Professional separator line
function BaseView:create_separator_line(width, char, highlight)
    return text_utils.divider(width, true, char, highlight)
end

---Professional helper to create empty line
---@param padding? number Optional padding for consistency
---@return NuiLine line Professional empty line
function BaseView:create_empty_line(padding)
    return text_utils.empty_line(padding)
end

---Professional helper to create section header
---@param title string Section title
---@param icon? string Optional icon
---@param highlight? string Optional highlight group
---@return NuiLine line Professional section header
function BaseView:create_section_header(title, icon, highlight)
    return text_utils.section_header(title, icon, highlight)
end

---Professional helper to create list item
---@param text string Item text
---@param index? number Optional item number
---@param status? string Optional status indicator
---@return NuiLine line Professional list item
function BaseView:create_list_item(text, index, status)
    return text_utils.list_item(text, index, status)
end

---Professional helper to create action bar
---@param actions table<string, string> Action mappings
---@param width number Available width
---@return NuiLine line Professional action bar
function BaseView:create_action_bar(actions, width)
    return text_utils.action_bar(actions, width)
end

---Professional helper to truncate text with ellipsis
---@param text string Text to truncate
---@param max_width number Maximum width
---@param ellipsis? string Ellipsis string
---@return string text Professionally truncated text
function BaseView:truncate_text(text, max_width, ellipsis)
    return text_utils.truncate_text(text, max_width, ellipsis)
end

---Get professional highlight for UI element
---@param element string UI element type
---@return string highlight Professional highlight group
function BaseView:get_highlight(element)
    return highlights.get_highlight(element)
end

---Create professional status badge
---@param text string Badge text
---@param type string Badge type
---@return table badge Professional badge configuration
function BaseView:create_badge(text, type)
    return highlights.create_badge(text, type)
end

return BaseView
