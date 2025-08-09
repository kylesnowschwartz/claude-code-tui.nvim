---@brief [[
--- Content renderer for displaying tool results using NUI components
--- Handles rich text display, syntax highlighting, and proper formatting
---@brief ]]

local Popup = require("nui.popup")

---@class CcTui.UI.ContentRenderer
local M = {}

---@enum CcTui.ContentDisplayType
M.ContentType = {
    JSON = "json",
    FILE_CONTENT = "file_content",
    COMMAND_OUTPUT = "command_output",
    ERROR = "error",
    GENERIC_TEXT = "generic_text",
}

---@class CcTui.ContentWindow
---@field popup? NuiPopup Active popup window
---@field split? NuiSplit Active split window
---@field buffer_id number Buffer ID for content
---@field content_type CcTui.ContentDisplayType Type of content displayed

--- Active content windows by result node ID
---@type table<string, CcTui.ContentWindow>
local active_windows = {}

---Detect content type based on tool and content analysis
---@param content string Content to analyze
---@param tool_name? string Name of the tool that generated the content
---@return CcTui.ContentDisplayType type Detected content type
---@return table metadata Additional metadata about content
function M.detect_content_type(content, tool_name)
    vim.validate({
        content = { content, "string" },
        tool_name = { tool_name, "string", true },
    })

    -- Error detection (highest priority)
    if content:match("^Error:") or content:match("^error:") or content:match("Exception") then
        return M.ContentType.ERROR, { error_type = "runtime_error" }
    end

    -- Tool-specific content detection
    if tool_name == "Read" then
        -- File content - detect file type if possible
        local file_ext = M.extract_file_extension(content)
        return M.ContentType.FILE_CONTENT, { file_type = file_ext or "text" }
    elseif tool_name == "Bash" then
        return M.ContentType.COMMAND_OUTPUT, { shell_type = "bash" }
    elseif tool_name and tool_name:match("^mcp__") then
        -- MCP API responses - often JSON
        if M.is_json_content(content) then
            return M.ContentType.JSON, { api_source = tool_name }
        else
            return M.ContentType.GENERIC_TEXT, { api_source = tool_name }
        end
    end

    -- Content-based detection
    if M.is_json_content(content) then
        return M.ContentType.JSON, {}
    end

    return M.ContentType.GENERIC_TEXT, {}
end

---Check if content appears to be JSON
---@param content string Content to check
---@return boolean is_json Whether content is JSON
function M.is_json_content(content)
    local trimmed = content:match("^%s*(.-)%s*$")
    return (trimmed:match("^{") and trimmed:match("}$")) or (trimmed:match("^%[") and trimmed:match("%]$"))
end

---Extract file extension from file content or path hints
---@param content string File content
---@return string? extension File extension or nil
function M.extract_file_extension(content)
    -- Look for common file patterns in first few lines
    local first_lines = content:sub(1, 200)

    if first_lines:match("^%s*{") or first_lines:match('"[^"]+"%s*:') then
        return "json"
    elseif first_lines:match("^%s*<%?xml") or first_lines:match("^%s*<[^>]+>") then
        return "xml"
    elseif first_lines:match("^%s*#") and first_lines:match("!/bin/") then
        return "sh"
    elseif first_lines:match("function%s+") or first_lines:match("local%s+") then
        return "lua"
    elseif first_lines:match("const%s+") or first_lines:match("function%s*%(") then
        return "javascript"
    elseif first_lines:match("def%s+") or first_lines:match("import%s+") then
        return "python"
    end

    return "text"
end

---Render content using appropriate NUI components
---@param result_node_id string Unique ID for the result node
---@param tool_name? string Tool that generated the content
---@param content string Content to render
---@param parent_window? number Parent window for positioning
---@return CcTui.ContentWindow? window Created content window or nil
function M.render_content(result_node_id, tool_name, content, parent_window)
    vim.validate({
        result_node_id = { result_node_id, "string" },
        tool_name = { tool_name, "string", true },
        content = { content, "string" },
        parent_window = { parent_window, "number", true },
    })

    local log = require("cc-tui.util.log")
    log.debug(
        "content_renderer",
        string.format(
            "render_content called: id=%s, tool=%s, content_len=%d",
            result_node_id,
            tool_name or "nil",
            #content
        )
    )

    -- Close existing window for this result if open
    M.close_content_window(result_node_id)

    local content_type, metadata = M.detect_content_type(content, tool_name)
    log.debug("content_renderer", string.format("detected content_type: %s", content_type))
    local window

    if content_type == M.ContentType.JSON then
        window = M.render_json_content(result_node_id, content, metadata)
    elseif content_type == M.ContentType.FILE_CONTENT then
        window = M.render_file_content(result_node_id, content, metadata)
    elseif content_type == M.ContentType.COMMAND_OUTPUT then
        window = M.render_command_output(result_node_id, content, metadata)
    elseif content_type == M.ContentType.ERROR then
        window = M.render_error_content(result_node_id, content, metadata)
    else
        window = M.render_generic_content(result_node_id, content, metadata)
    end

    if window then
        active_windows[result_node_id] = window
    end

    return window
