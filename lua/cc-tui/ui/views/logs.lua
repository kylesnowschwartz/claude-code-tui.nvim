---@brief [[
--- Logs view for CC-TUI tabbed interface
--- Shows debug and activity logs for CC-TUI operations
---@brief ]]

local BaseView = require("cc-tui.ui.views.base")
local NuiLine = require("nui.line")
local log = require("cc-tui.utils.log")

---@class CcTui.UI.LogsView:CcTui.UI.View
---@field log_entries table[] Cached log entries
---@field max_entries number Maximum number of log entries to keep
local LogsView = setmetatable({}, { __index = BaseView })
LogsView.__index = LogsView

---Create a new logs view instance
---@param manager CcTui.UI.TabbedManager Parent tabbed manager
---@return CcTui.UI.LogsView view New logs view instance
function LogsView.new(manager)
    local self = BaseView.new(manager, "logs")
    setmetatable(self, LogsView)

    self.log_entries = {}
    self.max_entries = 100 -- Keep last 100 log entries

    -- Collect initial log entries
    self:collect_log_entries()

    return self
end

---Collect log entries from log system
function LogsView:collect_log_entries()
    -- Get actual log entries from the log system
    self.log_entries = log.get_entries()
end

-- Log entries are now managed by the central log system

---Get highlight group for log level
---@param level string Log level
---@return string highlight Highlight group name
local function get_level_highlight(level)
    local highlights = {
        ERROR = "ErrorMsg",
        WARN = "WarningMsg",
        INFO = "CcTuiInfo",
        DEBUG = "CcTuiMuted",
    }
    return highlights[level] or "Normal"
end

---Render logs content
---@param available_height number Available height for content
---@return NuiLine[] lines Logs content lines
function LogsView:render(available_height)
    local lines = {}
    local width = self.manager:get_width()

    -- Header
    local header_line = NuiLine()
    header_line:append("  📋 CC-TUI Activity Logs", "CcTuiInfo")
    header_line:append(string.format(" (%d entries)", #self.log_entries), "CcTuiMuted")
    table.insert(lines, header_line)

    table.insert(lines, self:create_empty_line())

    if #self.log_entries == 0 then
        table.insert(lines, self:create_padded_line("No log entries available", 4, "CcTuiMuted"))
        table.insert(lines, self:create_padded_line("Debug logging may be disabled", 4, "CcTuiMuted"))
        return lines
    end

    -- Calculate how many entries we can show
    local header_lines = 3 -- Header + empty line + some padding
    local entries_to_show = math.min(#self.log_entries, available_height - header_lines)

    -- Show recent entries (already sorted newest first)
    for i = 1, entries_to_show do
        local entry = self.log_entries[i]

        local line = NuiLine()
        line:append("  ")

        -- Timestamp
        line:append(entry.timestamp, "CcTuiMuted")
        line:append(" ")

        -- Level badge
        local level_text = string.format("[%s]", entry.level)
        line:append(level_text, get_level_highlight(entry.level))
        line:append(" ")

        -- Module
        if entry.module then
            line:append(string.format("%s:", entry.module), "CcTuiInfo")
            line:append(" ")
        end

        -- Message (truncate if too long)
        local remaining_width = width - 35 -- Rough estimate for timestamp, level, module
        local truncated_message = self:truncate_text(entry.message, remaining_width)
        line:append(truncated_message, "Normal")

        table.insert(lines, line)
    end

    -- Show truncation notice if we have more entries
    if #self.log_entries > entries_to_show then
        table.insert(lines, self:create_empty_line())
        local more_line = NuiLine()
        more_line:append("  ... ", "CcTuiMuted")
        more_line:append(
            string.format("%d more entries (refresh to update)", #self.log_entries - entries_to_show),
            "CcTuiMuted"
        )
        table.insert(lines, more_line)
    end

    return lines
end

---Refresh logs content
function LogsView:refresh()
    -- Re-collect log entries from log system
    self:collect_log_entries()
end

---Set up logs view specific keymaps
function LogsView:setup_keymaps(_)
    -- Could add keymaps for filtering by level, clearing logs, etc.
    -- Example: Add 'C' key to clear logs
    -- vim.keymap.set("n", "C", function() log.clear_entries(); self:refresh() end, { buffer = true })
    -- For now, inherit base keymaps only
end

return LogsView
