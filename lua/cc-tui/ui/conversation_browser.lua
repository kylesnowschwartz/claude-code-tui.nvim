---@brief [[
--- Conversation Browser UI for Claude project exploration
--- Provides tabbed interface for browsing conversation history
--- Inspired by MCPHub's excellent UI patterns
---@brief ]]

local NuiLine = require("nui.line")
local NuiText = require("nui.text")
local ProjectDiscovery = require("cc-tui.services.project_discovery")
local Split = require("nui.split")
local log = require("cc-tui.util.log")

---@class CcTui.UI.ConversationBrowser
---@field split NuiSplit Main split window
---@field project_name string Current project name
---@field conversations CcTui.ConversationMetadata[] List of conversations
---@field current_index number Currently selected conversation index
---@field show_metadata boolean Whether to show metadata for each conversation
---@field on_select_callback function Callback when conversation is selected
---@field keymaps table<string, function> Keymap handlers
-- UI Constants
local DEFAULTS = {
    DEFAULT_HEIGHT = "80%",
    MIN_WINDOW_WIDTH = 80,
    MIN_WINDOW_HEIGHT = 10,
    HEADER_FOOTER_RESERVE = 6,
    LINE_PREFIX_RESERVE = 10,
    METADATA_EXTRA_RESERVE = 40,
}

local M = {}
M.__index = M

---@class CcTui.ConversationBrowserOptions
---@field on_select function(conversation_path: string) Callback when conversation selected
---@field width? number|string Width of browser (default: "50%")
---@field height? number|string Height of browser (default: DEFAULTS.DEFAULT_HEIGHT)

---Create highlight groups for the browser
local function setup_highlights()
    -- Define highlight groups inspired by MCPHub
    vim.api.nvim_set_hl(0, "CcTuiTabActive", { link = "TabLineSel", default = true })
    vim.api.nvim_set_hl(0, "CcTuiTabInactive", { link = "TabLine", default = true })
    vim.api.nvim_set_hl(0, "CcTuiTabBar", { link = "TabLineFill", default = true })
    vim.api.nvim_set_hl(0, "CcTuiBrowserTitle", { link = "Title", default = true })
    vim.api.nvim_set_hl(0, "CcTuiBrowserMuted", { link = "Comment", default = true })
    vim.api.nvim_set_hl(0, "CcTuiBrowserInfo", { link = "Directory", default = true })
end

