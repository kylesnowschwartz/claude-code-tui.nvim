---@brief [[
--- JSONL stream parser for Claude Code output
--- Parses line-delimited JSON from Claude Code's --output-format stream-json
---@brief ]]

---@class CcTui.Parser.Stream
local M = {}

-- Import Message model classes
local Message = require("cc-tui.models.message")

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

-- New methods using Message model

---Parse a single JSONL line into a Message object
---@param line string JSON line to parse
---@return CcTui.Models.Message? message Parsed message or nil if invalid
---@return string? error Error message if parsing failed
function M.parse_line_with_model(line)
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

    -- Use Message factory to create appropriate type
    return Message.from_json(data), nil
end

---Build message index for linking tool uses with results using Message model
---@param messages CcTui.Models.Message[] List of Message objects
---@return table<string, CcTui.Models.Message> tool_uses Map of tool_use_id to message
---@return table<string, CcTui.Models.Message> tool_results Map of tool_use_id to result message
function M.build_message_index_with_model(messages)
    vim.validate({
        messages = { messages, "table" },
    })

    local tool_uses = {}
    local tool_results = {}

    for _, msg in ipairs(messages) do
        if msg:is_assistant() then
            -- Use AssistantMessage methods
            local tools = msg:get_tool_uses()
            for _, tool in ipairs(tools) do
                if tool.id then
                    tool_uses[tool.id] = msg
                end
            end
        elseif msg:is_user() then
            -- Use UserMessage methods
            local results = msg:get_tool_results()
            for _, result in ipairs(results) do
                if result.tool_use_id then
                    tool_results[result.tool_use_id] = msg
                end
            end
        end
    end

    return tool_uses, tool_results
end

---Parse multiple JSONL lines into a list of Message objects
---@param lines string[] Array of JSONL lines
---@return CcTui.Models.Message[] messages List of parsed Message objects
---@return string[] errors List of parsing errors
function M.parse_lines_with_model(lines)
    vim.validate({
        lines = { lines, "table" },
    })

    local raw_messages = {}
    local errors = {}

    -- First pass: parse all lines into Message objects
    for i, line in ipairs(lines) do
        local msg, err = M.parse_line_with_model(line)
        if msg then
            table.insert(raw_messages, msg)
        elseif err then
            table.insert(errors, string.format("Line %d: %s", i, err))
        end
    end

    -- Second pass: consolidate messages with same ID
    local consolidated = M.consolidate_messages_with_model(raw_messages)

    return consolidated, errors
end

---Consolidate Message objects that share the same message ID
---@param raw_messages CcTui.Models.Message[] Raw Message objects
---@return CcTui.Models.Message[] consolidated Consolidated Message objects
function M.consolidate_messages_with_model(raw_messages)
    vim.validate({
        raw_messages = { raw_messages, "table" },
    })

    local message_map = {}
    local consolidated = {}

    for _, msg in ipairs(raw_messages) do
        if msg:is_assistant() then
            local msg_id = msg:get_message_id()

            if msg_id and message_map[msg_id] then
                -- Merge content into existing message
                local existing = message_map[msg_id]
                local new_tools = msg:get_tool_uses()
                local new_text = msg:get_text_content()

                -- Merge tool uses
                if #new_tools > 0 then
                    local existing_data = existing.data
                    if existing_data.message and existing_data.message.content then
                        for _, tool in ipairs(new_tools) do
                            table.insert(existing_data.message.content, {
                                type = "tool_use",
                                id = tool.id,
                                name = tool.name,
                                input = tool.input,
                            })
                        end
                    end
                end

                -- Merge text content
                if new_text and existing.data.message and existing.data.message.content then
                    table.insert(existing.data.message.content, {
                        type = "text",
                        text = new_text,
                    })
                end
            elseif msg_id then
                -- First occurrence of this message ID
                message_map[msg_id] = msg
                table.insert(consolidated, msg)
            else
                -- No ID, pass through unchanged
                table.insert(consolidated, msg)
            end
        else
            -- Non-assistant messages pass through unchanged
            table.insert(consolidated, msg)
        end
    end

    return consolidated
end

---Extract text preview from Message object
---@param message CcTui.Models.Message Message object
---@return string? preview Text preview or nil
function M.get_text_preview_with_model(message)
    vim.validate({
        message = { message, "table" },
    })

    local text = nil

    if message:is_assistant() then
        text = message:get_text_content()
    elseif message:is_user() then
        text = message:get_text_content()
    end

    if text then
        -- Return first 80 characters or until newline
        local newline_pos = text:find("\n")
        if newline_pos then
            text = text:sub(1, newline_pos - 1)
        end
        if #text > 80 then
            text = text:sub(1, 77) .. "..."
        end
        return text
    end

    return nil
end

---Extract tool information from Message object
---@param message CcTui.Models.Message Message object
---@return table[] tools List of tool information {id, name, input}
function M.get_tools_with_model(message)
    vim.validate({
        message = { message, "table" },
    })

    if message:is_assistant() then
        return message:get_tool_uses()
    end

    return {}
end

---Get session information from Message objects
---@param messages CcTui.Models.Message[] List of Message objects
---@return table? session_info Session information {id, summary, cwd, gitBranch, version}
function M.get_session_info_with_model(messages)
    vim.validate({
        messages = { messages, "table" },
    })

    local session_info = {}
    local found_session = false

    -- Look for summary messages for a better title
    for _, msg in ipairs(messages) do
        if msg:is_summary() then
            session_info.summary = msg:get_summary()
            break
        end
    end

    -- Extract sessionId from any message that has it
    for _, msg in ipairs(messages) do
        local session_id = msg:get_session_id()
        if session_id then
            session_info.id = session_id
            session_info.cwd = msg:get_cwd()
            session_info.gitBranch = msg:get_git_branch()
            session_info.version = msg:get_version()

            -- For assistant messages, also get model
            if msg:is_assistant() then
                session_info.model = msg:get_model()
            end

            found_session = true
            break
        end
    end

    if found_session then
        return session_info
    end

    return nil
end

return M
