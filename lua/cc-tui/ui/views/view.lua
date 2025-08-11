---@brief [[
--- View tab for CC-TUI tabbed interface
--- Renders conversation trees as NuiLine[] following MCPHub patterns
---@brief ]]

local BaseView = require("cc-tui.ui.views.base")
local log = require("cc-tui.utils.log")

-- Import services and UI components
local ClaudeState = require("cc-tui.services.claude_state")
local ContentRenderer = require("cc-tui.ui.content_renderer")
local DataLoader = require("cc-tui.core.data_loader")
local ProjectDiscovery = require("cc-tui.services.project_discovery")

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

    -- Try to load a default conversation (security handled at path mapping level)
    self:load_default_conversation()

    -- Setup keymaps (from working commit)
    self:setup_keymaps()

    -- Setup cursor tracking for native navigation
    self:setup_cursor_tracking()

    return self
end

---Load the default conversation (most recent)
function ViewView:load_default_conversation()
    -- Load the most recent conversation (security handled at path mapping level)
    local cwd = vim.fn.getcwd()
    local project_name = ProjectDiscovery.get_project_name(cwd)
    local recent = ClaudeState.get_most_recent_conversation(project_name)

    if recent and recent.path then
        log.debug("ViewView", "Loading most recent conversation")
        self:load_conversation(recent.path)
    else
        -- No conversations available
        self.empty_message = "No conversations found. Start a new conversation or select one from Browse tab"
    end
end

