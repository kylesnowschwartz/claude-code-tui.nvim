---@brief [[
--- Keybinding configuration for CC-TUI
--- Manages global and buffer-local keymaps
---@brief ]]

local log = require("cc-tui.util.log")

---@class CcTui.Keymaps
local M = {}

---@class CcTui.KeymapConfig
---@field global table<string, string|function> Global keymaps
---@field tree table<string, string|function> Tree-specific keymaps

---Default keymap configuration
---@type CcTui.KeymapConfig
local default_config = {
    global = {
        toggle = "<leader>cc",
        focus = "<leader>cf",
        close = "<leader>cq",
        refresh = "<leader>cr",
    },
    tree = {
        toggle_node = { "<Tab>", "<CR>" },
        close_window = { "q", "<Esc>" },
        expand_all = "E",
        collapse_all = "C",
        next_node = { "j", "<Down>" },
        prev_node = { "k", "<Up>" },
        parent_node = "h",
        child_node = "l",
        first_sibling = "^",
        last_sibling = "$",
        copy_text = "y",
        copy_all = "Y",
        search = "/",
        next_match = "n",
        prev_match = "N",
        refresh = "r",
        help = "?",
    },
}

---Current configuration
---@type CcTui.KeymapConfig
local config = vim.deepcopy(default_config)

---Setup global keymaps
---@param keymaps table<string, string|function> Keymap table
---@param handlers table<string, function> Handler functions
---@return nil
function M.setup_global(keymaps, handlers)
    vim.validate({
        keymaps = { keymaps, "table" },
        handlers = { handlers, "table" },
    })

    for action, keys in pairs(keymaps) do
        local handler = handlers[action]
        if handler then
            if type(keys) == "string" then
                keys = { keys }
            end

            for _, key in ipairs(keys) do
                vim.keymap.set("n", key, handler, {
                    desc = string.format("CC-TUI: %s", action),
                    silent = true,
                })

                log.debug("keymaps", string.format("Global keymap set: %s -> %s", key, action))
            end
        else
            log.debug("keymaps", string.format("No handler for action: %s", action))
        end
    end
end

---Setup buffer-local keymaps for tree
---@param bufnr number Buffer number
---@param keymaps table<string, string|function> Keymap table
---@param handlers table<string, function> Handler functions
---@return nil
function M.setup_tree_buffer(bufnr, keymaps, handlers)
    vim.validate({
        bufnr = { bufnr, "number" },
        keymaps = { keymaps, "table" },
        handlers = { handlers, "table" },
    })

    for action, keys in pairs(keymaps) do
        local handler = handlers[action]
        if handler then
            if type(keys) == "string" then
                keys = { keys }
            end

            for _, key in ipairs(keys) do
                vim.keymap.set("n", key, handler, {
                    buffer = bufnr,
                    desc = string.format("CC-TUI Tree: %s", action),
                    silent = true,
                    nowait = true,
                })

                log.debug("keymaps", string.format("Tree keymap set for buffer %d: %s -> %s", bufnr, key, action))
            end
        else
            log.debug("keymaps", string.format("No handler for tree action: %s", action))
        end
    end
end

---Merge user configuration with defaults
---@param user_config? CcTui.KeymapConfig User configuration
---@return CcTui.KeymapConfig merged Merged configuration
function M.merge_config(user_config)
    vim.validate({
        user_config = { user_config, "table", true },
    })

    if not user_config then
        return config
    end

    config = vim.tbl_deep_extend("force", config, user_config)

    log.debug("keymaps", "Configuration merged")

    return config
end

---Get current configuration
---@return CcTui.KeymapConfig config
function M.get_config()
    return vim.deepcopy(config)
end

---Create help text for keybindings
---@param keymap_type "global"|"tree" Type of keymaps to show
---@return string[] lines Help text lines
function M.get_help_text(keymap_type)
    vim.validate({
        keymap_type = {
            keymap_type,
            function(v)
                return v == "global" or v == "tree"
            end,
            "must be 'global' or 'tree'",
        },
    })

    local lines = {}
    local keymaps = keymap_type == "global" and config.global or config.tree

    table.insert(lines, string.format("=== CC-TUI %s Keybindings ===", keymap_type:upper()))
    table.insert(lines, "")

    -- Format keymaps for display
    local items = {}
    for action, keys in pairs(keymaps) do
        if type(keys) == "table" then
            keys = table.concat(keys, ", ")
        end
        table.insert(items, { action = action, keys = keys })
    end

    -- Sort by action name
    table.sort(items, function(a, b)
        return a.action < b.action
    end)

    -- Find max action length for alignment
    local max_len = 0
    for _, item in ipairs(items) do
        max_len = math.max(max_len, #item.action)
    end

    -- Format lines
    for _, item in ipairs(items) do
        local action = item.action:gsub("_", " ")
        action = action:sub(1, 1):upper() .. action:sub(2)
        local padding = string.rep(" ", max_len - #item.action + 2)
        table.insert(lines, string.format("  %s%s: %s", action, padding, item.keys))
    end

    return lines
end

---Show help window for keybindings
---@param keymap_type? "global"|"tree" Type of keymaps to show (default: "tree")
---@return nil
function M.show_help(keymap_type)
    keymap_type = keymap_type or "tree"

    vim.validate({
        keymap_type = {
            keymap_type,
            function(v)
                return v == "global" or v == "tree"
            end,
            "must be 'global' or 'tree'",
        },
    })

    local lines = M.get_help_text(keymap_type)

    -- Create floating window for help
    local width = 50
    local height = #lines + 2
    local buf = vim.api.nvim_create_buf(false, true)

    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].modifiable = false
    vim.bo[buf].buftype = "nofile"

    local win = vim.api.nvim_open_win(buf, true, {
        relative = "editor",
        width = width,
        height = height,
        row = math.floor((vim.o.lines - height) / 2),
        col = math.floor((vim.o.columns - width) / 2),
        style = "minimal",
        border = "rounded",
        title = " CC-TUI Help ",
        title_pos = "center",
    })

    -- Close on escape
    vim.keymap.set("n", "<Esc>", function()
        vim.api.nvim_win_close(win, true)
    end, { buffer = buf })

    vim.keymap.set("n", "q", function()
        vim.api.nvim_win_close(win, true)
    end, { buffer = buf })

    log.debug("keymaps", string.format("Help window shown for %s keymaps", keymap_type))
end

---Clear all CC-TUI keymaps
---@return nil
function M.clear_all()
    -- Note: This would need to track set keymaps to properly clear them
    -- For now, this is a placeholder
    log.debug("keymaps", "All keymaps cleared")
end

return M