end

---Render JSON content with syntax highlighting
---@param result_id string Result node ID
---@param content string JSON content
---@param _metadata table Content metadata (unused)
---@return CcTui.ContentWindow window Created content window
function M.render_json_content(result_id, content, _metadata)
    local log = require("cc-tui.util.log")
    local lines = vim.split(content, "\n")
    local line_count = #lines

    log.debug("content_renderer", string.format("render_json_content: id=%s, lines=%d", result_id, line_count))

    -- Choose display method based on content size
    local popup
    if line_count > 30 then
        -- Large JSON - use popup window with enhanced navigation
        popup = Popup({
            enter = true, -- Focus the window for navigation
            focusable = true,
            border = {
                style = "rounded",
                text = {
                    top = string.format(" JSON Content (%d lines) [za/zo/zc to fold] ", line_count),
                    top_align = "center",
                },
            },
            position = { row = "5%", col = "50%" },
            size = { width = "45%", height = "90%" },
            buf_options = {
                modifiable = false,
                readonly = true,
                filetype = "json",
            },
            win_options = {
                wrap = false,
                linebreak = true,
                number = true,
                relativenumber = false,
                cursorline = true,
            },
        })
    else
        -- Medium JSON - use smaller popup
        popup = Popup({
            enter = true,
            focusable = true,
            border = {
                style = "single",
                text = { top = " JSON [za to fold] ", top_align = "center" },
            },
            position = { row = "20%", col = "60%" },
            size = { width = "35%", height = math.min(line_count + 4, 25) },
            buf_options = {
                modifiable = false,
                readonly = true,
                filetype = "json",
            },
            win_options = {
                wrap = true,
                linebreak = true,
                cursorline = true,
            },
        })
    end

    local mount_ok, mount_err = pcall(function()
        popup:mount()
    end)

    if not mount_ok then
        log.debug("content_renderer", string.format("Failed to mount JSON popup: %s", mount_err))
        return nil
    end

    log.debug(
        "content_renderer",
        string.format("Successfully mounted JSON popup: winid=%s, bufnr=%s", popup.winid, popup.bufnr)
    )

    -- Temporarily make buffer modifiable to set content
    vim.bo[popup.bufnr].modifiable = true
    vim.api.nvim_buf_set_lines(popup.bufnr, 0, -1, false, lines)
    vim.bo[popup.bufnr].modifiable = false

    -- Enable treesitter folding for JSON navigation
    vim.api.nvim_buf_call(popup.bufnr, function()
        vim.opt_local.foldmethod = "expr"
        vim.opt_local.foldexpr = "v:lua.vim.treesitter.foldexpr()"
        vim.opt_local.foldenable = true
        vim.opt_local.foldlevel = 1 -- Start with top-level objects folded
        vim.opt_local.foldlevelstart = 1
    end)

    -- Add navigation and close keybindings
    popup:map("n", "q", function()
        M.close_content_window(result_id)
    end, { noremap = true, silent = true })

    popup:map("n", "<Esc>", function()
        M.close_content_window(result_id)
    end, { noremap = true, silent = true })

    -- Enhanced JSON navigation bindings
    popup:map("n", "zR", function()
        vim.api.nvim_win_call(popup.winid, function()
            vim.cmd("normal! zR")
        end)
    end, { noremap = true, silent = true })

    popup:map("n", "zM", function()
        vim.api.nvim_win_call(popup.winid, function()
            vim.cmd("normal! zM")
        end)
    end, { noremap = true, silent = true })

    return {
        popup = popup,
        buffer_id = popup.bufnr,
        content_type = M.ContentType.JSON,
    }
end