---Load conversation data from a file path
---@param conversation_path string? Path to conversation file
function ViewView:load_conversation(conversation_path)
    -- Security is now handled at the path mapping level in ClaudePathMapper

    if not conversation_path then
        -- Clear if no path provided
        self.messages = {}
        self.tree_data = nil
        self.conversation_path = nil
        self.tree_component = nil
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

        -- Reset selection and expansion state
        self.selected_index = 1
        self.expanded_nodes = {}

        -- Set initial expanded state for root session node only
        if self.tree_data then
            self.expanded_nodes[self.tree_data.id or tostring(self.tree_data)] = true
        end

        log.debug("ViewView", string.format("Loaded conversation with %d messages", #self.messages))

        -- Trigger a re-render if this tab is currently active
        if self.manager and self.manager.current_tab == "view" then
            -- Re-render the entire tab to show new conversation
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

    self:load_conversation(conversation_path)
end

---Flatten tree for display with indentation and expansion state (from working commit)
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

---Get node display text (from working commit)
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
    elseif node.type == "text" then
        -- Simple text node display
        local text = node.text or "Text"
        return text, "Comment"
    elseif node.type == "tool" then
        -- Tool nodes
        local text = node.text or "Tool"
        return text, "Function" -- Use function highlight for tools
    elseif node.type == "result" then
        -- Result nodes
        local text = node.text or "Result"
        if node.is_error then
            return "❌ " .. text, "ErrorMsg"
        else
            return "✅ " .. text, "String"
        end
    else
        -- Generic node
        local text = node.title or node.name or node.text or "Node"
        return "• " .. text, "Normal"
    end
end

---Get flattened tree for display (from working commit)
---@return table[] flattened Flattened tree nodes with display info
function ViewView:get_flattened_tree()
    if not self.tree_data then
        return {}
    end

    local flattened = {}
    flatten_tree(self.tree_data, 0, flattened, 1, self.expanded_nodes)
    return flattened
end

---Render tree as NuiLine[] using flattened tree approach (MCPHub compatible)
---@param available_height number Available height for tree content
---@return NuiLine[] lines Tree content as NuiLine array
function ViewView:render_tree_as_lines(available_height)
    local lines = {}
    local width = self.manager:get_width()

    if not self.tree_data then
        return lines
    end

    -- Get flattened tree for display (same as working commit)
    local flattened = self:get_flattened_tree()

    if #flattened == 0 then
        local empty_line = self:create_padded_line("Empty conversation", 4, "CcTuiMuted")
        table.insert(lines, empty_line)
        return lines
    end

    -- Render ALL tree items (let Neovim handle scrolling)
    -- This matches the working commit behavior where all items were rendered
    local items_to_show = #flattened

    -- Render tree items (same logic as working commit)
    for i = 1, items_to_show do
        local item = flattened[i]
        local node = item.node
        local level = item.level
        local is_selected = i == self.selected_index

        local line = require("nui.line")()

        -- Selection indicator (same as working commit)
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

        local help_line = require("nui.line")()
        help_line:append(
            "  [j/k] Navigate  [Space/Enter/Tab] Expand/Content  [h/l] Collapse/Expand  [o/c] Expand/Collapse All  [x/X] Close Content",
            "CcTuiMuted"
        )
        table.insert(lines, help_line)
    end

    return lines
end

---Setup working keymaps following MCPHub pattern - let Neovim handle j/k natively
function ViewView:setup_keymaps()
    self.keymaps = {
        -- Remove j/k overrides to allow native Neovim navigation
        -- j and k will work naturally and trigger CursorMoved events
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
            self:collapse_selected_node()
        end,
        ["l"] = function()
            self:expand_selected_node()
        end,
        ["o"] = function()
            self:expand_all()
            self:refresh_display()
        end,
        ["c"] = function()
            self:collapse_all()
            self:refresh_display()
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

---Setup CursorMoved event handler following MCPHub pattern
function ViewView:setup_cursor_tracking()
    if not self.manager or not self.manager.buffer then
        return
    end

    -- Clear any existing autocmds
    if self.cursor_group then
        vim.api.nvim_del_augroup_by_id(self.cursor_group)
    end

    -- Create autocmd group for cursor tracking
    self.cursor_group = vim.api.nvim_create_augroup("CcTuiViewCursor", { clear = true })

    vim.api.nvim_create_autocmd("CursorMoved", {
        group = self.cursor_group,
        buffer = self.manager.buffer,
        callback = function()
            self:handle_cursor_move()
        end,
    })
end

---Handle cursor movement to update selected tree item
function ViewView:handle_cursor_move()
    if not self.manager or not self.manager.window or not vim.api.nvim_win_is_valid(self.manager.window) then
        return
    end

    local cursor = vim.api.nvim_win_get_cursor(self.manager.window)
    local line = cursor[1]

    -- Map cursor line to tree item index (but don't trigger re-render)
    local new_selected_index = self:line_to_tree_index(line)
    if new_selected_index and new_selected_index ~= self.selected_index then
        self.selected_index = new_selected_index
        -- Don't re-render during cursor movement - let Neovim handle the display
        -- The selection will be updated on the next natural render cycle
    end
end

---Map buffer line number to tree item index
---@param line_number number Current cursor line number
---@return number? index Tree item index or nil if not on a tree item
function ViewView:line_to_tree_index(line_number)
    -- Account for header (2 lines: title + empty line)
    local tree_line = line_number - 2

    -- Must be positive
    if tree_line < 1 then
        return 1 -- Default to first item if above tree area
    end

    local flattened = self:get_flattened_tree()
    if #flattened == 0 then
        return nil
    end

    -- Clamp to valid range
    if tree_line > #flattened then
        return #flattened
    end

    return tree_line
end

---Refresh display without moving cursor
function ViewView:refresh_display()
    if self.manager and self.manager.current_tab == "view" then
        self.manager:render()
    end
end

---Toggle expansion of selected node or show content popup (from working commit)
function ViewView:toggle_selected_node()
    local flattened = self:get_flattened_tree()
    if self.selected_index <= #flattened then
        local item = flattened[self.selected_index]
        local node = item.node

        -- Debug what kind of node we have
        log.debug(
            "ViewView",
            string.format(
                "Toggle node: type=%s, has_data=%s, has_children=%s",
                node.type or "nil",
                node.data and "yes" or "no",
                node.children and #node.children > 0 and "yes" or "no"
            )
        )

        -- Handle result nodes with content popups (like original tree system)
        if node.data and node.data.type == "result" then
            self:toggle_result_content(node)
        elseif node.children and #node.children > 0 then
            -- Handle regular tree expansion
            local node_key = node.id or tostring(node)
            self.expanded_nodes[node_key] = not self.expanded_nodes[node_key]
            self:refresh_display()
        end
    end
end

---Toggle content display for result nodes (from working commit)
function ViewView:toggle_result_content(node)
    if not node.data or node.data.type ~= "result" then
        log.debug("ViewView", "Node is not a result type")
        return
    end

    local result_data = node.data
    log.debug(
        "ViewView",
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

    -- Use display decision from result data
    local should_use_rich_display = result_data.use_rich_display
    if should_use_rich_display == nil then
        -- Default to true for content popups
        should_use_rich_display = true
    end

    if should_use_rich_display then
        -- Use rich content display via ContentRenderer
        local tool_name = result_data.tool_name

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
        if node.children and #node.children > 0 then
            local node_key = node.id or tostring(node)
            self.expanded_nodes[node_key] = not self.expanded_nodes[node_key]
        end
    end
end

---Expand all nodes (from working commit)
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

---Collapse all nodes (from working commit)
function ViewView:collapse_all()
    self.expanded_nodes = {}
end

---Expand the currently selected node
function ViewView:expand_selected_node()
    local flattened = self:get_flattened_tree()
    if self.selected_index <= #flattened then
        local item = flattened[self.selected_index]
        if item.node.children and #item.node.children > 0 then
            self.expanded_nodes[item.node.id or tostring(item.node)] = true
            self:refresh_display()
        end
    end
end

---Collapse the currently selected node
function ViewView:collapse_selected_node()
    local flattened = self:get_flattened_tree()
    if self.selected_index <= #flattened then
        local item = flattened[self.selected_index]
        if item.node.children and #item.node.children > 0 then
            self.expanded_nodes[item.node.id or tostring(item.node)] = false
            self:refresh_display()
        end
    end
end

---Refresh current conversation data (from working commit)
function ViewView:refresh()
    if self.conversation_path then
        self:load_conversation(self.conversation_path)
    end
    log.debug("ViewView", "Refreshed conversation data")
end

---Render the view tab content
---@param available_height number Available height for content
---@return NuiLine[] lines View content lines
function ViewView:render(available_height)
    local lines = {}

    -- Header
    local NuiLine = require("nui.line")
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

    -- Render conversation tree as NuiLine[] following MCPHub pattern
    local tree_lines = self:render_tree_as_lines(available_height - 4) -- Reserve space for header
    vim.list_extend(lines, tree_lines)

    return lines
end

---Called when this tab becomes active
function ViewView:on_activate()
    -- Following MCPHub pattern: no direct buffer manipulation in activate
    -- All rendering should go through the render() method that returns NuiLine[]
    -- This ensures proper integration with the tabbed interface
    log.debug("ViewView", "View tab activated")
end

---Called when this tab becomes inactive
function ViewView:on_deactivate()
    -- Following MCPHub pattern: cleanup if needed
    log.debug("ViewView", "View tab deactivated")
end

---Refresh current conversation data
function ViewView:refresh()
    if self.conversation_path then
        self:load_conversation(self.conversation_path)
    end
    log.debug("ViewView", "Refreshed conversation data")
end

return ViewView
