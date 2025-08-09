---@brief [[
--- Node type definitions for CC-TUI tree structure
--- Defines the different types of nodes in the collapsible tree
---@brief ]]

---@class CcTui.Models.Node
local M = {}

---@enum CcTui.NodeType
M.NodeType = {
    SESSION = "session",
    MESSAGE = "message",
    TOOL = "tool",
    RESULT = "result",
    TEXT = "text",
}

---@class CcTui.BaseNode
---@field id string Unique node identifier
---@field type CcTui.NodeType Node type
---@field text string Display text
---@field children CcTui.BaseNode[] Child nodes
---@field expanded boolean Whether node is expanded
---@field data table Additional node data

---@class CcTui.SessionNode : CcTui.BaseNode
---@field session_id string Session identifier
---@field timestamp? string Session start time
---@field model? string Model used
---@field cwd? string Working directory

---@class CcTui.MessageNode : CcTui.BaseNode
---@field message_id string Message identifier
---@field role "assistant"|"user" Message role
---@field preview string Text preview

---@class CcTui.ToolNode : CcTui.BaseNode
---@field tool_id string Tool use identifier
---@field tool_name string Tool name
---@field tool_input table Tool input parameters
---@field has_result boolean Whether tool has a result

---@class CcTui.ResultNode : CcTui.BaseNode
---@field tool_use_id string Reference to tool use
---@field content any Result content
---@field is_error boolean Whether result is an error

---Create a session node
---@param session_id string Session identifier
---@param data? table Additional session data
---@return CcTui.SessionNode node
function M.create_session_node(session_id, data)
    vim.validate({
        session_id = { session_id, "string" },
        data = { data, "table", true },
    })

    data = data or {}
    local timestamp = data.timestamp or os.date("%H:%M:%S")

    return {
        id = "session-" .. session_id,
        type = M.NodeType.SESSION,
        text = string.format("Session: %s [%s]", session_id:sub(1, 8), timestamp),
        children = {},
        expanded = true,
        data = data,
        session_id = session_id,
        timestamp = timestamp,
        model = data.model,
        cwd = data.cwd,
    }
end

---Create a message node
---@param message_id string Message identifier
---@param role "assistant"|"user" Message role
---@param preview? string Text preview
---@return CcTui.MessageNode node
function M.create_message_node(message_id, role, preview)
    vim.validate({
        message_id = { message_id, "string" },
        role = { role, "string" },
        preview = { preview, "string", true },
    })

    local icon = role == "assistant" and "Claude" or "User"
    preview = preview or ""

    -- Ensure single line and truncate if needed
    preview = preview:gsub("[\n\r]", " "):gsub("%s+", " ")
    if #preview > 80 then
        preview = preview:sub(1, 77) .. "..."
    end

    return {
        id = "msg-" .. message_id,
        type = M.NodeType.MESSAGE,
        text = string.format("%s: %s", icon, preview),
        children = {},
        expanded = false,
        data = {},
        message_id = message_id,
        role = role,
        preview = preview,
    }
end

---Create a tool node
---@param tool_id string Tool use identifier
---@param tool_name string Tool name
---@param tool_input? table Tool input parameters
---@return CcTui.ToolNode node
function M.create_tool_node(tool_id, tool_name, tool_input)
    vim.validate({
        tool_id = { tool_id, "string" },
        tool_name = { tool_name, "string" },
        tool_input = { tool_input, "table", true },
    })

    -- Extract primary argument for display
    local arg_display = ""
    if tool_input then
        if tool_input.file_path then
            arg_display = string.format(" [%s]", vim.fn.fnamemodify(tool_input.file_path, ":t"))
        elseif tool_input.command then
            local cmd = tool_input.command
            if #cmd > 30 then
                cmd = cmd:sub(1, 27) .. "..."
            end
            arg_display = string.format(" [%s]", cmd)
        elseif tool_input.libraryName then
            arg_display = string.format(" [%s]", tool_input.libraryName)
        end
    end

    -- Determine tool icon
    local icon = "🔧"
    if tool_name == "Read" then
        icon = "📖"
    elseif tool_name == "Write" then
        icon = "✏️"
    elseif tool_name == "Edit" or tool_name == "MultiEdit" then
        icon = "✏️"
    elseif tool_name == "Bash" then
        icon = "💻"
    elseif tool_name == "Task" then
        icon = "🔧"
    elseif tool_name:match("^mcp__") then
        icon = "🔌"
    end

    return {
        id = "tool-" .. tool_id,
        type = M.NodeType.TOOL,
        text = string.format("%s %s%s", icon, tool_name, arg_display),
        children = {},
        expanded = false,
        data = {},
        tool_id = tool_id,
        tool_name = tool_name,
        tool_input = tool_input or {},
        has_result = false,
    }
end

---Create a result node
---@param tool_use_id string Reference to tool use
---@param content any Result content
---@param is_error? boolean Whether result is an error
---@return CcTui.ResultNode node
function M.create_result_node(tool_use_id, content, is_error)
    vim.validate({
        tool_use_id = { tool_use_id, "string" },
        is_error = { is_error, "boolean", true },
    })

    local text = "Result"
    if is_error then
        text = "❌ Error"
    elseif type(content) == "string" then
        -- Show first line of content, sanitized
        local first_line = content:match("^[^\n\r]*")
        if first_line and #first_line > 0 then
            -- Remove any remaining control characters
            first_line = first_line:gsub("[\n\r\t]", " ")
            if #first_line > 60 then
                first_line = first_line:sub(1, 57) .. "..."
            end
            text = first_line
        end
    end

    return {
        id = "result-" .. tool_use_id,
        type = M.NodeType.RESULT,
        text = text,
        children = {},
        expanded = false,
        data = {},
        tool_use_id = tool_use_id,
        content = content,
        is_error = is_error or false,
    }
end

---Create a text node for displaying content
---@param text string Text content
---@param parent_id? string Parent node ID for unique identification
---@param counter? number Unique counter to ensure ID uniqueness
---@return CcTui.BaseNode node
function M.create_text_node(text, parent_id, counter)
    vim.validate({
        text = { text, "string" },
        parent_id = { parent_id, "string", true },
        counter = { counter, "number", true },
    })

    -- Sanitize text to ensure no newlines
    text = text:gsub("[\n\r]", " ")

    -- Generate unique ID with counter to prevent duplicates
    local id
    if counter then
        id = parent_id and (parent_id .. "-text-" .. tostring(counter)) or ("text-" .. tostring(counter))
    else
        -- Fallback to hash-based ID (for backwards compatibility)
        local text_hash = vim.fn.sha256(text):sub(1, 8)
        id = parent_id and (parent_id .. "-text-" .. text_hash) or ("text-" .. text_hash)
    end

    return {
        id = id,
        type = M.NodeType.TEXT,
        text = text,
        children = {},
        expanded = false,
        data = {},
    }
end

return M