---Render file content with appropriate syntax highlighting
---@param result_id string Result node ID
---@param content string File content
---@param metadata table Content metadata with file_type
---@return CcTui.ContentWindow window Created content window
function M.render_file_content(result_id, content, metadata)
    local lines = vim.split(content, "\n")
    local line_count = #lines
    local file_type = metadata.file_type or "text"

    local popup = Popup({
        enter = false,
        focusable = true,
        border = {
            style = "rounded",
            text = {
                top = string.format(" File Content (%s, %d lines) ", file_type, line_count),
                top_align = "center",
            },
        },
        position = { row = "5%", col = "65%" },
        size = { width = "35%", height = "85%" },
        buf_options = {
            modifiable = false,
            readonly = true,
            filetype = file_type,
        },
        win_options = {
            wrap = false,
            number = true,
            relativenumber = false,
        },
    })

    popup:mount()

    -- Temporarily make buffer modifiable to set content
    vim.bo[popup.bufnr].modifiable = true
    vim.api.nvim_buf_set_lines(popup.bufnr, 0, -1, false, lines)
    vim.bo[popup.bufnr].modifiable = false

    -- Add close keybindings
    popup:map("n", "q", function()
        M.close_content_window(result_id)
    end, { noremap = true, silent = true })

    popup:map("n", "<Esc>", function()
        M.close_content_window(result_id)
    end, { noremap = true, silent = true })

    return {
        popup = popup,
        buffer_id = popup.bufnr,
        content_type = M.ContentType.FILE_CONTENT,
    }
end

---Render command output with terminal-like styling
---@param result_id string Result node ID
---@param content string Command output
---@param metadata table Content metadata
---@return CcTui.ContentWindow window Created content window
function M.render_command_output(result_id, content, _metadata)
    local lines = vim.split(content, "\n")
    local line_count = #lines

    local popup = Popup({
        enter = false,
        focusable = true,
        border = {
            style = "double",
            text = {
                top = string.format(" Command Output (%d lines) ", line_count),
                top_align = "center",
            },
        },
        position = { row = "15%", col = "60%" },
        size = { width = "40%", height = math.min(line_count + 4, 20) },
        buf_options = {
            modifiable = false,
            readonly = true,
            filetype = "sh", -- Shell highlighting for command output
        },
        win_options = {
            wrap = true,
            linebreak = true,
        },
    })

    popup:mount()

    -- Temporarily make buffer modifiable to set content
    vim.bo[popup.bufnr].modifiable = true
    vim.api.nvim_buf_set_lines(popup.bufnr, 0, -1, false, lines)
    vim.bo[popup.bufnr].modifiable = false

    -- Add close keybindings
    popup:map("n", "q", function()
        M.close_content_window(result_id)
    end, { noremap = true, silent = true })

    popup:map("n", "<Esc>", function()
        M.close_content_window(result_id)
    end, { noremap = true, silent = true })

    return {
        popup = popup,
        buffer_id = popup.bufnr,
        content_type = M.ContentType.COMMAND_OUTPUT,
    }
end

