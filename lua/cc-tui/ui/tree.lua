---@brief [[
--- NuiTree component for rendering Claude Code output
--- Displays hierarchical tree of messages, tools, and results
---@brief ]]

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
---@return NuiTree tree NuiTree instance
function M.create_tree(root_node, config)
    vim.validate({
        root_node = { root_node, "table" },
        config = { config, "table", true },
    })

    config = vim.tbl_deep_extend("force", default_config, config or {})

    -- Convert cc-tui nodes to NuiTree nodes
    local nui_root = create_nui_node(root_node, config)

    -- Create NuiTree with nodes
    local tree = NuiTree({
        nodes = { nui_root },
        bufnr = vim.api.nvim_create_buf(false, true),
    })

    log.debug("ui.tree", string.format("Created tree with root node: %s", root_node.id))

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

    -- Toggle node expansion
    map(config.keymaps.toggle, function()
        local node = tree:get_node()
        if node and node:has_children() then
            if node:is_expanded() then
                node:collapse()
            else
                node:expand()
            end
            tree:render()
        end
    end, "Toggle node")

    -- Navigation
    map(config.keymaps.focus_next, function()
        local node = tree:get_node()
        if node then
            local next_node = tree:get_node(node:get_next_id())
            if next_node then
                tree:focus_node(next_node:get_id())
                tree:render()
            end
        end
    end, "Focus next node")

    map(config.keymaps.focus_prev, function()
        local node = tree:get_node()
        if node then
            local prev_node = tree:get_node(node:get_prev_id())
            if prev_node then
                tree:focus_node(prev_node:get_id())
                tree:render()
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

    -- Update tree nodes
    tree.nodes = NuiTree.Nodes({ nui_root })

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
    local parent = node:get_parent()
    while parent do
        if not parent:is_expanded() then
            parent:expand()
        end
        parent = parent:get_parent()
    end

    -- Focus the target node
    tree:focus_node(node_id)
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

return M
