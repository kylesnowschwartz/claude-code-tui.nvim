---@brief [[
--- Help view for CC-TUI tabbed interface
--- Shows keybindings and usage instructions
---@brief ]]

local BaseView = require("cc-tui.ui.views.base")
local NuiLine = require("nui.line")

---@class CcTui.UI.HelpView:CcTui.UI.View
local HelpView = setmetatable({}, { __index = BaseView })
HelpView.__index = HelpView

---Create a new help view instance
---@param manager CcTui.UI.TabbedManager Parent tabbed manager
---@return CcTui.UI.HelpView view New help view instance
function HelpView.new(manager)
    local self = BaseView.new(manager, "help")
    setmetatable(self, HelpView)

    return self
end

---Render help content
---@param available_height number Available height for content
---@return NuiLine[] lines Help content lines
function HelpView:render(_)
    local lines = {}
    local width = self.manager:get_width()

    -- Title
    table.insert(lines, self:create_centered_line("CC-TUI Help & Keybindings", width, "CcTuiTitle"))
    table.insert(lines, self:create_empty_line())

    -- Tab Navigation Section
    table.insert(lines, self:create_padded_line("📑 Tab Navigation", 2, "CcTuiInfo"))
    table.insert(lines, self:create_empty_line())

    local tab_shortcuts = {
        { key = "C", desc = "Switch to Current conversation view" },
        { key = "B", desc = "Switch to Browse conversations view" },
        { key = "L", desc = "Switch to Logs view" },
        { key = "?", desc = "Switch to Help view (this view)" },
    }

    for _, shortcut in ipairs(tab_shortcuts) do
        local line = NuiLine()
        line:append("    ")
        line:append(shortcut.key, "CcTuiTabActive")
        line:append(" - " .. shortcut.desc, "Normal")
        table.insert(lines, line)
    end

    table.insert(lines, self:create_empty_line())

    -- Secondary Navigation
    table.insert(lines, self:create_padded_line("🔄 Secondary Navigation", 2, "CcTuiInfo"))
    table.insert(lines, self:create_empty_line())

    local secondary_shortcuts = {
        { key = "Tab", desc = "Cycle to next tab" },
        { key = "Shift+Tab", desc = "Cycle to previous tab" },
        { key = "R", desc = "Refresh current tab content" },
        { key = "q", desc = "Close CC-TUI" },
        { key = "Esc", desc = "Close CC-TUI" },
    }

    for _, shortcut in ipairs(secondary_shortcuts) do
        local line = NuiLine()
        line:append("    ")
        line:append(shortcut.key, "CcTuiTabInactive")
        line:append(" - " .. shortcut.desc, "Normal")
        table.insert(lines, line)
    end

    table.insert(lines, self:create_empty_line())

    -- Current Tab Shortcuts
    table.insert(lines, self:create_padded_line("📋 Current Tab Shortcuts", 2, "CcTuiInfo"))
    table.insert(lines, self:create_empty_line())

    local current_shortcuts = {
        { key = "j/k", desc = "Navigate up/down in conversation tree" },
        { key = "h/l", desc = "Collapse/expand nodes" },
        { key = "Space", desc = "Toggle node expansion" },
        { key = "Enter", desc = "Jump to message in editor" },
        { key = "o", desc = "Expand all nodes" },
        { key = "c", desc = "Collapse all nodes" },
    }

    for _, shortcut in ipairs(current_shortcuts) do
        local line = NuiLine()
        line:append("    ")
        line:append(shortcut.key, "CcTuiTabInactive")
        line:append(" - " .. shortcut.desc, "Normal")
        table.insert(lines, line)
    end

    table.insert(lines, self:create_empty_line())

    -- Browse Tab Shortcuts
    table.insert(lines, self:create_padded_line("🗂  Browse Tab Shortcuts", 2, "CcTuiInfo"))
    table.insert(lines, self:create_empty_line())

    local browse_shortcuts = {
        { key = "j/k", desc = "Navigate up/down conversation list" },
        { key = "Enter", desc = "Open selected conversation" },
        { key = "Tab", desc = "Toggle metadata display" },
        { key = "r", desc = "Refresh conversation list" },
        { key = "gg/G", desc = "Jump to first/last conversation" },
    }

    for _, shortcut in ipairs(browse_shortcuts) do
        local line = NuiLine()
        line:append("    ")
        line:append(shortcut.key, "CcTuiTabInactive")
        line:append(" - " .. shortcut.desc, "Normal")
        table.insert(lines, line)
    end

    table.insert(lines, self:create_empty_line())

    -- Usage Instructions
    table.insert(lines, self:create_padded_line("🚀 Usage Instructions", 2, "CcTuiInfo"))
    table.insert(lines, self:create_empty_line())

    local usage_instructions = {
        "1. Start CC-TUI with :CcTui command",
        "2. Use tab shortcuts (C/B/L/?) to switch between views",
        "3. Current tab shows your active conversation tree",
        "4. Browse tab lists all conversations in your project",
        "5. Logs tab displays debug and activity information",
        "6. Use view-specific shortcuts for navigation within each tab",
    }

    for _, instruction in ipairs(usage_instructions) do
        table.insert(lines, self:create_padded_line(instruction, 4, "Normal"))
    end

    table.insert(lines, self:create_empty_line())

    -- Footer
    table.insert(lines, self:create_separator_line(width, "─", "CcTuiMuted"))
    table.insert(lines, self:create_centered_line("CC-TUI: Claude Code Terminal User Interface", width, "CcTuiMuted"))

    return lines
end

---Refresh help content (no-op since help is static)
function HelpView:refresh(_)
    -- Help content is static, no refresh needed
end

return HelpView
