---@brief [[
--- AssistantMessage class for handling assistant messages in Claude Code JSONL
--- Handles text content and tool uses
---@brief ]]

local Message = require("cc-tui.models.message")

---@class CcTui.Models.AssistantMessage : CcTui.Models.Message
local AssistantMessage = setmetatable({}, { __index = Message })
AssistantMessage.__index = AssistantMessage

---Create a new AssistantMessage instance
---@param data table Raw JSON data
---@return CcTui.Models.AssistantMessage
function AssistantMessage.new(data)
    local self = setmetatable(Message.new(data), AssistantMessage)
    return self
end

---Get the model used for this message
---@return string?
function AssistantMessage:get_model()
    if self.data.message and self.data.message.model then
        return self.data.message.model
    end
    return nil
end

---Get text content from the message
---@return string?
function AssistantMessage:get_text_content()
    if not self.data.message or not self.data.message.content then
        return nil
    end

    local content = self.data.message.content
    local text_parts = {}

    -- Handle array content
    if type(content) == "table" then
        for _, block in ipairs(content) do
            if block.type == "text" and block.text then
                table.insert(text_parts, block.text)
            end
        end
    elseif type(content) == "string" then
        -- Fallback for string content (shouldn't happen for assistant)
        return content
    end

    if #text_parts > 0 then
        return table.concat(text_parts, "\n")
    end

    return nil
end

---Get tool uses from the message
---@return table[] Array of tool use objects
function AssistantMessage:get_tool_uses()
    local tool_uses = {}

    if not self.data.message or not self.data.message.content then
        return tool_uses
    end

    local content = self.data.message.content

    -- Only process array content
    if type(content) == "table" then
        for _, block in ipairs(content) do
            if block.type == "tool_use" then
                table.insert(tool_uses, {
                    id = block.id,
                    name = block.name,
                    input = block.input,
                })
            end
        end
    end

    return tool_uses
end

---Check if message has tool uses
---@return boolean
function AssistantMessage:has_tool_uses()
    local tool_uses = self:get_tool_uses()
    return #tool_uses > 0
end

---Get message ID
---@return string?
function AssistantMessage:get_message_id()
    if self.data.message and self.data.message.id then
        return self.data.message.id
    end
    return nil
end

---Get stop reason
---@return string?
function AssistantMessage:get_stop_reason()
    if self.data.message and self.data.message.stop_reason then
        return self.data.message.stop_reason
    end
    return nil
end

---Get usage information
---@return table?
function AssistantMessage:get_usage()
    if self.data.message and self.data.message.usage then
        return {
            input_tokens = self.data.message.usage.input_tokens,
            output_tokens = self.data.message.usage.output_tokens,
            cache_creation_input_tokens = self.data.message.usage.cache_creation_input_tokens,
            cache_read_input_tokens = self.data.message.usage.cache_read_input_tokens,
        }
    end
    return nil
end

---Get the role (should always be "assistant" for AssistantMessage)
---@return string
function AssistantMessage:get_role()
    if self.data.message and self.data.message.role then
        return self.data.message.role
    end
    return "assistant"
end

---Check if this is an MCP tool use
---@param tool_use table Tool use object
---@return boolean
function AssistantMessage:is_mcp_tool(tool_use)
    if tool_use and tool_use.name then
        return tool_use.name:match("^mcp__") ~= nil
    end
    return false
end

---Parse MCP tool name into components
---@param tool_name string Full MCP tool name
---@return table? Components {server, tool} or nil
function AssistantMessage:parse_mcp_tool_name(tool_name)
    if not tool_name then
        return nil
    end

    -- Pattern: mcp__server__tool or mcp__server__namespace__tool
    local parts = {}
    for part in tool_name:gmatch("[^_]+") do
        if part ~= "mcp" and part ~= "" then
            table.insert(parts, part)
        end
    end

    if #parts >= 2 then
        return {
            server = parts[1],
            tool = table.concat(parts, "__", 2),
        }
    end

    return nil
end

return AssistantMessage
