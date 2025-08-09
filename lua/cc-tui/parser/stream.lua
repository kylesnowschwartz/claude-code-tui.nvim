---@brief [[
--- JSONL stream parser for Claude Code output
--- Parses line-delimited JSON from Claude Code's --output-format stream-json
---@brief ]]

---@class CcTui.Parser.Stream
local M = {}

---@class CcTui.Message
---@field type "system"|"assistant"|"user"|"result"
---@field subtype? string
---@field session_id string
---@field message? table
---@field parent_tool_use_id? string

---@class CcTui.ContentBlock
---@field type "text"|"tool_use"|"tool_result"
---@field text? string
---@field id? string Tool use ID
---@field tool_use_id? string Tool result reference
---@field name? string Tool name
---@field input? table Tool input parameters
---@field content? any Tool result content

---Parse a single JSONL line into a message object
---@param line string JSON line to parse
---@return CcTui.Message? message Parsed message or nil if invalid
---@return string? error Error message if parsing failed
function M.parse_line(line)
    vim.validate({
        line = { line, "string" },
    })

    -- Skip empty lines
    if line == "" then
        return nil, nil
    end

    local ok, data = pcall(vim.json.decode, line)
    if not ok then
        return nil, "Failed to parse JSON: " .. tostring(data)
    end

    -- Validate required fields
    if not data.type then
        return nil, "Missing required field: type"
    end

    return data, nil
end

---Build message index for linking tool uses with results
---@param messages CcTui.Message[] List of parsed messages
---@return table<string, CcTui.Message> tool_uses Map of tool_use_id to message
---@return table<string, CcTui.Message> tool_results Map of tool_use_id to result message
function M.build_message_index(messages)
    vim.validate({
        messages = { messages, "table" },
    })

    local tool_uses = {}
    local tool_results = {}

    for _, msg in ipairs(messages) do
        if msg.type == "assistant" and msg.message and msg.message.content then
            -- Find tool use blocks
            for _, content in ipairs(msg.message.content) do
                if content.type == "tool_use" and content.id then
                    tool_uses[content.id] = msg
                end
            end
        elseif msg.type == "user" and msg.message and msg.message.content then
            -- Find tool result blocks
            for _, content in ipairs(msg.message.content) do
                if content.type == "tool_result" and content.tool_use_id then
                    tool_results[content.tool_use_id] = msg
                end
            end
        end
    end

    return tool_uses, tool_results
end

---Parse multiple JSONL lines into a list of messages
---@param lines string[] Array of JSONL lines
---@return CcTui.Message[] messages List of parsed messages
---@return string[] errors List of parsing errors
function M.parse_lines(lines)
    vim.validate({
        lines = { lines, "table" },
    })

    local messages = {}
    local errors = {}

    for i, line in ipairs(lines) do
        local msg, err = M.parse_line(line)
        if msg then
            table.insert(messages, msg)
        elseif err then
            table.insert(errors, string.format("Line %d: %s", i, err))
        end
    end

    return messages, errors
end

---Extract text preview from message content
---@param message CcTui.Message Message to extract text from
---@return string? preview Text preview or nil
function M.get_text_preview(message)
    vim.validate({
        message = { message, "table" },
    })

    if message.type == "assistant" and message.message and message.message.content then
        for _, content in ipairs(message.message.content) do
            if content.type == "text" and content.text then
                -- Return first 80 characters or until newline
                local text = content.text
                local newline_pos = text:find("\n")
                if newline_pos then
                    text = text:sub(1, newline_pos - 1)
                end
                if #text > 80 then
                    text = text:sub(1, 77) .. "..."
                end
                return text
            end
        end
    end

    return nil
end

---Extract tool information from message
---@param message CcTui.Message Message to extract tool from
---@return table[] tools List of tool information {id, name, input}
function M.get_tools(message)
    vim.validate({
        message = { message, "table" },
    })

    local tools = {}

    if message.type == "assistant" and message.message and message.message.content then
        for _, content in ipairs(message.message.content) do
            if content.type == "tool_use" then
                table.insert(tools, {
                    id = content.id,
                    name = content.name,
                    input = content.input,
                })
            end
        end
    end

    return tools
end

---Get session information from messages
---@param messages CcTui.Message[] List of messages
---@return table? session_info Session information {id, start_time, tools}
function M.get_session_info(messages)
    vim.validate({
        messages = { messages, "table" },
    })

    for _, msg in ipairs(messages) do
        if msg.type == "system" and msg.subtype == "init" then
            return {
                id = msg.session_id,
                tools = msg.tools,
                model = msg.model,
                cwd = msg.cwd,
            }
        end
    end

    return nil
end

---Get result information from messages
---@param messages CcTui.Message[] List of messages
---@return table? result_info Result information {cost, duration, num_turns}
function M.get_result_info(messages)
    vim.validate({
        messages = { messages, "table" },
    })

    for i = #messages, 1, -1 do
        local msg = messages[i]
        if msg.type == "result" then
            return {
                success = msg.subtype == "success",
                cost_usd = msg.total_cost_usd,
                duration_ms = msg.duration_ms,
                num_turns = msg.num_turns,
            }
        end
    end

    return nil
end

return M
