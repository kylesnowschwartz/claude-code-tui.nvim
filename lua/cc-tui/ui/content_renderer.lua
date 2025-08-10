---@brief [[
--- Content renderer for displaying tool results using NUI components
--- Handles rich text display, syntax highlighting, and proper formatting
---@brief ]]

local ContentClassifier = require("cc-tui.utils.content_classifier")
local Popup = require("nui.popup")

---@class CcTui.UI.ContentRenderer
local M = {}

---@class CcTui.ContentWindow
---@field popup? NuiPopup Active popup window
---@field split? NuiSplit Active split window
---@field buffer_id number Buffer ID for content
---@field content_type string Type of content displayed

--- Window layering configuration
---@class CcTui.WindowLayers
local WINDOW_LAYERS = {
    MAIN_UI = 10, -- Main CC-TUI popup window
    CONTENT = 50, -- Content popups (command output, file content, etc.)
    MODAL = 100, -- Modal dialogs (future use)
}

--- Active content windows by result node ID
---@type table<string, CcTui.ContentWindow>
local active_windows = {}

-- REMOVED: detect_content_type() function (33 lines removed)
-- Phase 1 Cleanup: This legacy function has been removed in favor of
-- ContentClassifier.classify_from_structured_data() which provides deterministic
-- classification using Claude Code JSON structure instead of inference-based detection.

-- REMOVED: is_json_content() wrapper function (5 lines removed)
-- Phase 1 Cleanup: This wrapper has been removed. Use ContentClassifier.is_json_content() directly
-- or preferably ContentClassifier.classify_from_structured_data() for deterministic classification.

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

---Render content using appropriate NUI components with context-aware ContentClassifier
---@param result_node_id string Unique ID for the result node
---@param tool_name? string Tool that generated the content
---@param content string Content to render
---@param parent_window? number Parent window for positioning
---@param structured_content table REQUIRED: Original Claude Code JSON structure for deterministic classification
---@param stream_context? table Optional Claude Code stream context for enhanced classification
---@return CcTui.ContentWindow? window Created content window or nil
function M.render_content(result_node_id, tool_name, content, parent_window, structured_content, stream_context)
    vim.validate({
        result_node_id = { result_node_id, "string" },
        tool_name = { tool_name, "string", true },
        content = { content, "string" },
        parent_window = { parent_window, "number", true },
        structured_content = { structured_content, "table" }, -- REQUIRED after Phase 1 cleanup
        stream_context = { stream_context, "table", true }, -- Optional for enhanced classification
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

    -- 🚀 ACTIVATE DORMANT INFRASTRUCTURE - Context-aware classification!
    local classification
    if stream_context then
        classification = ContentClassifier.classify_with_stream_context(structured_content, content, stream_context)
        log.debug(
            "content_renderer",
            string.format(
                "🚀 CONTEXT-AWARE: Using ContentClassifier.classify_with_stream_context() - type=%s, strategy=%s, force_popup=%s",
                classification.type,
                classification.display_strategy,
                tostring(classification.force_popup)
            )
        )
    else
        classification = ContentClassifier.classify_from_structured_data(structured_content, content)
        log.debug(
            "content_renderer",
            string.format(
                "🚀 BASIC: Using ContentClassifier.classify_from_structured_data() - type=%s, confidence=%.2f",
                classification.type,
                classification.confidence
            )
        )
    end

    -- Use ContentClassifier types directly
    local content_type = classification.type
    local metadata = classification.metadata

    log.debug("content_renderer", string.format("final content_type: %s", content_type))
    local window

    if
        content_type == ContentClassifier.ContentType.TOOL_INPUT
        or content_type == ContentClassifier.ContentType.JSON_API_RESPONSE
        or content_type == ContentClassifier.ContentType.ERROR_OBJECT
    then
        window = M.render_json_content(result_node_id, content, metadata)
    elseif content_type == ContentClassifier.ContentType.FILE_CONTENT then
        window = M.render_file_content(result_node_id, content, metadata)
    elseif content_type == ContentClassifier.ContentType.COMMAND_OUTPUT then
        window = M.render_command_output(result_node_id, content, metadata)
    elseif content_type == ContentClassifier.ContentType.ERROR_CONTENT then
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
            zindex = WINDOW_LAYERS.CONTENT, -- Content popups appear above main window
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
            zindex = WINDOW_LAYERS.CONTENT, -- Content popups appear above main window
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
        content_type = ContentClassifier.ContentType.JSON_API_RESPONSE,
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
        enter = true, -- Focus popup when it opens
        focusable = true,
        zindex = WINDOW_LAYERS.CONTENT, -- Content popups appear above main window
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
        content_type = ContentClassifier.ContentType.FILE_CONTENT,
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
        enter = true, -- Focus popup when it opens
        focusable = true,
        zindex = WINDOW_LAYERS.CONTENT, -- Content popups appear above main window
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
        content_type = ContentClassifier.ContentType.COMMAND_OUTPUT,
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
        enter = true, -- Focus popup when it opens
        focusable = true,
        zindex = WINDOW_LAYERS.CONTENT, -- Content popups appear above main window
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
        content_type = ContentClassifier.ContentType.ERROR_CONTENT,
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
            zindex = WINDOW_LAYERS.CONTENT, -- Content popups appear above main window
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
            zindex = WINDOW_LAYERS.CONTENT, -- Content popups appear above main window
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
        content_type = ContentClassifier.ContentType.GENERIC_TEXT,
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
