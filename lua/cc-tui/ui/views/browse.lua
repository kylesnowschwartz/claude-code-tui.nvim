---@brief [[
--- Browse conversations view for CC-TUI tabbed interface
--- Shows conversation browser in tabbed interface
---@brief ]]

local BaseView = require("cc-tui.ui.views.base")
local NuiLine = require("nui.line")
local ProjectDiscovery = require("cc-tui.services.project_discovery")
local log = require("cc-tui.utils.log")

---@class CcTui.UI.BrowseView:CcTui.UI.View
---@field project_name string Current project name
---@field conversations CcTui.ConversationMetadata[] List of conversations
---@field current_index number Currently selected conversation index
---@field show_metadata boolean Whether to show metadata for each conversation
local BrowseView = setmetatable({}, { __index = BaseView })
BrowseView.__index = BrowseView

-- UI Constants
local BROWSE_DEFAULTS = {
    LINE_PREFIX_RESERVE = 10,
    METADATA_EXTRA_RESERVE = 40,
}

---Create a new browse conversations view instance
---@param manager CcTui.UI.TabbedManager Parent tabbed manager
---@return CcTui.UI.BrowseView view New browse view instance
function BrowseView.new(manager)
    local self = BaseView.new(manager, "browse")
    setmetatable(self, BrowseView)

    self.current_index = 1
    self.show_metadata = false
    self.conversations = {}

    -- Get current project
    local cwd = vim.fn.getcwd()
    self.project_name = ProjectDiscovery.get_project_name(cwd)

    -- Load conversations
    self:load_conversations()

    -- Set up browse-specific keymaps
    self:setup_keymaps()

    return self
end

---Load conversations for current project
function BrowseView:load_conversations()
    if not ProjectDiscovery.project_exists(self.project_name) then
        log.debug("BrowseView", string.format("Project %s not found", self.project_name))
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

    log.debug("BrowseView", string.format("Loaded %d conversations", #self.conversations))
end

---Asynchronously load metadata for initial conversations to display
function BrowseView:load_initial_metadata_async()
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
                    -- Trigger re-render through manager
                    if self.manager and self.manager.current_tab == "browse" then
                        self.manager:render()
                    end
                end)
            end
        end)
    end
end

---Asynchronously load metadata for a single conversation and re-render
---@param conv CcTui.ConversationMetadata Conversation to enrich
---@param index number Index in conversations array
function BrowseView:load_conversation_metadata_async(conv, index)
    ProjectDiscovery.enrich_conversation_metadata_async(conv, function(enriched_conv)
        -- Update the conversation in place
        self.conversations[index] = enriched_conv

        -- Re-render to show the updated metadata
        vim.schedule(function()
            if self.manager and self.manager.current_tab == "browse" then
                self.manager:render()
            end
        end)
    end)
end

