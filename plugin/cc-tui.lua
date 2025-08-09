-- You can use this loaded variable to enable conditional parts of your plugin.
if _G.CcTuiLoaded then
    return
end

_G.CcTuiLoaded = true

-- Useful if you want your plugin to be compatible with older (<0.7) neovim versions
if vim.fn.has("nvim-0.7") == 0 then
    vim.cmd("command! CcTui lua require('cc-tui').toggle()")
else
    vim.api.nvim_create_user_command("CcTui", function()
        require("cc-tui").toggle()
    end, {})
end
