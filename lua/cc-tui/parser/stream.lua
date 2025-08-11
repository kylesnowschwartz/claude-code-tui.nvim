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
---@return CcTui.Message[] messages List of parsed and consolidated messages
---@return string[] errors List of parsing errors
function M.parse_lines(lines)
    vim.validate({
        lines = { lines, "table" },
    })

    local raw_messages = {}
    local errors = {}

    -- First pass: parse all lines
    for i, line in ipairs(lines) do
        local msg, err = M.parse_line(line)
        if msg then
            table.insert(raw_messages, msg)
        elseif err then
            table.insert(errors, string.format("Line %d: %s", i, err))
        end
    end

    -- Second pass: consolidate messages with same ID
    local consolidated = M.consolidate_messages(raw_messages)

    return consolidated, errors
end

---Consolidate messages that share the same message ID
---Claude Code outputs multiple JSONL lines for the same logical message
---@param raw_messages CcTui.Message[] Raw parsed messages
---@return CcTui.Message[] consolidated Consolidated messages
function M.consolidate_messages(raw_messages)
    vim.validate({
        raw_messages = { raw_messages, "table" },
    })

    local message_map = {}
    local consolidated = {}

    for _, msg in ipairs(raw_messages) do
        if msg.type == "assistant" and msg.message and msg.message.id then
            local msg_id = msg.message.id

            if message_map[msg_id] then
                -- Merge content into existing message
                local existing = message_map[msg_id]
                if msg.message.content then
                    for _, content in ipairs(msg.message.content) do
                        table.insert(existing.message.content, content)
                    end
                end
            else
                -- First occurrence of this message ID
                message_map[msg_id] = {
                    type = msg.type,
                    message = {
                        id = msg.message.id,
                        type = msg.message.type,
                        role = msg.message.role,
                        model = msg.message.model,
                        content = msg.message.content and vim.deepcopy(msg.message.content) or {},
                        stop_reason = msg.message.stop_reason,
                        stop_sequence = msg.message.stop_sequence,
                        usage = msg.message.usage,
                    },
                    parent_tool_use_id = msg.parent_tool_use_id,
                    session_id = msg.session_id,
                }
                table.insert(consolidated, message_map[msg_id])
            end
        else
            -- Non-assistant messages or messages without IDs pass through unchanged
            table.insert(consolidated, msg)
        end
    end

    return consolidated
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

    local session_info = {}
    local found_session = false

    -- Look for summary messages for a better title
    for _, msg in ipairs(messages) do
        if msg.type == "summary" and msg.summary then
            session_info.summary = msg.summary
            break
        end
    end

    -- First try to find a system init message (older format)
    for _, msg in ipairs(messages) do
        if msg.type == "system" and msg.subtype == "init" then
            session_info.id = msg.session_id or msg.sessionId
            session_info.tools = msg.tools
            session_info.model = msg.model
            session_info.cwd = msg.cwd
            found_session = true
            break
        end
    end

    -- Fall back to extracting sessionId from any message that has it
    if not found_session then
        for _, msg in ipairs(messages) do
            if msg.sessionId or msg.session_id then
                session_info.id = msg.sessionId or msg.session_id
                session_info.cwd = msg.cwd
                session_info.model = msg.model
                session_info.version = msg.version
                session_info.gitBranch = msg.gitBranch
                found_session = true
                break
            end
        end
    end

    if found_session then
        return session_info
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
