---@brief [[
--- View tab for CC-TUI tabbed interface
--- Shows tree view of selected conversation from Browse tab
---@brief ]]

local BaseView = require("cc-tui.ui.views.base")
local NuiLine = require("nui.line")
local log = require("cc-tui.utils.log")

-- Import existing UI components we can reuse
local ContentRenderer = require("cc-tui.ui.content_renderer")
local DataLoader = require("cc-tui.core.data_loader")

---@class CcTui.UI.ViewView:CcTui.UI.View
---@field messages CcTui.Message[] Current conversation messages
---@field tree_data CcTui.BaseNode? Current conversation tree
---@field selected_index number Currently selected tree node index
---@field expanded_nodes table<string, boolean> Track which nodes are expanded
---@field conversation_path string? Path to currently loaded conversation file
local ViewView = setmetatable({}, { __index = BaseView })
ViewView.__index = ViewView

---Create a new view tab instance
---@param manager CcTui.UI.TabbedManager Parent tabbed manager
---@return CcTui.UI.ViewView view New view tab instance
function ViewView.new(manager)
    local self = BaseView.new(manager, "view")
    setmetatable(self, ViewView)

    self.messages = {}
    self.tree_data = nil
    self.selected_index = 1
    self.expanded_nodes = {}
    self.conversation_path = nil

    -- Don't load data initially - wait for selection from Browse
    self.empty_message = "Select a conversation from the Browse tab to view"

    -- Setup keymaps
    self:setup_keymaps()

    return self
end