---Create a new conversation browser
---@param opts CcTui.ConversationBrowserOptions Options
---@return CcTui.UI.ConversationBrowser? browser New browser instance or nil if creation failed
---@return string? error Error message if creation failed
function M.new(opts)
    vim.validate({
        opts = { opts, "table" },
        ["opts.on_select"] = { opts.on_select, "function" },
    })

    setup_highlights()

    local self = setmetatable({}, M)

    -- Initialize state
    self.on_select_callback = opts.on_select
    self.current_index = 1
    self.show_metadata = false
    self.conversations = {}

    -- Get current project
    local cwd = vim.fn.getcwd()
    self.project_name = ProjectDiscovery.get_project_name(cwd)

    -- Create main split window with error handling
    local success, split = pcall(function()
        return Split({
            relative = "editor",
            position = "top",
            size = opts.height or DEFAULTS.DEFAULT_HEIGHT,
            border = {
                style = "rounded",
                text = {
                    top = NuiText(" Claude Conversations - " .. self.project_name .. " ", "CcTuiBrowserTitle"),
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
            },
        })
    end)

    if not success then
        return nil, "Failed to create conversation browser UI: " .. tostring(split)
    end

    self.split = split

    -- Setup keymaps
    self:setup_keymaps()

    -- Load conversations
    self:load_conversations()

    return self, nil
end

---Setup keymaps for the browser
function M:setup_keymaps()
    self.keymaps = {
        ["<Tab>"] = function()
            self:toggle_metadata()
        end,
        ["<CR>"] = function()
            self:select_current()
        end,
        ["j"] = function()
            self:next_conversation()
        end,
        ["k"] = function()
            self:prev_conversation()
        end,
        ["<Down>"] = function()
            self:next_conversation()
        end,
        ["<Up>"] = function()
            self:prev_conversation()
        end,
        ["gg"] = function()
            self:first_conversation()
        end,
        ["G"] = function()
            self:last_conversation()
        end,
        ["q"] = function()
            self:close()
        end,
        ["<Esc>"] = function()
            self:close()
        end,
        ["r"] = function()
            self:refresh()
        end,
    }
end

---Load conversations for current project
function M:load_conversations()
    if not ProjectDiscovery.project_exists(self.project_name) then
        log.debug("ConversationBrowser", string.format("Project %s not found", self.project_name))
        self.conversations = {}
        return
    end

    -- Get all conversations
    self.conversations = ProjectDiscovery.list_conversations(self.project_name)

    -- Reset current index if out of bounds
    if self.current_index > #self.conversations then
        self.current_index = 1
    end

    -- Enrich first few with metadata for initial display (async for UI responsiveness)
    self:load_initial_metadata_async()

    log.debug("ConversationBrowser", string.format("Loaded %d conversations", #self.conversations))
end

---Asynchronously load metadata for initial conversations to display
function M:load_initial_metadata_async()
    local initial_count = math.min(5, #self.conversations)
    local loaded_count = 0

    -- Load metadata for first few conversations asynchronously
    for i = 1, initial_count do
        local conv = self.conversations[i]
        ProjectDiscovery.enrich_conversation_metadata_async(conv, function()
            loaded_count = loaded_count + 1

            -- Re-render when all initial metadata is loaded
            if loaded_count == initial_count then
                vim.schedule(function()
                    if self.split and self.split.bufnr then
                        self:render()
                    end
                end)
            end
        end)
    end
end

---Asynchronously load metadata for a single conversation and re-render
---@param conv CcTui.ConversationMetadata Conversation to enrich
---@param index number Index in conversations array
function M:load_conversation_metadata_async(conv, index)
    ProjectDiscovery.enrich_conversation_metadata_async(conv, function(enriched_conv)
        -- Update the conversation in place
        self.conversations[index] = enriched_conv

        -- Re-render to show the updated metadata
        vim.schedule(function()
            if self.split and self.split.bufnr then
                self:render()
            end
        end)
    end)
end

---Create conversation list view
---@return NuiLine[] lines The conversation list lines
function M:create_conversation_list()
    local lines = {}
    local width = math.max(vim.api.nvim_win_get_width(self.split.winid or 0), DEFAULTS.MIN_WINDOW_WIDTH)

    if #self.conversations == 0 then
        local empty_line = NuiLine()
        empty_line:append("  No conversations found in project: ", "CcTuiBrowserMuted")
        empty_line:append(self.project_name or "unknown", "CcTuiBrowserInfo")
        table.insert(lines, empty_line)

        local help_line = NuiLine()
        help_line:append("  Start a new conversation with: ", "CcTuiBrowserMuted")
        help_line:append("claude", "CcTuiBrowserInfo")
        table.insert(lines, help_line)

        return lines
    end

    -- Calculate scrolling window
    local window_height = math.max(
        DEFAULTS.MIN_WINDOW_HEIGHT,
        vim.api.nvim_win_get_height(self.split.winid or 0) - DEFAULTS.HEADER_FOOTER_RESERVE
    ) -- Reserve space for headers/help
    local start_idx = 1
    local end_idx = #self.conversations

    -- Adjust window if we have many conversations
    if #self.conversations > window_height then
        local half_window = math.floor(window_height / 2)
        start_idx = math.max(1, self.current_index - half_window)
        end_idx = math.min(#self.conversations, start_idx + window_height - 1)

        -- Adjust start if we're at the end
        if end_idx == #self.conversations then
            start_idx = math.max(1, end_idx - window_height + 1)
        end
    end

    -- Render conversation list
    for i = start_idx, end_idx do
        local conv = self.conversations[i]

        -- Lazy load metadata if needed (async to prevent UI blocking)
        if not conv.title then
            self:load_conversation_metadata_async(conv, i)
        end

        local line = NuiLine()

        -- Add selection indicator
        local is_selected = i == self.current_index
        local prefix = is_selected and "► " or "  "
        local prefix_hl = is_selected and "CcTuiBrowserInfo" or "CcTuiBrowserMuted"
        line:append(prefix, prefix_hl)

        -- Add conversation number and title
        local title = conv.title or "Untitled Conversation"
        title = title:gsub("\n", " ") -- Remove newlines

        -- Truncate title if too long
        local available_width = width - DEFAULTS.LINE_PREFIX_RESERVE -- Reserve space for prefix, number, etc.
        if self.show_metadata then
            available_width = available_width - DEFAULTS.METADATA_EXTRA_RESERVE -- More space needed for metadata
        end

        if #title > available_width then
            title = title:sub(1, available_width - 3) .. "..."
        end

        local number_text = string.format("%d. ", i)
        line:append(number_text, is_selected and "CcTuiBrowserInfo" or "CcTuiBrowserMuted")
        line:append(title, is_selected and "CcTuiTabActive" or "Normal")

        -- Add metadata if enabled
        if self.show_metadata then
            if conv.timestamp and conv.timestamp ~= "unknown" then
                -- Parse and format timestamp nicely
                local year, month, day, hour, min = conv.timestamp:match("(%d+)-(%d+)-(%d+)T(%d+):(%d+)")
                if year then
                    local time_str = string.format(" [%s/%s %s:%s]", month, day, hour, min)
                    line:append(time_str, "CcTuiBrowserMuted")
                end
            end

            if conv.message_count then
                local msg_str = string.format(" (%d msgs)", conv.message_count)
                line:append(msg_str, "CcTuiBrowserMuted")
            end

            if conv.size then
                local size_str
                if conv.size < 1024 then
                    size_str = string.format(" %dB", conv.size)
                elseif conv.size < 1024 * 1024 then
                    size_str = string.format(" %.1fKB", conv.size / 1024)
                else
                    size_str = string.format(" %.1fMB", conv.size / (1024 * 1024))
                end
                line:append(size_str, "CcTuiBrowserMuted")
            end
        end

        table.insert(lines, line)
    end

    -- Add scroll indicators if needed
    if start_idx > 1 then
        local up_line = NuiLine()
        up_line:append("  ↑ ", "CcTuiBrowserMuted")
        up_line:append(string.format("(%d more above)", start_idx - 1), "CcTuiBrowserMuted")
        table.insert(lines, 1, up_line)
    end

    if end_idx < #self.conversations then
        local down_line = NuiLine()
        down_line:append("  ↓ ", "CcTuiBrowserMuted")
        down_line:append(string.format("(%d more below)", #self.conversations - end_idx), "CcTuiBrowserMuted")
        table.insert(lines, down_line)
    end

    return lines
end

---Render the browser content
function M:render()
    vim.api.nvim_buf_set_option(self.split.bufnr, "modifiable", true)

    local lines = {}
    local width = math.max(vim.api.nvim_win_get_width(self.split.winid or 0), DEFAULTS.MIN_WINDOW_WIDTH)

    -- Add header
    table.insert(lines, NuiLine())

    -- Project info line
    local header_line = NuiLine()
    header_line:append("  Project: ", "CcTuiBrowserMuted")
    header_line:append(self.project_name, "CcTuiBrowserInfo")
    if #self.conversations > 0 then
        header_line:append(string.format(" (%d conversations)", #self.conversations), "CcTuiBrowserMuted")
    end
    table.insert(lines, header_line)

    table.insert(lines, NuiLine())

    -- Add conversation list
    local list_lines = self:create_conversation_list()
    for _, line in ipairs(list_lines) do
        table.insert(lines, line)
    end

    -- Add keybindings help
    table.insert(lines, NuiLine())

    local separator_line = NuiLine()
    separator_line:append(string.rep("─", width), "CcTuiBrowserMuted")
    table.insert(lines, separator_line)

    local help_line = NuiLine()
    help_line:append("  ", "CcTuiBrowserMuted")
    help_line:append("[j/k]", "CcTuiBrowserInfo")
    help_line:append(" Navigate  ", "CcTuiBrowserMuted")
    help_line:append("[Tab]", "CcTuiBrowserInfo")
    help_line:append(" Toggle Metadata  ", "CcTuiBrowserMuted")
    help_line:append("[Enter]", "CcTuiBrowserInfo")
    help_line:append(" Open  ", "CcTuiBrowserMuted")
    help_line:append("[r]", "CcTuiBrowserInfo")
    help_line:append(" Refresh  ", "CcTuiBrowserMuted")
    help_line:append("[q]", "CcTuiBrowserInfo")
    help_line:append(" Close", "CcTuiBrowserMuted")
    table.insert(lines, help_line)

    -- Render all lines
    vim.api.nvim_buf_set_lines(self.split.bufnr, 0, -1, false, {})
    for i, line in ipairs(lines) do
        line:render(self.split.bufnr, -1, i)
    end

    vim.api.nvim_buf_set_option(self.split.bufnr, "modifiable", false)
end

---Navigate to next conversation
function M:next_conversation()
    if #self.conversations > 0 then
        self.current_index = math.min(self.current_index + 1, #self.conversations)
        self:render()
    end
end

---Navigate to previous conversation
function M:prev_conversation()
    if #self.conversations > 0 then
        self.current_index = math.max(self.current_index - 1, 1)
        self:render()
    end
end

---Navigate to first conversation
function M:first_conversation()
    if #self.conversations > 0 then
        self.current_index = 1
        self:render()
    end
end

---Navigate to last conversation
function M:last_conversation()
    if #self.conversations > 0 then
        self.current_index = #self.conversations
        self:render()
    end
end

---Toggle metadata display
function M:toggle_metadata()
    self.show_metadata = not self.show_metadata
    self:render()
end

---Select current conversation and trigger callback
function M:select_current()
    if #self.conversations == 0 then
        return
    end

    local conv = self.conversations[self.current_index]
    if conv and self.on_select_callback then
        self:close()
        self.on_select_callback(conv.path)
    end
end

---Refresh conversation list
function M:refresh()
    self:load_conversations()
    self:render()
end

---Show the browser
function M:show()
    self.split:mount()

    -- Apply keymaps
    for key, handler in pairs(self.keymaps) do
        vim.keymap.set("n", key, handler, {
            buffer = self.split.bufnr,
            noremap = true,
            silent = true,
        })
    end

    self:render()
end

---Close the browser
function M:close()
    if self.split then
        -- Buffer-local keymaps are automatically cleaned up when buffer is unmounted
        self.split:unmount()
    end
end

return M
