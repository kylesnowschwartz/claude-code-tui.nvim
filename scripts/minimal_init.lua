-- Add current directory to 'runtimepath' to be able to use 'lua' files
vim.cmd([[let &rtp.=','.getcwd()]])

-- Set up 'mini.test' and 'mini.doc' only when calling headless Neovim (like with `make test` or `make documentation`)
if #vim.api.nvim_list_uis() == 0 then
    -- Add 'mini.nvim' to 'runtimepath' to be able to use 'mini.test'
    -- Assumed that 'mini.nvim' is stored in 'deps/mini.nvim'
    vim.cmd("set rtp+=deps/mini.nvim")

    -- Add nui-components for development and testing (includes nui.nvim dependency)
    vim.cmd("set rtp+=deps/nui-components.nvim")

    -- Add nui.nvim for UI components
    vim.cmd("set rtp+=deps/nui.nvim")

    -- Set up 'mini.test'
    require("mini.test").setup()

    -- Set up 'mini.doc' with custom hook to avoid duplicate 'M' tags
    require("mini.doc").setup({
        hooks = {
            write_pre = function(lines)
                -- Track seen tags to remove duplicates
                local seen_tags = {}
                local new_lines = {}

                for i, line in ipairs(lines) do
                    -- Check for help tags (pattern: *tag_name*)
                    local tag = line:match("^%s*%*([^%*]+)%*%s*$")
                    if tag then
                        if seen_tags[tag] then
                            -- Skip duplicate tag
                        else
                            seen_tags[tag] = true
                            table.insert(new_lines, line)
                        end
                    else
                        table.insert(new_lines, line)
                    end
                end
                return new_lines
            end,
        },
    })
end
