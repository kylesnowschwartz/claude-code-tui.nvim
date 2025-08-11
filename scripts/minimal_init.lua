-- Add current directory to 'runtimepath' to be able to use 'lua' files
vim.cmd([[let &rtp.=','.getcwd()]])

-- Set testing mode environment variable for all tests
vim.env.CC_TUI_TESTING = "1"

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

                for _, line in ipairs(lines) do
                    -- Check for help tags (pattern: *tag_name*)
                    local tag = line:match("^%s*%*([^%*]+)%*%s*$")
                    if tag then
                        if not seen_tags[tag] then
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