---Create conversation list for display
---@param available_height number Available height for conversation list
---@param width number Available width
---@return NuiLine[] lines Conversation list lines
function BrowseView:create_conversation_list(available_height, width)
    local lines = {}

    if #self.conversations == 0 then
        local empty_line = NuiLine()
        empty_line:append("  No conversations found in project: ", "CcTuiMuted")
        empty_line:append(self.project_name or "unknown", "CcTuiInfo")
        table.insert(lines, empty_line)

        local help_line = NuiLine()
        help_line:append("  Start a new conversation with: ", "CcTuiMuted")
        help_line:append("claude", "CcTuiInfo")
        table.insert(lines, help_line)

        return lines
    end

    -- Calculate scrolling window
    local window_height = math.max(5, available_height)
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

    -- Add scroll indicators if needed
    if start_idx > 1 then
        local up_line = NuiLine()
        up_line:append("  ↑ ", "CcTuiMuted")
        up_line:append(string.format("(%d more above)", start_idx - 1), "CcTuiMuted")
        table.insert(lines, up_line)
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
        local prefix_hl = is_selected and "CcTuiInfo" or "CcTuiMuted"
        line:append(prefix, prefix_hl)

        -- Add conversation number and title
        local title = conv.title or "Untitled Conversation"
        title = title:gsub("\n", " ") -- Remove newlines

        -- Truncate title if too long
        local available_width = width - BROWSE_DEFAULTS.LINE_PREFIX_RESERVE
        if self.show_metadata then
            available_width = available_width - BROWSE_DEFAULTS.METADATA_EXTRA_RESERVE
        end

        title = self:truncate_text(title, available_width)

        local number_text = string.format("%d. ", i)
        line:append(number_text, is_selected and "CcTuiInfo" or "CcTuiMuted")
        line:append(title, is_selected and "CcTuiTabActive" or "Normal")

        -- Add metadata if enabled
        if self.show_metadata then
            if conv.timestamp and conv.timestamp ~= "unknown" then
                -- Parse and format timestamp nicely
                local year, month, day, hour, min = conv.timestamp:match("(%d+)-(%d+)-(%d+)T(%d+):(%d+)")
                if year then
                    local time_str = string.format(" [%s/%s %s:%s]", month, day, hour, min)
                    line:append(time_str, "CcTuiMuted")
                end
            end

            if conv.message_count then
                local msg_str = string.format(" (%d msgs)", conv.message_count)
                line:append(msg_str, "CcTuiMuted")
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
                line:append(size_str, "CcTuiMuted")
            end
        end

        table.insert(lines, line)
    end

    if end_idx < #self.conversations then
        local down_line = NuiLine()
        down_line:append("  ↓ ", "CcTuiMuted")
        down_line:append(string.format("(%d more below)", #self.conversations - end_idx), "CcTuiMuted")
        table.insert(lines, down_line)
    end

    return lines
end

---Render browse conversations content
---@param available_height number Available height for content
---@return NuiLine[] lines Browse conversations content lines
function BrowseView:render(available_height)
    local lines = {}
    local width = self.manager:get_width()

    -- Debug validation for test environments
    if type(width) ~= "number" then
        log.debug("BrowseView", string.format("Invalid width type: %s, value: %s", type(width), vim.inspect(width)))
        width = 80 -- Fallback width for tests
    end

    -- Header
    local header_line = NuiLine()
    header_line:append("  🗂  Browse Conversations", "CcTuiInfo")
    header_line:append(" - ", "CcTuiMuted")
    header_line:append(self.project_name, "CcTuiInfo")
    if #self.conversations > 0 then
        header_line:append(string.format(" (%d conversations)", #self.conversations), "CcTuiMuted")
    end
    table.insert(lines, header_line)

    table.insert(lines, self:create_empty_line())

    -- Calculate space for conversation list
    local header_lines = 2
    local footer_lines = 3 -- Space for help text
    local list_height = available_height - header_lines - footer_lines

    -- Add conversation list
    local list_lines = self:create_conversation_list(list_height, width)
    for _, line in ipairs(list_lines) do
        table.insert(lines, line)
    end

    -- Add help footer
    if #self.conversations > 0 then
        table.insert(lines, self:create_empty_line())
        table.insert(lines, self:create_separator_line(width, "─", "CcTuiMuted"))

        local help_line = NuiLine()
        help_line:append("  [j/k] Navigate  [Tab] Toggle Metadata  [Enter] Open  [r] Refresh", "CcTuiMuted")
        table.insert(lines, help_line)
    end

    return lines
end

---Navigate to next conversation
function BrowseView:next_conversation()
    if #self.conversations > 0 then
        self.current_index = math.min(self.current_index + 1, #self.conversations)
    end
end

---Navigate to previous conversation
function BrowseView:prev_conversation()
    if #self.conversations > 0 then
        self.current_index = math.max(self.current_index - 1, 1)
    end
end

---Navigate to first conversation
function BrowseView:first_conversation()
    if #self.conversations > 0 then
        self.current_index = 1
    end
end

---Navigate to last conversation
function BrowseView:last_conversation()
    if #self.conversations > 0 then
        self.current_index = #self.conversations
    end
end

---Toggle metadata display
function BrowseView:toggle_metadata()
    self.show_metadata = not self.show_metadata
end

---Select current conversation
function BrowseView:select_current()
    if #self.conversations == 0 then
        return
    end

    local conv = self.conversations[self.current_index]
    if conv then
        log.debug("BrowseView", string.format("Selected conversation: %s", conv.path))

        -- Set the conversation in the tabbed manager
        if self.manager then
            self.manager:set_current_conversation(conv.path)
            vim.notify(string.format("Loading conversation: %s", conv.title or "Untitled"), vim.log.levels.INFO)

            -- Switch to current tab to show loaded conversation
            self.manager:switch_to_tab("current")
        end
    end
end

---Set up browse view specific keymaps
function BrowseView:setup_keymaps()
    self.keymaps = {
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
        ["<Tab>"] = function()
            self:toggle_metadata()
        end,
        ["<CR>"] = function()
            self:select_current()
        end,
        ["r"] = function()
            self:refresh()
        end,
    }
end

---Refresh conversations list
function BrowseView:refresh()
    self:load_conversations()
    log.debug("BrowseView", "Refreshed conversations list")
end

return BrowseView
