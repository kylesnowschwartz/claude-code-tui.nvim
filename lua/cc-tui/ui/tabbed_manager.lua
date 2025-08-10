---@brief [[
--- Tabbed Interface Manager for CC-TUI
--- Provides unified tabbed interface following MCPHub's UX patterns
--- Consolidates Current, Browse, Logs, and Help views
---@brief ]]

local NuiLine = require("nui.line")
local NuiText = require("nui.text")
local Split = require("nui.split")
local log = require("cc-tui.utils.log")

---@class CcTui.UI.TabbedManager
---@field split NuiSplit Main split window
---@field current_tab string Currently active tab ID
---@field tabs CcTui.TabConfig[] Tab configuration array
---@field views table<string, any> Tab content views by ID
---@field keymaps table<string, function> Global keymap handlers
---@field on_close_callback function? Optional callback when manager is closed
local TabbedManager = {}
TabbedManager.__index = TabbedManager

---@class CcTui.TabConfig
---@field id string Tab identifier (e.g., "current", "browse", "logs", "help")
---@field key string Keyboard shortcut key (e.g., "C", "B", "L", "?")
---@field label string Display label for tab
---@field view string View class name for content

---@class CcTui.TabbedManagerOptions
---@field width? number|string Width of manager window (default: "90%")
---@field height? number|string Height of manager window (default: "80%")
---@field default_tab? string Default tab to open (default: "current")
---@field on_close? function Optional callback when manager is closed

-- UI Constants
local DEFAULTS = {
    DEFAULT_WIDTH = "90%",
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

---Create highlight groups for the tabbed interface
local function setup_highlights()
    vim.api.nvim_set_hl(0, "CcTuiTabActive", { link = "TabLineSel", default = true })
    vim.api.nvim_set_hl(0, "CcTuiTabInactive", { link = "TabLine", default = true })
    vim.api.nvim_set_hl(0, "CcTuiTabBar", { link = "TabLineFill", default = true })
    vim.api.nvim_set_hl(0, "CcTuiTitle", { link = "Title", default = true })
    vim.api.nvim_set_hl(0, "CcTuiMuted", { link = "Comment", default = true })
    vim.api.nvim_set_hl(0, "CcTuiInfo", { link = "Directory", default = true })
end

---Create MCPHub-style centered tab bar
---@param tabs CcTui.TabConfig[] Tab definitions
---@param current_tab string Currently active tab ID
---@param width number Available width for centering
---@return NuiLine
local function create_tab_bar(tabs, current_tab, width)
    local tab_group = NuiLine()

    for i, tab in ipairs(tabs) do
        if i > 1 then
            tab_group:append(" ")
        end

        local is_selected = tab.id == current_tab
        local tab_text = string.format("%s %s", tab.key, tab.label)

        tab_group:append(" " .. tab_text .. " ", is_selected and "CcTuiTabActive" or "CcTuiTabInactive")
    end

    -- Center the tab bar
    local tab_content = tab_group:content()
    local tab_width = vim.api.nvim_strwidth(tab_content)
    local padding = math.max(0, math.floor((width - tab_width) / 2))

    local centered_line = NuiLine()
    centered_line:append(string.rep(" ", padding), "CcTuiTabBar")

    -- Re-add tab content with proper highlights
    for i, tab in ipairs(tabs) do
        if i > 1 then
            centered_line:append(" ", "CcTuiTabBar")
        end

        local is_selected = tab.id == current_tab
        local tab_text = string.format("%s %s", tab.key, tab.label)

        centered_line:append(" " .. tab_text .. " ", is_selected and "CcTuiTabActive" or "CcTuiTabInactive")
    end

    -- Fill remaining space
    local remaining_padding = width - vim.api.nvim_strwidth(centered_line:content())
    if remaining_padding > 0 then
        centered_line:append(string.rep(" ", remaining_padding), "CcTuiTabBar")
    end

    return centered_line
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

    -- Create main split window with error handling
    local success, split = pcall(function()
        return Split({
            relative = "editor",
            position = "top",
            size = opts.height or DEFAULTS.DEFAULT_HEIGHT,
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
        return nil, "Failed to create tabbed manager UI: " .. tostring(split)
    end

    self.split = split

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

    -- Secondary navigation
    self.keymaps["<Tab>"] = function()
        self:cycle_tab_forward()
    end

    self.keymaps["<S-Tab>"] = function()
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

---Get window width for layout calculations
---@return number width Available window width
function TabbedManager:get_width()
    return math.max(DEFAULTS.MIN_WINDOW_WIDTH, vim.api.nvim_win_get_width(self.split.winid or 0))
end

---Get window height for layout calculations
---@return number height Available window height for content
function TabbedManager:get_content_height()
    local total_height = math.max(DEFAULTS.MIN_WINDOW_HEIGHT, vim.api.nvim_win_get_height(self.split.winid or 0))
    return total_height - DEFAULTS.TAB_BAR_HEIGHT
end

---Render the complete tabbed interface
function TabbedManager:render()
    if not self.split or not self.split.bufnr then
        return
    end

    vim.api.nvim_buf_set_option(self.split.bufnr, "modifiable", true)

    local lines = {}
    local width = self:get_width()

    -- Add tab bar
    local tab_bar = create_tab_bar(self.tabs, self.current_tab, width)
    table.insert(lines, tab_bar)

    -- Add separator line
    local separator = NuiLine()
    separator:append(string.rep("─", width), "CcTuiMuted")
    table.insert(lines, separator)

    -- Add spacing
    table.insert(lines, NuiLine())

    -- Add current tab content
    local current_view = self:load_view(self.current_tab)
    if current_view and type(current_view.render) == "function" then
        local content_lines = current_view:render(self:get_content_height())
        if content_lines then
            for _, line in ipairs(content_lines) do
                table.insert(lines, line)
            end
        end
    else
        -- Fallback content if view not available
        local error_line = NuiLine()
        error_line:append(string.format("  Error: Unable to load content for '%s' tab", self.current_tab), "CcTuiMuted")
        table.insert(lines, error_line)
    end

    -- Clear buffer and render all lines
    vim.api.nvim_buf_set_lines(self.split.bufnr, 0, -1, false, {})
    for i, line in ipairs(lines) do
        line:render(self.split.bufnr, -1, i)
    end

    vim.api.nvim_buf_set_option(self.split.bufnr, "modifiable", false)
end

---Show the tabbed manager
function TabbedManager:show()
    if not self.split then
        return
    end

    self.split:mount()

    -- Apply global keymaps
    for key, handler in pairs(self.keymaps) do
        vim.keymap.set("n", key, handler, {
            buffer = self.split.bufnr,
            noremap = true,
            silent = true,
        })
    end

    -- Initial render
    self:render()

    log.debug("TabbedManager", string.format("Showed tabbed manager, active tab: %s", self.current_tab))
end

---Close the tabbed manager
function TabbedManager:close()
    if self.split then
        -- Clean up views
        for _, view in pairs(self.views) do
            if type(view.cleanup) == "function" then
                view:cleanup()
            end
        end

        self.split:unmount()

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
    return self.split ~= nil and self.split.bufnr ~= nil and vim.api.nvim_buf_is_valid(self.split.bufnr)
end

return TabbedManager
