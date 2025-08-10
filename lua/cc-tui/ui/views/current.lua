---@brief [[
--- Current conversation view for CC-TUI tabbed interface
--- Shows tree view of current conversation (replaces :CcTui)
---@brief ]]

local BaseView = require("cc-tui.ui.views.base")
local NuiLine = require("nui.line")
local log = require("cc-tui.utils.log")

-- Import existing UI components we can reuse
local DataLoader = require("cc-tui.core.data_loader")

---@class CcTui.UI.CurrentView:CcTui.UI.View
---@field messages CcTui.Message[] Current conversation messages
---@field tree_data CcTui.BaseNode? Current conversation tree
---@field selected_index number Currently selected tree node index
---@field expanded_nodes table<string, boolean> Track which nodes are expanded
local CurrentView = setmetatable({}, { __index = BaseView })
CurrentView.__index = CurrentView

---Create a new current conversation view instance
---@param manager CcTui.UI.TabbedManager Parent tabbed manager
---@return CcTui.UI.CurrentView view New current view instance
function CurrentView.new(manager)
    local self = BaseView.new(manager, "current")
    setmetatable(self, CurrentView)

    self.messages = {}
    self.tree_data = nil
    self.selected_index = 1
    self.expanded_nodes = {}

    -- Load initial conversation data
    self:load_conversation_data()

    -- Setup keymaps
    self:setup_keymaps()

    return self
end

---Load current conversation data
function CurrentView:load_conversation_data()
    -- Use existing data loader to get current conversation
    local root, err, messages = DataLoader.load_test_data()

    if not root then
        log.debug("CurrentView", "Failed to load conversation data: " .. (err or "unknown error"))
        self.messages = {}
        self.tree_data = nil
        return
    end

    self.messages = messages or {}
    self.tree_data = root

    -- Set initial expanded state for root nodes
    if self.tree_data and self.tree_data.children then
        for _, child in ipairs(self.tree_data.children) do
            self.expanded_nodes[child.id or tostring(child)] = true
        end
    end

    log.debug("CurrentView", string.format("Loaded conversation with %d messages", #self.messages))
end

---Flatten tree for display with indentation
---@param node CcTui.BaseNode Tree node to flatten
---@param level number Indentation level
---@param result table[] Accumulated flattened nodes
---@param index number Running index counter
---@return number index Updated index counter
local function flatten_tree(node, level, result, index)
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

    -- Add children if node is expanded
    if node.children and #node.children > 0 then
        for _, child in ipairs(node.children) do
            index = flatten_tree(child, level + 1, result, index)
        end
    end

    return index
end

---Get flattened tree for display
---@return table[] flattened Flattened tree nodes with display info
function CurrentView:get_flattened_tree()
    if not self.tree_data then
        return {}
    end

    local flattened = {}
    flatten_tree(self.tree_data, 0, flattened, 1)
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
function CurrentView:render(available_height)
    local lines = {}
    local width = self.manager:get_width()

    -- Header
    local header_line = NuiLine()
    header_line:append("  📋 Current Conversation", "CcTuiInfo")
    if #self.messages > 0 then
        header_line:append(string.format(" (%d messages)", #self.messages), "CcTuiMuted")
    end
    table.insert(lines, header_line)

    table.insert(lines, self:create_empty_line())

    -- Check if we have conversation data
    if not self.tree_data then
        table.insert(lines, self:create_padded_line("No conversation loaded", 4, "CcTuiMuted"))
        table.insert(
            lines,
            self:create_padded_line("Start a conversation with Claude to see content here", 4, "CcTuiMuted")
        )
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
            "  [j/k] Navigate  [Space/Enter] Expand/Select  [h/l] Collapse/Expand  [o/c] Expand/Collapse All",
            "CcTuiMuted"
        )
        table.insert(lines, help_line)
    end

    return lines
end

---Navigate to next item in tree
function CurrentView:next_item()
    local flattened = self:get_flattened_tree()
    if #flattened > 0 then
        self.selected_index = math.min(self.selected_index + 1, #flattened)
    end
end

---Navigate to previous item in tree
function CurrentView:prev_item()
    if self.selected_index > 1 then
        self.selected_index = self.selected_index - 1
    end
end

---Toggle expansion of selected node
function CurrentView:toggle_selected_node()
    local flattened = self:get_flattened_tree()
    if self.selected_index <= #flattened then
        local item = flattened[self.selected_index]
        local node = item.node

        if node.children and #node.children > 0 then
            local node_key = node.id or tostring(node)
            self.expanded_nodes[node_key] = not self.expanded_nodes[node_key]
        end
    end
end

---Expand all nodes
function CurrentView:expand_all()
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
function CurrentView:collapse_all()
    self.expanded_nodes = {}
end

---Set up current view specific keymaps
function CurrentView:setup_keymaps()
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
    }
end

---Refresh current conversation data
function CurrentView:refresh()
    self:load_conversation_data()
    log.debug("CurrentView", "Refreshed current conversation data")
end

return CurrentView
