---@brief [[
--- View tab for CC-TUI tabbed interface
--- Uses NuiTree component for proper tree rendering with built-in scrolling
---@brief ]]

local BaseView = require("cc-tui.ui.views.base")
-- local NuiLine = require("nui.line")
local Config = require("cc-tui.config")
local Tree = require("cc-tui.ui.tree")
local log = require("cc-tui.utils.log")

-- Import services
local ClaudeState = require("cc-tui.services.claude_state")
local DataLoader = require("cc-tui.core.data_loader")
local ProjectDiscovery = require("cc-tui.services.project_discovery")

---@class CcTui.UI.ViewView:CcTui.UI.View
---@field messages CcTui.Message[] Current conversation messages
---@field tree_data CcTui.BaseNode? Current conversation tree
---@field conversation_path string? Path to currently loaded conversation file
---@field tree_component NuiTree? The actual NuiTree component
---@field tree_rendered boolean Whether tree is currently rendered
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
    self.conversation_path = nil
    self.tree_component = nil
    self.tree_rendered = false

    -- Try to load a default conversation (security handled at path mapping level)
    self:load_default_conversation()

    -- Tree keymaps will be set up when tree is rendered
    -- Tab switching keymaps are handled by BaseView

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

        log.debug("ViewView", string.format("Loaded conversation with %d messages", #self.messages))

        -- Trigger a re-render if this tab is currently active
        if self.manager and self.manager.current_tab == "view" then
            -- Only render tree since we're already in the view tab
            self:render_tree()
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

---Render tree in the current buffer
function ViewView:render_tree()
    if not self.tree_data then
        return
    end

    -- Get the current buffer from the tabbed manager's popup
    local bufnr = self.manager and self.manager.popup and self.manager.popup.bufnr
    if not bufnr then
        log.debug("ViewView", "No buffer available for tree rendering")
        return
    end

    -- Create or update tree component using helper methods
    local tree_config = self:get_tree_config()

    if self.tree_component then
        -- Update existing tree
        Tree.update_tree(self.tree_component, self.tree_data, tree_config)
    else
        -- Create new tree using the popup's buffer
        self.tree_component = Tree.create_tree(self.tree_data, tree_config, bufnr)
        -- Setup tree keybindings using helper
        self:setup_tree_keybindings(bufnr)
    end

    -- Make buffer modifiable temporarily for tree rendering
    vim.api.nvim_buf_set_option(bufnr, "modifiable", true)
    vim.api.nvim_buf_set_option(bufnr, "readonly", false)

    -- Render the tree
    self.tree_component:render()

    -- Set buffer back to readonly
    vim.api.nvim_buf_set_option(bufnr, "modifiable", false)
    vim.api.nvim_buf_set_option(bufnr, "readonly", true)

    self.tree_rendered = true
    log.debug("ViewView", "Tree rendered in buffer")
end

---Get tree configuration
---@return table tree_config Configuration for tree configuration
function ViewView:get_tree_config()
    return {
        icons = {
            expanded = "▼",
            collapsed = "▶",
            empty = " ",
        },
        colors = {
            session = "CcTuiSession",
            message = "CcTuiMessage",
            tool = "CcTuiTool",
            result = "CcTuiResult",
            text = "CcTuiText",
            error = "CcTuiError",
        },
    }
end

---Setup tree keybindings
---@param bufnr number Buffer number
function ViewView:setup_tree_keybindings(bufnr)
    Tree.setup_keybindings(self.tree_component, bufnr, {
        keymaps = {
            toggle = { "<Space>", "<CR>", "<Tab>" },
            close = { "q" }, -- Remove Esc to avoid conflicts with tab navigation
            expand_all = "o",
            collapse_all = "c",
            focus_next = { "j", "<Down>" },
            focus_prev = { "k", "<Up>" },
            close_content = "x",
            close_all_content = "X",
            copy_text = "y",
            help = "?",
        },
    })
end

---Clear tree from buffer
function ViewView:clear_tree()
    if not self.tree_rendered then
        return
    end

    local bufnr = self.manager and self.manager.popup and self.manager.popup.bufnr
    if bufnr then
        -- Make buffer modifiable
        vim.api.nvim_buf_set_option(bufnr, "modifiable", true)
        vim.api.nvim_buf_set_option(bufnr, "readonly", false)

        -- Clear buffer content
        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {})

        -- Set back to readonly
        vim.api.nvim_buf_set_option(bufnr, "modifiable", false)
        vim.api.nvim_buf_set_option(bufnr, "readonly", true)
    end

    self.tree_rendered = false
end

---Render the view tab content
---@param _available_height number Available height for content
---@return NuiLine[] lines View content lines (or empty when tree is active)
function ViewView.render(_, _available_height)
    -- Always return empty lines - tree rendering is handled separately via on_activate()
    -- This prevents conflicts between line-based rendering and direct tree rendering
    return {}
end

---Called when this tab becomes active
function ViewView:on_activate()
    local bufnr = self.manager and self.manager.popup and self.manager.popup.bufnr
    if not bufnr then
        return
    end

    -- Make buffer modifiable for rendering
    vim.api.nvim_buf_set_option(bufnr, "modifiable", true)
    vim.api.nvim_buf_set_option(bufnr, "readonly", false)

    if self.tree_data then
        -- Clear buffer and render tree (render_tree will handle buffer setup)
        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {})

        -- Call render_tree without buffer option changes since we're already in activate
        if self.tree_component then
            Tree.update_tree(self.tree_component, self.tree_data, self:get_tree_config())
        else
            self.tree_component = Tree.create_tree(self.tree_data, self:get_tree_config(), bufnr)
            self:setup_tree_keybindings(bufnr)
        end

        self.tree_component:render()
        self.tree_rendered = true
        log.debug("ViewView", "Tree rendered in activate")
    else
        -- Render empty state
        local lines = {}
        table.insert(lines, "")
        table.insert(lines, "  📋 View Conversation")
        if self.conversation_path then
            local filename = vim.fn.fnamemodify(self.conversation_path, ":t:r")
            table.insert(lines, string.format("      - %s", filename))
        end
        table.insert(lines, "")
        if self.empty_message then
            table.insert(lines, "    " .. self.empty_message)
        else
            table.insert(lines, "    No conversation loaded")
        end
        table.insert(lines, "    Press 'B' to browse conversations")
        table.insert(lines, "")

        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    end

    -- Set buffer back to readonly
    vim.api.nvim_buf_set_option(bufnr, "modifiable", false)
    vim.api.nvim_buf_set_option(bufnr, "readonly", true)
end

---Called when this tab becomes inactive
function ViewView:on_deactivate()
    -- Clear tree rendering and reset state
    self:clear_tree()
    self.tree_rendered = false
end

---Refresh current conversation data
function ViewView:refresh()
    if self.conversation_path then
        self:load_conversation(self.conversation_path)
    end
    log.debug("ViewView", "Refreshed conversation data")
end

return ViewView