---Load conversation data from a file path
---@param conversation_path string? Path to conversation file
function ViewView:load_conversation(conversation_path)
    if not conversation_path then
        -- Clear if no path provided
        self.messages = {}
        self.tree_data = nil
        self.conversation_path = nil
        self.empty_message = "Select a conversation from the Browse tab to view"
        return
    end

    self.conversation_path = conversation_path
    self.empty_message = nil

    -- Use DataLoader to load the specific conversation
    DataLoader.load_conversation(conversation_path, function(messages, root, _, path)
        self.messages = messages or {}
        self.tree_data = root
        self.conversation_path = path

        -- Set initial expanded state for root nodes
        if self.tree_data and self.tree_data.children then
            for _, child in ipairs(self.tree_data.children) do
                self.expanded_nodes[child.id or tostring(child)] = true
            end
        end

        log.debug("ViewView", string.format("Loaded conversation with %d messages", #self.messages))

        -- Trigger re-render if manager exists
        if self.manager then
            self.manager:render()
        end
    end)
end

---Load specific conversation by file path (alias for backward compatibility)
---@param conversation_path string Path to conversation JSONL file
function ViewView:load_specific_conversation(conversation_path)
    vim.validate({
        conversation_path = { conversation_path, "string" },
    })

    self.conversation_path = conversation_path

    -- Use DataLoader to load the specific conversation
    DataLoader.load_conversation(conversation_path, function(messages, root, _, path)
        self.messages = messages or {}
        self.tree_data = root
        self.conversation_path = path

        -- Reset expansion state and selection
        self.expanded_nodes = {}
        self.selected_index = 1

        -- Set initial expanded state for root nodes
        if self.tree_data and self.tree_data.children then
            for _, child in ipairs(self.tree_data.children) do
                self.expanded_nodes[child.id or tostring(child)] = true
            end
        end

        log.debug("ViewView", string.format("Loaded specific conversation: %s (%d messages)", path, #self.messages))

        -- Trigger re-render through manager
        if self.manager then
            vim.schedule(function()
                self.manager:render()
            end)
        end
    end)
end

---Flatten tree for display with indentation and expansion state
---@param node CcTui.BaseNode Tree node to flatten
---@param level number Indentation level
---@param result table[] Accumulated flattened nodes
---@param index number Running index counter
---@param expanded_nodes table<string, boolean> Current expansion state
---@return number index Updated index counter
local function flatten_tree(node, level, result, index, expanded_nodes)
    if not node then
        return index
    end

    -- Add current node to result
    table.insert(result, {
        node = node,
        level = level,
        index = index,
    })
    index = index + 1

    -- Add children only if node is expanded
    if node.children and #node.children > 0 then
        local node_key = node.id or tostring(node)
        local is_expanded = expanded_nodes[node_key]

        if is_expanded then
            for _, child in ipairs(node.children) do
                index = flatten_tree(child, level + 1, result, index, expanded_nodes)
            end
        end
    end

    return index
end

---Get flattened tree for display
---@return table[] flattened Flattened tree nodes with display info
function ViewView:get_flattened_tree()
    if not self.tree_data then
        return {}
    end

    local flattened = {}
    flatten_tree(self.tree_data, 0, flattened, 1, self.expanded_nodes)
    return flattened
end

---Get node display text
---@param node CcTui.BaseNode Tree node
---@return string text Display text for node
---@return string highlight Highlight group for node
local function get_node_display_text(node)
    if not node then
        return "Unknown Node", "CcTuiMuted"
    end

    -- Handle different node types
    if node.type == "conversation" then
        return "📝 " .. (node.title or "Conversation"), "CcTuiTitle"
    elseif node.type == "message" then
        local role = node.role or "unknown"
        local role_icons = {
            user = "👤",
            assistant = "🤖",
            system = "⚙️",
        }
        local icon = role_icons[role] or "💬"

        local preview = node.preview or node.content or ""
        preview = preview:gsub("\n", " ") -- Remove newlines
        preview = string.sub(preview, 1, 60) -- Limit preview length

        local highlight = "Normal"
        if role == "user" then
            highlight = "CcTuiInfo"
        elseif role == "assistant" then
            highlight = "String"
        elseif role == "system" then
            highlight = "CcTuiMuted"
        end

        return string.format("%s %s: %s", icon, role, preview), highlight
    else
        -- Generic node
        local text = node.title or node.name or node.text or "Node"
        return "• " .. text, "Normal"
    end
end

---Render current conversation tree
---@param available_height number Available height for content
---@return NuiLine[] lines Current conversation content lines
function ViewView:render(available_height)
    local lines = {}
    local width = self.manager:get_width()

    -- Header
    local header_line = NuiLine()
    header_line:append("  📋 View Conversation", "CcTuiInfo")
    if self.conversation_path then
        local filename = vim.fn.fnamemodify(self.conversation_path, ":t:r")
        header_line:append(string.format(" - %s", filename), "CcTuiMuted")
    end
    if #self.messages > 0 then
        header_line:append(string.format(" (%d messages)", #self.messages), "CcTuiMuted")
    end
    table.insert(lines, header_line)

    table.insert(lines, self:create_empty_line())

    -- Check if we have conversation data
    if not self.tree_data then
        if self.empty_message then
            table.insert(lines, self:create_padded_line(self.empty_message, 4, "CcTuiMuted"))
        else
            table.insert(lines, self:create_padded_line("No conversation loaded", 4, "CcTuiMuted"))
        end
        table.insert(lines, self:create_padded_line("Press 'B' to browse conversations", 4, "CcTuiMuted"))
        return lines
    end

    -- Get flattened tree for display
    local flattened = self:get_flattened_tree()

    if #flattened == 0 then
        table.insert(lines, self:create_padded_line("Empty conversation", 4, "CcTuiMuted"))
        return lines
    end

    -- Calculate how many tree items we can show
    local header_lines = 3
    local items_to_show = math.min(#flattened, available_height - header_lines)

    -- Render tree items
    for i = 1, items_to_show do
        local item = flattened[i]
        local node = item.node
        local level = item.level
        local is_selected = i == self.selected_index

        local line = NuiLine()

        -- Selection indicator
        local indicator = is_selected and "►" or " "
        line:append(" " .. indicator .. " ", is_selected and "CcTuiInfo" or "CcTuiMuted")

        -- Indentation for tree structure
        local indent = string.rep("  ", level)
        line:append(indent)

        -- Expansion indicator for nodes with children
        if node.children and #node.children > 0 then
            local expanded = self.expanded_nodes[node.id or tostring(node)]
            local expand_icon = expanded and "▼" or "▶"
            line:append(expand_icon .. " ", "CcTuiMuted")
        else
            line:append("  ")
        end

        -- Node content
        local text, highlight = get_node_display_text(node)
        local available_text_width = width - 10 - (level * 2) -- Account for indicators and indentation
        local truncated_text = self:truncate_text(text, available_text_width)

        line:append(truncated_text, is_selected and "CcTuiTabActive" or highlight)

        table.insert(lines, line)
    end

    -- Show navigation help if we have items
    if #flattened > 0 then
        table.insert(lines, self:create_empty_line())
        table.insert(lines, self:create_separator_line(width, "─", "CcTuiMuted"))

        local help_line = NuiLine()
        help_line:append(
            "  [j/k] Navigate  [Space/Enter/Tab] Expand/Content  [h/l] Collapse/Expand  [o/c] Expand/Collapse All  [x/X] Close Content",
            "CcTuiMuted"
        )
        table.insert(lines, help_line)
    end

    return lines
end

---Navigate to next item in tree
function ViewView:next_item()
    local flattened = self:get_flattened_tree()
    if #flattened > 0 then
        self.selected_index = math.min(self.selected_index + 1, #flattened)
    end
end

---Navigate to previous item in tree
function ViewView:prev_item()
    if self.selected_index > 1 then
        self.selected_index = self.selected_index - 1
    end
end

---Toggle expansion of selected node or show content popup
function ViewView:toggle_selected_node()
    local flattened = self:get_flattened_tree()
    if self.selected_index <= #flattened then
        local item = flattened[self.selected_index]
        local node = item.node

        -- Debug what kind of node we have
        log.debug(
            "CurrentView",
            string.format(
                "Toggle node: type=%s, has_data=%s, has_children=%s",
                node.type or "nil",
                node.data and "yes" or "no",
                node.children and #node.children > 0 and "yes" or "no"
            )
        )

        if node.data then
            log.debug(
                "CurrentView",
                string.format("Node data: type=%s, id=%s", node.data.type or "nil", node.data.id or "nil")
            )
        end

        -- Handle result nodes with content popups (like original tree system)
        if node.data and node.data.type == "result" then
            self:toggle_result_content(node)
        elseif node.children and #node.children > 0 then
            -- Handle regular tree expansion
            local node_key = node.id or tostring(node)
            self.expanded_nodes[node_key] = not self.expanded_nodes[node_key]
        end
    end
end

---Toggle content display for result nodes (matches original tree.lua functionality)
function ViewView:toggle_result_content(node)
    if not node.data or node.data.type ~= "result" then
        log.debug("ViewView", "Node is not a result type")
        return
    end

    local result_data = node.data
    log.debug(
        "CurrentView",
        string.format("Attempting to toggle result content: id=%s, type=%s", result_data.id or "nil", result_data.type)
    )

    -- Check if content window is already open
    if ContentRenderer.is_content_window_open(result_data.id) then
        -- Close existing content window
        local closed = ContentRenderer.close_content_window(result_data.id)
        if closed then
            log.debug("ViewView", string.format("Closed content window for result: %s", result_data.id))
        end
        return
    end

    -- Debug the result data structure
    log.debug(
        "CurrentView",
        string.format(
            "Result data: id=%s, content_len=%d, has_structured=%s, use_rich_display=%s",
            result_data.id or "nil",
            result_data.content and #result_data.content or 0,
            result_data.structured_content and "yes" or "no",
            tostring(result_data.use_rich_display)
        )
    )

    -- Check if we have the required structured_content
    if not result_data.structured_content then
        log.debug("ViewView", "No structured_content available, creating minimal structure")
        result_data.structured_content = {
            type = "text",
            content = result_data.content or "",
        }
    end

    -- Use display decision from result data
    local should_use_rich_display = result_data.use_rich_display
    if should_use_rich_display == nil then
        -- Default to true for content popups
        should_use_rich_display = true
    end

    if should_use_rich_display then
        -- Use rich content display via ContentRenderer
        local tool_name = result_data.tool_name -- May need to find parent tool

        log.debug(
            "CurrentView",
            string.format(
                "Calling ContentRenderer.render_content with: id=%s, tool=%s, content_len=%d",
                result_data.id,
                tool_name or "nil",
                result_data.content and #result_data.content or 0
            )
        )

        local success, content_window = pcall(
            ContentRenderer.render_content,
            result_data.id,
            tool_name,
            result_data.content or "",
            vim.api.nvim_get_current_win(),
            result_data.structured_content,
            result_data.stream_context
        )

        if success and content_window then
            log.debug("ViewView", string.format("Opened content window for result: %s", result_data.id))
        else
            log.debug("ViewView", string.format("Failed to open content window: %s", tostring(content_window)))
            vim.notify("Failed to open content window: " .. tostring(content_window), vim.log.levels.ERROR)
        end
    else
        -- Fall back to normal tree expansion for small content
        log.debug("ViewView", "Using fallback tree expansion")
        if node.children and #node.children > 0 then
            local node_key = node.id or tostring(node)
            self.expanded_nodes[node_key] = not self.expanded_nodes[node_key]
        end
    end
end

---Expand all nodes
function ViewView:expand_all()
    local function expand_recursive(node)
        if node.children and #node.children > 0 then
            self.expanded_nodes[node.id or tostring(node)] = true
            for _, child in ipairs(node.children) do
                expand_recursive(child)
            end
        end
    end

    if self.tree_data then
        expand_recursive(self.tree_data)
    end
end

---Collapse all nodes
function ViewView:collapse_all()
    self.expanded_nodes = {}
end

---Set up current view specific keymaps
function ViewView:setup_keymaps()
    self.keymaps = {
        ["j"] = function()
            self:next_item()
        end,
        ["k"] = function()
            self:prev_item()
        end,
        ["<Down>"] = function()
            self:next_item()
        end,
        ["<Up>"] = function()
            self:prev_item()
        end,
        ["<Space>"] = function()
            self:toggle_selected_node()
        end,
        ["<CR>"] = function()
            self:toggle_selected_node()
        end,
        ["<Tab>"] = function()
            self:toggle_selected_node()
        end,
        ["h"] = function()
            local flattened = self:get_flattened_tree()
            if self.selected_index <= #flattened then
                local item = flattened[self.selected_index]
                self.expanded_nodes[item.node.id or tostring(item.node)] = false
            end
        end,
        ["l"] = function()
            local flattened = self:get_flattened_tree()
            if self.selected_index <= #flattened then
                local item = flattened[self.selected_index]
                self.expanded_nodes[item.node.id or tostring(item.node)] = true
            end
        end,
        ["o"] = function()
            self:expand_all()
        end,
        ["c"] = function()
            self:collapse_all()
        end,
        ["x"] = function()
            -- Close content window for selected result node
            local flattened = self:get_flattened_tree()
            if self.selected_index <= #flattened then
                local item = flattened[self.selected_index]
                local node = item.node
                if node.data and node.data.type == "result" then
                    local closed = ContentRenderer.close_content_window(node.data.id)
                    if closed then
                        vim.notify("Closed content window", vim.log.levels.INFO)
                    else
                        vim.notify("No content window to close", vim.log.levels.WARN)
                    end
                end
            end
        end,
        ["X"] = function()
            -- Close all content windows
            local count = ContentRenderer.close_all_content_windows()
            if count > 0 then
                vim.notify(string.format("Closed %d content window(s)", count), vim.log.levels.INFO)
            else
                vim.notify("No content windows to close", vim.log.levels.INFO)
            end
        end,
    }
end

---Refresh current conversation data
function ViewView:refresh()
    self:load_conversation_data()
    log.debug("ViewView", "Refreshed current conversation data")
end

return ViewView
