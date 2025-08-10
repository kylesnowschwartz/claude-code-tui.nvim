---@brief [[
--- NuiTree component for rendering Claude Code output
--- Displays hierarchical tree of messages, tools, and results
---@brief ]]

local ContentRenderer = require("cc-tui.ui.content_renderer")
local Keymaps = require("cc-tui.keymaps")
local NuiLine = require("nui.line")
local NuiTree = require("nui.tree")
local log = require("cc-tui.util.log")

---@class CcTui.Ui.Tree
local M = {}

---@class CcTui.TreeConfig
---@field keymaps table<string, string|function> Keybinding configuration
---@field icons table<string, string> Icon configuration
---@field colors table<string, string> Color highlight groups

---Default configuration
---@type CcTui.TreeConfig
local default_config = {
    keymaps = {
        toggle = { "<Space>", "<CR>" },
        close = { "q", "<Esc>" },
        expand_all = "E",
        collapse_all = "C",
        focus_next = { "j", "<Down>" },
        focus_prev = { "k", "<Up>" },
        copy_text = "y",
        close_content = "x",
        close_all_content = "X",
        search = "/",
    },
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

---Create NuiTree nodes from cc-tui nodes
---@param cc_node CcTui.BaseNode CC-TUI node
---@param config CcTui.TreeConfig Configuration
---@return NuiTree.Node nui_node NuiTree node
local function create_nui_node(cc_node, config)
    vim.validate({
        cc_node = { cc_node, "table" },
        config = { config, "table" },
    })

    local line = NuiLine()

    -- Add expand/collapse icon for non-leaf nodes
    if cc_node.children and #cc_node.children > 0 then
        local icon = cc_node.expanded and config.icons.expanded or config.icons.collapsed
        line:append(icon .. " ", config.colors[cc_node.type] or "Normal")
    else
        line:append(config.icons.empty .. " ", "Normal")
    end

    -- Add node text with appropriate highlighting
    local highlight = config.colors[cc_node.type] or "Normal"

    -- Special handling for error results
    if cc_node.type == "result" and cc_node.is_error then
        highlight = config.colors.error or "ErrorMsg"
    end

    line:append(cc_node.text, highlight)

    -- Create NuiTree node with children
    local children = {}
    if cc_node.children then
        for _, child in ipairs(cc_node.children) do
            table.insert(children, create_nui_node(child, config))
        end
    end

    return NuiTree.Node({
        text = line,
        id = cc_node.id,
        data = cc_node,
    }, children)
end

---Create a new tree component
---@param root_node CcTui.BaseNode Root node of the tree
---@param config? CcTui.TreeConfig Optional configuration
---@param bufnr? number Optional buffer number to use instead of creating new buffer
---@return NuiTree tree NuiTree instance
function M.create_tree(root_node, config, bufnr)
    vim.validate({
        root_node = { root_node, "table" },
        config = { config, "table", true },
        bufnr = { bufnr, "number", true },
    })

    config = vim.tbl_deep_extend("force", default_config, config or {})

    -- Convert cc-tui nodes to NuiTree nodes
    local nui_root = create_nui_node(root_node, config)

    -- Create NuiTree with nodes - use provided bufnr or create new buffer
    local tree_bufnr = bufnr or vim.api.nvim_create_buf(false, true)
    local tree = NuiTree({
        nodes = { nui_root },
        bufnr = tree_bufnr,
    })

    log.debug("ui.tree", string.format("Created tree with root node: %s (bufnr: %d)", root_node.id, tree_bufnr))

    return tree
end

---Setup keybindings for the tree
---@param tree NuiTree Tree instance
---@param bufnr number Buffer number
---@param config CcTui.TreeConfig Configuration
---@return nil
function M.setup_keybindings(tree, bufnr, config)
    vim.validate({
        tree = { tree, "table" },
        bufnr = { bufnr, "number" },
        config = { config, "table" },
    })

    local function map(keys, callback, desc)
        if type(keys) == "string" then
            keys = { keys }
        end
        for _, key in ipairs(keys) do
            vim.keymap.set("n", key, callback, {
                buffer = bufnr,
                desc = desc,
                nowait = true,
            })
        end
    end

    -- Toggle node expansion (with hybrid content rendering)
    map(config.keymaps.toggle, function()
        local node = tree:get_node()
        if not node then
            return
        end

        -- Special handling for Result nodes - use rich content display
        if node.data and node.data.type == "result" then
            M.toggle_result_node(node, tree)
        elseif node:has_children() then
            -- Normal tree expand/collapse for non-result nodes
            if node:is_expanded() then
                node:collapse()
            else
                node:expand()
            end
            tree:render()
        end
    end, "Toggle node / Show content")

    -- Navigation
    map(config.keymaps.focus_next, function()
        local curr_linenr = vim.api.nvim_win_get_cursor(0)[1]

        -- Find the next line that has a node
        local next_linenr = curr_linenr + 1
        local max_lines = vim.api.nvim_buf_line_count(tree.bufnr)

        -- Loop through lines to find next node
        while next_linenr <= max_lines do
            local next_node = tree:get_node(next_linenr)
            if next_node then
                vim.api.nvim_win_set_cursor(0, { next_linenr, 0 })
                return
            end
            next_linenr = next_linenr + 1
        end

        -- If we've reached the end, wrap to the first node
        for linenr = 1, curr_linenr - 1 do
            local node = tree:get_node(linenr)
            if node then
                vim.api.nvim_win_set_cursor(0, { linenr, 0 })
                return
            end
        end
    end, "Focus next node")

    map(config.keymaps.focus_prev, function()
        local curr_linenr = vim.api.nvim_win_get_cursor(0)[1]

        -- Find the previous line that has a node
        local prev_linenr = curr_linenr - 1

        -- Loop backwards through lines to find previous node
        while prev_linenr >= 1 do
            local prev_node = tree:get_node(prev_linenr)
            if prev_node then
                vim.api.nvim_win_set_cursor(0, { prev_linenr, 0 })
                return
            end
            prev_linenr = prev_linenr - 1
        end

        -- If we've reached the beginning, wrap to the last node
        local max_lines = vim.api.nvim_buf_line_count(tree.bufnr)
        for linenr = max_lines, curr_linenr + 1, -1 do
            local node = tree:get_node(linenr)
            if node then
                vim.api.nvim_win_set_cursor(0, { linenr, 0 })
                return
            end
        end
    end, "Focus previous node")

    -- Expand/collapse all
    map(config.keymaps.expand_all, function()
        for _, node in pairs(tree.nodes.by_id) do
            if node:has_children() then
                node:expand()
            end
        end
        tree:render()
    end, "Expand all nodes")

    map(config.keymaps.collapse_all, function()
        for _, node in pairs(tree.nodes.by_id) do
            if node:has_children() and node:get_depth() > 0 then
                node:collapse()
            end
        end
        tree:render()
    end, "Collapse all nodes")

    -- Copy node text
    map(config.keymaps.copy_text, function()
        local node = tree:get_node()
        if node and node.data and node.data.text then
            vim.fn.setreg("+", node.data.text)
            vim.notify("Copied to clipboard", vim.log.levels.INFO)
        end
    end, "Copy node text")

    -- Close content window for current result node
    map(config.keymaps.close_content, function()
        local node = tree:get_node()
        if node and node.data and node.data.type == "result" then
            local closed = ContentRenderer.close_content_window(node.data.id)
            if closed then
                vim.notify("Closed content window", vim.log.levels.INFO)
            else
                vim.notify("No content window to close", vim.log.levels.WARN)
            end
        else
            vim.notify("Not a result node", vim.log.levels.WARN)
        end
    end, "Close content window")

    -- Close all content windows
    map(config.keymaps.close_all_content, function()
        local count = ContentRenderer.close_all_content_windows()
        if count > 0 then
            vim.notify(string.format("Closed %d content window(s)", count), vim.log.levels.INFO)
        else
            vim.notify("No content windows to close", vim.log.levels.INFO)
        end
    end, "Close all content windows")

    -- Show help menu
    if config.keymaps.help then
        map(config.keymaps.help, function()
            Keymaps.show_help("tree")
        end, "Show help menu")
    end

    log.debug("ui.tree", "Keybindings configured")
end

---Update tree with new root node
---@param tree NuiTree Tree instance
---@param root_node CcTui.BaseNode New root node
---@param config CcTui.TreeConfig Configuration
---@return nil
function M.update_tree(tree, root_node, config)
    vim.validate({
        tree = { tree, "table" },
        root_node = { root_node, "table" },
        config = { config, "table" },
    })

    -- Convert new nodes
    local nui_root = create_nui_node(root_node, config)

    -- Update tree nodes using proper API
    tree:set_nodes({ nui_root })

    -- Re-render
    tree:render()

    log.debug("ui.tree", "Tree updated with new root")
end

---Expand node to reveal a specific node by ID
---@param tree NuiTree Tree instance
---@param node_id string Node ID to reveal
---@return boolean success Whether node was found and revealed
function M.reveal_node(tree, node_id)
    vim.validate({
        tree = { tree, "table" },
        node_id = { node_id, "string" },
    })

    local node = tree:get_node(node_id)
    if not node then
        return false
    end

    -- Expand all parent nodes
    local parent_id = node:get_parent_id()
    while parent_id do
        local parent = tree:get_node(parent_id)
        if not parent then
            break
        end

        if not parent:is_expanded() then
            parent:expand()
        end

        parent_id = parent:get_parent_id()
    end

    -- Focus the target node by setting cursor position
    local node_obj, start_line, _ = tree:get_node(node_id)
    if node_obj and start_line then
        vim.api.nvim_win_set_cursor(0, { start_line, 0 })
    end
    tree:render()

    return true
end

---Get currently focused node data
---@param tree NuiTree Tree instance
---@return CcTui.BaseNode? node CC-TUI node data or nil
function M.get_focused_node(tree)
    vim.validate({
        tree = { tree, "table" },
    })

    local node = tree:get_node()
    if node and node.data then
        return node.data
    end

    return nil
end

---Define highlight groups for tree elements
---@return nil
function M.setup_highlights()
    local highlights = {
        CcTuiSession = { link = "Title" },
        CcTuiMessage = { link = "Function" },
        CcTuiTool = { link = "Keyword" },
        CcTuiResult = { link = "String" },
        CcTuiText = { link = "Normal" },
        CcTuiError = { link = "ErrorMsg" },
    }

    for group, opts in pairs(highlights) do
        vim.api.nvim_set_hl(0, group, opts)
    end

    log.debug("ui.tree", "Highlights configured")
end

---Toggle a result node - show/hide rich content using ContentRenderer
---@param node NuiTree.Node Result node to toggle
---@param tree NuiTree Tree instance for rendering updates
---@return nil
function M.toggle_result_node(node, tree)
    vim.validate({
        node = { node, "table" },
        tree = { tree, "table", true },
    })

    local result_data = node.data
    if not result_data or result_data.type ~= "result" then
        return
    end

    -- Check if content window is already open
    if ContentRenderer.is_content_window_open(result_data.id) then
        -- Close existing content window
        local closed = ContentRenderer.close_content_window(result_data.id)
        if closed then
            log.debug("ui.tree", string.format("Closed content window for result: %s", result_data.id))
        end
        return
    end

    -- Use display decision computed during tree construction (eliminates duplication)
    -- This maintains single source of truth principle from Phase 2 refactoring
    local should_use_rich_display = result_data.use_rich_display

    if should_use_rich_display then
        -- Use rich content display via ContentRenderer
        local parent_tool = M.find_parent_tool(tree, node)
        local tool_name = parent_tool and parent_tool.tool_name

        local content_window = ContentRenderer.render_content(
            result_data.id,
            tool_name,
            result_data.content or "",
            vim.api.nvim_get_current_win(),
            result_data.structured_content,
            result_data.stream_context -- 🚀 ACTIVATED: Stream context threading for enhanced classification
        )

        if content_window then
            log.debug("ui.tree", string.format("Opened content window for result: %s", result_data.id))
        else
            vim.notify("Failed to open content window", vim.log.levels.ERROR)
        end
    else
        -- Fall back to normal tree expansion for small content
        if node:has_children() then
            if node:is_expanded() then
                node:collapse()
            else
                node:expand()
            end
            -- Render tree to show expansion changes
            if tree then
                tree:render()
            end
        end
    end
end

---Find the parent tool node for a result node
---@param tree NuiTree Tree instance
---@param result_node NuiTree.Node Result node
---@return CcTui.ToolNode? tool_data Parent tool data or nil
function M.find_parent_tool(tree, result_node)
    vim.validate({
        tree = { tree, "table" },
        result_node = { result_node, "table" },
    })

    local parent_id = result_node:get_parent_id()
    while parent_id do
        local parent = tree:get_node(parent_id)
        if not parent then
            break
        end

        if parent.data and parent.data.type == "tool" then
            return parent.data
        end

        parent_id = parent:get_parent_id()
    end

    return nil
end

---Close all content windows (cleanup function)
---@return nil
function M.cleanup_content_windows()
    ContentRenderer.close_all_content_windows()
    log.debug("ui.tree", "Cleaned up all content windows")
end

---Get summary of currently open content windows
---@return table summary Summary of open windows
function M.get_content_windows_summary()
    local active_windows = ContentRenderer.get_active_windows()
    return {
        count = #active_windows,
        result_ids = active_windows,
    }
end

return M
