-- You can use this loaded variable to enable conditional parts of your plugin.
if _G.CcTuiLoaded then
    return
end

_G.CcTuiLoaded = true

-- Useful if you want your plugin to be compatible with older (<0.7) neovim versions
if vim.fn.has("nvim-0.7") == 0 then
    vim.cmd("command! CcTui lua require('cc-tui').toggle()")
    vim.cmd(
        "command! CcTuiReload lua for k,_ in pairs(package.loaded) do if k:match('^cc%-tui') then package.loaded[k] = nil end end; print('cc-tui modules reloaded!')"
    )
else
    vim.api.nvim_create_user_command("CcTui", function()
        require("cc-tui").toggle()
    end, {})

    vim.api.nvim_create_user_command("CcTuiReload", function()
        -- Preserve current config
        local current_config = _G.CcTui and _G.CcTui.config or {}

        -- Clear all cc-tui modules from package cache
        for module_name, _ in pairs(package.loaded) do
            if module_name:match("^cc%-tui") then
                package.loaded[module_name] = nil
            end
        end

        -- Restore config with debug enabled for development
        require("cc-tui").setup(vim.tbl_deep_extend("force", current_config, { debug = true }))

        print("cc-tui modules reloaded with debug enabled!")
    end, {})
end

-- Development keymaps
vim.keymap.set("n", "<leader>Cct", "<cmd>CcTui<cr>", { desc = "Toggle cc-tui" })
vim.keymap.set("n", "<leader>Ccr", "<cmd>CcTuiReload<cr>", { desc = "Reload cc-tui modules" })