---Render error content with error highlighting
---@param result_id string Result node ID
---@param content string Error content
---@param metadata table Content metadata
---@return CcTui.ContentWindow window Created content window
function M.render_error_content(result_id, content, _metadata)
    local lines = vim.split(content, "\n")

    local popup = Popup({
        enter = false,
        focusable = true,
        border = {
            style = "double",
            text = { top = " ❌ Error ", top_align = "center" },
        },
        position = { row = "25%", col = "55%" },
        size = { width = "45%", height = math.min(#lines + 4, 15) },
        buf_options = {
            modifiable = false,
            readonly = true,
        },
        win_options = {
            wrap = true,
            linebreak = true,
        },
    })

    popup:mount()

    -- Temporarily make buffer modifiable to set content
    vim.bo[popup.bufnr].modifiable = true
    vim.api.nvim_buf_set_lines(popup.bufnr, 0, -1, false, lines)
    vim.bo[popup.bufnr].modifiable = false

    -- Add error highlighting
    local ns_id = vim.api.nvim_create_namespace("cc_tui_error")
    for i = 0, #lines - 1 do
        vim.api.nvim_buf_add_highlight(popup.bufnr, ns_id, "ErrorMsg", i, 0, -1)
    end

    -- Add close keybindings
    popup:map("n", "q", function()
        M.close_content_window(result_id)
    end, { noremap = true, silent = true })

    popup:map("n", "<Esc>", function()
        M.close_content_window(result_id)
    end, { noremap = true, silent = true })

    return {
        popup = popup,
        buffer_id = popup.bufnr,
        content_type = M.ContentType.ERROR,
    }
end

---Render generic text content
---@param result_id string Result node ID
---@param content string Text content
---@param metadata table Content metadata
---@return CcTui.ContentWindow window Created content window
function M.render_generic_content(result_id, content, _metadata)
    local log = require("cc-tui.util.log")
    local lines = vim.split(content, "\n")
    local line_count = #lines

    log.debug("content_renderer", string.format("render_generic_content: id=%s, lines=%d", result_id, line_count))

    -- Use adaptive sizing like JSON renderer
    local popup
    if line_count > 30 then
        -- Large content - use prominent window
        popup = Popup({
            enter = true, -- FIXED: Now focusable and visible
            focusable = true,
            border = {
                style = "rounded",
                text = {
                    top = string.format(" Content (%d lines) [q to close] ", line_count),
                    top_align = "center",
                },
            },
            position = { row = "5%", col = "50%" }, -- FIXED: Better positioning
            size = { width = "45%", height = "90%" }, -- FIXED: Much larger size
            buf_options = {
                modifiable = false,
                readonly = true,
                filetype = "markdown", -- Better highlighting for structured text
            },
            win_options = {
                wrap = false,
                linebreak = true,
                number = true,
                cursorline = true,
            },
        })
    else
        -- Medium content - use smaller window
        popup = Popup({
            enter = true, -- FIXED: Now focusable
            focusable = true,
            border = {
                style = "single",
                text = {
                    top = string.format(" Content (%d lines) ", line_count),
                    top_align = "center",
                },
            },
            position = { row = "20%", col = "60%" },
            size = { width = "40%", height = math.min(line_count + 4, 30) }, -- FIXED: Larger limits
            buf_options = {
                modifiable = false,
                readonly = true,
                filetype = "markdown",
            },
            win_options = {
                wrap = true,
                linebreak = true,
                cursorline = true,
            },
        })
    end

    local mount_ok, mount_err = pcall(function()
        popup:mount()
    end)

    if not mount_ok then
        log.debug("content_renderer", string.format("Failed to mount generic content popup: %s", mount_err))
        return nil
    end

    log.debug(
        "content_renderer",
        string.format("Successfully mounted generic content popup: winid=%s, bufnr=%s", popup.winid, popup.bufnr)
    )

    -- Temporarily make buffer modifiable to set content
    vim.bo[popup.bufnr].modifiable = true
    vim.api.nvim_buf_set_lines(popup.bufnr, 0, -1, false, lines)
    vim.bo[popup.bufnr].modifiable = false

    -- Enable basic folding for structured content (if line count is high)
    if line_count > 30 then
        vim.api.nvim_buf_call(popup.bufnr, function()
            vim.opt_local.foldmethod = "indent"
            vim.opt_local.foldenable = true
            vim.opt_local.foldlevel = 2 -- Start with some content visible
            vim.opt_local.foldlevelstart = 2
        end)
    end

    -- Add navigation and close keybindings
    popup:map("n", "q", function()
        M.close_content_window(result_id)
    end, { noremap = true, silent = true })

    popup:map("n", "<Esc>", function()
        M.close_content_window(result_id)
    end, { noremap = true, silent = true })

    -- Add folding shortcuts for large content
    if line_count > 30 then
        popup:map("n", "zR", function()
            vim.api.nvim_win_call(popup.winid, function()
                vim.cmd("normal! zR")
            end)
        end, { noremap = true, silent = true })

        popup:map("n", "zM", function()
            vim.api.nvim_win_call(popup.winid, function()
                vim.cmd("normal! zM")
            end)
        end, { noremap = true, silent = true })
    end

    return {
        popup = popup,
        buffer_id = popup.bufnr,
        content_type = M.ContentType.GENERIC_TEXT,
    }
end

---Close content window for a result node
---@param result_node_id string Result node ID
---@return boolean closed Whether a window was closed
function M.close_content_window(result_node_id)
    vim.validate({
        result_node_id = { result_node_id, "string" },
    })

    local window = active_windows[result_node_id]
    if not window then
        return false
    end

    if window.popup then
        pcall(function()
            window.popup:unmount()
        end)
    end

    if window.split then
        pcall(function()
            window.split:unmount()
        end)
    end

    active_windows[result_node_id] = nil
    return true
end

---Close all active content windows
---@return number closed_count Number of windows closed
function M.close_all_content_windows()
    local count = 0
    for result_id, _ in pairs(active_windows) do
        if M.close_content_window(result_id) then
            count = count + 1
        end
    end
    return count
end

---Check if a content window is open for a result node
---@param result_node_id string Result node ID
---@return boolean is_open Whether window is open
function M.is_content_window_open(result_node_id)
    return active_windows[result_node_id] ~= nil
end

---Get list of active content windows
---@return string[] result_ids List of result node IDs with open windows
function M.get_active_windows()
    local result_ids = {}
    for result_id, _ in pairs(active_windows) do
        table.insert(result_ids, result_id)
    end
    return result_ids
end

return M
