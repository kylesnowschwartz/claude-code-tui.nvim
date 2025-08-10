---@brief [[
--- Tabbed Interface Manager for CC-TUI
--- Provides unified tabbed interface following MCPHub's UX patterns
--- Consolidates Current, Browse, Logs, and Help views
---@brief ]]

local NuiLine = require("nui.line")
local NuiText = require("nui.text")
local Popup = require("nui.popup")
local highlights = require("cc-tui.utils.highlights")
local log = require("cc-tui.utils.log")
local logo_utils = require("cc-tui.utils.logo")
local text_utils = require("cc-tui.utils.text")

---@class CcTui.UI.TabbedManager
---@field popup NuiPopup Main popup window
---@field current_tab string Currently active tab ID
---@field tabs CcTui.TabConfig[] Tab configuration array
---@field views table<string, any> Tab content views by ID
---@field keymaps table<string, function> Global keymap handlers
---@field on_close_callback function? Optional callback when manager is closed
---@field current_conversation_path string? Path to currently selected conversation
local TabbedManager = {}
TabbedManager.__index = TabbedManager

---@class CcTui.TabConfig
---@field id string Tab identifier (e.g., "current", "browse", "logs", "help")
---@field key string Keyboard shortcut key (e.g., "C", "B", "L", "?")
---@field label string Display label for tab
---@field view string View class name for content

---@class CcTui.TabbedManagerOptions
---@field width? number|string Width of manager window (default: "80%")
---@field height? number|string Height of manager window (default: "80%")
---@field default_tab? string Default tab to open (default: "current")
---@field on_close? function Optional callback when manager is closed

-- UI Constants
local DEFAULTS = {
    DEFAULT_WIDTH = "80%",
    DEFAULT_HEIGHT = "80%",
    MIN_WINDOW_WIDTH = 80,
    MIN_WINDOW_HEIGHT = 15,
    TAB_BAR_HEIGHT = 3,
}

-- Tab definitions following PRD specifications
local TAB_DEFINITIONS = {
    {
        id = "current",
        key = "C",
        label = "Current",
        view = "current",
    },
    {
        id = "browse",
        key = "B",
        label = "Browse",
        view = "browse",
    },
    {
        id = "logs",
        key = "L",
        label = "Logs",
        view = "logs",
    },
    {
        id = "help",
        key = "?",
        label = "Help",
        view = "help",
    },
}

---Initialize professional highlights system
local function setup_highlights()
    highlights.init()
end

---Create professional MCPHub-style centered tab bar
---@param tabs CcTui.TabConfig[] Tab definitions
---@param current_tab string Currently active tab ID
---@param width number Available width for centering
---@return NuiLine
local function create_tab_bar(tabs, current_tab, width)
    local line = NuiLine()

    -- Build tab content manually with proper highlights
    local tab_parts = {}
    local total_content_width = 0

    for i, tab in ipairs(tabs) do
        local is_selected = tab.id == current_tab
        local tab_text = string.format(" %s %s ", tab.key, tab.label)

        -- Add spacing between tabs
        if i > 1 then
            table.insert(tab_parts, { text = "  ", highlight = "CcTuiTabBar" })
            total_content_width = total_content_width + 2
        end

        -- Add tab with appropriate highlight
        local highlight = is_selected and "CcTuiTabActive" or "CcTuiTabInactive"
        table.insert(tab_parts, { text = tab_text, highlight = highlight })
        total_content_width = total_content_width + vim.api.nvim_strwidth(tab_text)
    end

    -- Center the tab bar
    local padding = math.max(0, math.floor((width - total_content_width) / 2))

    -- Add left padding
    line:append(string.rep(" ", padding), "CcTuiTabBar")

    -- Add all tab parts
    for _, part in ipairs(tab_parts) do
        line:append(part.text, part.highlight)
    end

    -- Fill remaining space on the right
    local current_width = vim.api.nvim_strwidth(line:content())
    local remaining_padding = math.max(0, width - current_width)
    if remaining_padding > 0 then
        line:append(string.rep(" ", remaining_padding), "CcTuiTabBar")
    end

    return line
end

---Create a new tabbed manager instance
---@param opts CcTui.TabbedManagerOptions Configuration options
---@return CcTui.UI.TabbedManager? manager New manager instance or nil if creation failed
---@return string? error Error message if creation failed
function TabbedManager.new(opts)
    vim.validate({
        opts = { opts, "table", true },
    })

    opts = opts or {}
    setup_highlights()

    local self = setmetatable({}, TabbedManager)

    -- Initialize state
    self.tabs = vim.deepcopy(TAB_DEFINITIONS)
    self.current_tab = opts.default_tab or "current"
    self.views = {}
    self.on_close_callback = opts.on_close
    self.current_conversation_path = nil

    -- Parse size values like MCPHub
    local function parse_size(value, total)
        if type(value) == "string" then
            if value:match("%%$") then
                local percent = tonumber(value:match("(%d+)%%"))
                return math.floor((percent / 100) * total)
            end
        elseif type(value) == "number" then
            if value <= 1 then
                return math.floor(value * total)
            else
                return value
            end
        end
        return math.floor(0.8 * total) -- default fallback
    end

    local width = parse_size(opts.width or DEFAULTS.DEFAULT_WIDTH, vim.o.columns)
    local height = parse_size(opts.height or DEFAULTS.DEFAULT_HEIGHT, vim.o.lines)

    -- Center the window
    local row = math.floor((vim.o.lines - height) / 2)
    local col = math.floor((vim.o.columns - width) / 2)

    -- Create main floating window with error handling
    local success, popup = pcall(function()
        return Popup({
            relative = "editor",
            position = {
                row = row,
                col = col,
            },
            size = {
                width = width,
                height = height,
            },
            border = {
                style = "rounded",
                text = {
                    top = NuiText(" CC-TUI ", "CcTuiTitle"),
                    top_align = "center",
                },
            },
            win_options = {
                winhighlight = "Normal:Normal,FloatBorder:FloatBorder",
                cursorline = true,
            },
            buf_options = {
                modifiable = false,
                buftype = "nofile",
                filetype = "cc-tui",
            },
        })
    end)

    if not success then
        return nil, "Failed to create tabbed manager UI: " .. tostring(popup)
    end

    self.popup = popup

    -- Setup keymaps
    self:setup_keymaps()

    -- Initialize views (lazy loading)
    self:init_views()

    log.debug("TabbedManager", string.format("Created tabbed manager with %d tabs", #self.tabs))

    return self, nil
end

---Setup global and tab-specific keymaps
function TabbedManager:setup_keymaps()
    self.keymaps = {}

    -- Tab switching shortcuts (C, B, L, ?)
    for _, tab in ipairs(self.tabs) do
        self.keymaps[tab.key] = function()
            self:switch_to_tab(tab.id)
        end
    end

    -- Secondary navigation (removed Tab key to avoid conflicts with tree toggling)
    self.keymaps["]"] = function()
        self:cycle_tab_forward()
    end

    self.keymaps["["] = function()
        self:cycle_tab_backward()
    end

    self.keymaps["q"] = function()
        self:close()
    end

    self.keymaps["<Esc>"] = function()
        self:close()
    end

    self.keymaps["R"] = function()
        self:refresh_current_tab()
    end
end

---Initialize view instances (lazy loading)
function TabbedManager:init_views()
    -- Views will be loaded on demand in switch_to_tab()
    -- This prevents loading all views upfront and improves startup time
    log.debug("TabbedManager", "View initialization set up for lazy loading")
end

---Load view for specific tab (lazy loading implementation)
---@param tab_id string Tab identifier
---@return any? view View instance or nil if loading failed
function TabbedManager:load_view(tab_id)
    if self.views[tab_id] then
        return self.views[tab_id]
    end

    local view_name = nil
    for _, tab in ipairs(self.tabs) do
        if tab.id == tab_id then
            view_name = tab.view
            break
        end
    end

    if not view_name then
        log.debug("TabbedManager", string.format("No view mapping found for tab: %s", tab_id))
        return nil
    end

    -- Load view module based on view name
    local view_module_path = string.format("cc-tui.ui.views.%s", view_name)
    local success, view_module = pcall(require, view_module_path)

    if not success then
        log.debug("TabbedManager", string.format("Failed to load view module: %s", view_module_path))
        return nil
    end

    -- Create view instance
    local view_success, view_instance = pcall(view_module.new, self)
    if not view_success then
        log.debug(
            "TabbedManager",
            string.format("Failed to create view instance for %s: %s", tab_id, tostring(view_instance))
        )
        return nil
    end

    self.views[tab_id] = view_instance
    log.debug("TabbedManager", string.format("Loaded view for tab: %s", tab_id))

    return view_instance
end

---Apply view-specific keymaps for current tab
function TabbedManager:apply_view_keymaps()
    if not self.popup or not self.popup.bufnr then
        return
    end

    -- Clear existing view keymaps
    if self._current_view_keymaps then
        for key, _ in pairs(self._current_view_keymaps) do
            pcall(vim.keymap.del, "n", key, { buffer = self.popup.bufnr })
        end
    end

    -- Apply current view keymaps
    local current_view = self.views[self.current_tab]
    if current_view then
        -- Initialize view keymaps if not done
        if type(current_view.setup_keymaps) == "function" and not current_view.keymaps then
            current_view:setup_keymaps()
        end

        -- Apply view keymaps
        if current_view.keymaps then
            self._current_view_keymaps = {}
            for key, handler in pairs(current_view.keymaps) do
                -- Skip keys that conflict with global keymaps
                if not self.keymaps[key] then
                    vim.keymap.set("n", key, function()
                        handler()
                        self:render() -- Re-render after view action
                    end, {
                        buffer = self.popup.bufnr,
                        noremap = true,
                        silent = true,
                    })
                    self._current_view_keymaps[key] = true
                end
            end
        end
    end
end

---Switch to specified tab
---@param tab_id string Tab identifier to switch to
function TabbedManager:switch_to_tab(tab_id)
    vim.validate({
        tab_id = { tab_id, "string" },
    })

    -- Check if tab exists
    local tab_exists = false
    for _, tab in ipairs(self.tabs) do
        if tab.id == tab_id then
            tab_exists = true
            break
        end
    end

    if not tab_exists then
        log.debug("TabbedManager", string.format("Invalid tab ID: %s", tab_id))
        return
    end

    -- Switch tab and refresh display
    self.current_tab = tab_id
    self:render()
    self:apply_view_keymaps()

    log.debug("TabbedManager", string.format("Switched to tab: %s", tab_id))
end

---Cycle to next tab
function TabbedManager:cycle_tab_forward()
    local current_index = 1
    for i, tab in ipairs(self.tabs) do
        if tab.id == self.current_tab then
            current_index = i
            break
        end
    end

    local next_index = current_index < #self.tabs and current_index + 1 or 1
    self:switch_to_tab(self.tabs[next_index].id)
end

---Cycle to previous tab
function TabbedManager:cycle_tab_backward()
    local current_index = 1
    for i, tab in ipairs(self.tabs) do
        if tab.id == self.current_tab then
            current_index = i
            break
        end
    end

    local prev_index = current_index > 1 and current_index - 1 or #self.tabs
    self:switch_to_tab(self.tabs[prev_index].id)
end

---Refresh current tab content
function TabbedManager:refresh_current_tab()
    local current_view = self.views[self.current_tab]
    if current_view and type(current_view.refresh) == "function" then
        current_view:refresh()
    end

    self:render()
    log.debug("TabbedManager", string.format("Refreshed tab: %s", self.current_tab))
end

---Set the current conversation for cross-tab context
---@param conversation_path string Path to conversation file
function TabbedManager:set_current_conversation(conversation_path)
    vim.validate({
        conversation_path = { conversation_path, "string" },
    })

    self.current_conversation_path = conversation_path
    log.debug("TabbedManager", string.format("Set current conversation: %s", conversation_path))

    -- If Current tab is loaded, update it with the new conversation
    local current_view = self.views.current
    if current_view and type(current_view.load_specific_conversation) == "function" then
        current_view:load_specific_conversation(conversation_path)
    end
end

---Get the current conversation path
---@return string? conversation_path Current conversation path or nil
function TabbedManager:get_current_conversation()
    return self.current_conversation_path
end

---Get window width for layout calculations
---@return number width Available window width
function TabbedManager:get_width()
    return math.max(DEFAULTS.MIN_WINDOW_WIDTH, vim.api.nvim_win_get_width(self.popup.winid or 0))
end

---Get window height for layout calculations
---@return number height Available window height for content
function TabbedManager:get_content_height()
    local total_height = math.max(DEFAULTS.MIN_WINDOW_HEIGHT, vim.api.nvim_win_get_height(self.popup.winid or 0))
    return total_height - DEFAULTS.TAB_BAR_HEIGHT
end

---Render the complete professional tabbed interface
function TabbedManager:render()
    if not self.popup or not self.popup.bufnr then
        return
    end

    vim.api.nvim_buf_set_option(self.popup.bufnr, "modifiable", true)

    local lines = {}
    local width = self:get_width()

    -- Add professional header with logo placeholder
    local header_lines = logo_utils.create_compact_header(width)
    for _, line in ipairs(header_lines) do
        table.insert(lines, line)
    end

    -- Add professional tab bar
    local tab_bar = create_tab_bar(self.tabs, self.current_tab, width)
    table.insert(lines, tab_bar)

    -- Add professional divider
    local divider_line = text_utils.divider(width, true, "─", "CcTuiMuted")
    table.insert(lines, divider_line)

    -- Add consistent spacing
    table.insert(lines, text_utils.empty_line())

    -- Add current tab content with professional layout
    local current_view = self:load_view(self.current_tab)
    if current_view and type(current_view.render) == "function" then
        local content_height = self:get_content_height() - 4 -- Account for header space
        local content_lines = current_view:render(content_height)
        if content_lines then
            for _, line in ipairs(content_lines) do
                table.insert(lines, line)
            end
        end
    else
        -- Professional fallback content
        local error_line = text_utils.pad_line(
            string.format("Error: Unable to load content for '%s' tab", self.current_tab),
            "CcTuiMuted"
        )
        table.insert(lines, error_line)
    end

    -- Clear buffer and render all lines
    vim.api.nvim_buf_set_lines(self.popup.bufnr, 0, -1, false, {})
    for i, line in ipairs(lines) do
        line:render(self.popup.bufnr, -1, i)
    end

    vim.api.nvim_buf_set_option(self.popup.bufnr, "modifiable", false)
end

---Show the tabbed manager
function TabbedManager:show()
    if not self.popup then
        return
    end

    self.popup:mount()

    -- Focus the main window
    if self.popup.winid then
        vim.api.nvim_set_current_win(self.popup.winid)
    end

    -- Apply global keymaps
    for key, handler in pairs(self.keymaps) do
        vim.keymap.set("n", key, handler, {
            buffer = self.popup.bufnr,
            noremap = true,
            silent = true,
        })
    end

    -- Initial render and apply view keymaps
    self:render()
    self:apply_view_keymaps()

    log.debug("TabbedManager", string.format("Showed tabbed manager, active tab: %s", self.current_tab))
end

---Close the tabbed manager
function TabbedManager:close()
    if self.popup then
        -- Clean up views
        for _, view in pairs(self.views) do
            if type(view.cleanup) == "function" then
                view:cleanup()
            end
        end

        self.popup:unmount()

        -- Call optional close callback
        if self.on_close_callback then
            self.on_close_callback()
        end

        log.debug("TabbedManager", "Closed tabbed manager")
    end
end

---Check if manager is currently active
---@return boolean active True if manager is shown and valid
function TabbedManager:is_active()
    return self.popup ~= nil and self.popup.bufnr ~= nil and vim.api.nvim_buf_is_valid(self.popup.bufnr)
end

return TabbedManager
