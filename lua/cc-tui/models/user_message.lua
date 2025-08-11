---@brief [[
--- UserMessage class for handling user messages in Claude Code JSONL
--- Handles both text content and tool results
---@brief ]]

local Message = require("cc-tui.models.message")

---@class CcTui.Models.UserMessage : CcTui.Models.Message
local UserMessage = setmetatable({}, { __index = Message })
UserMessage.__index = UserMessage

---Create a new UserMessage instance
---@param data table Raw JSON data
---@return CcTui.Models.UserMessage
function UserMessage.new(data)
    local self = setmetatable(Message.new(data), UserMessage)
    return self
end

---Check if this is a tool result message
---@return boolean
function UserMessage:is_tool_result()
    return self.data.toolUseResult == true
end

---Get text content from the message
---@return string?
function UserMessage:get_text_content()
    if not self.data.message then
        return nil
    end

    local content = self.data.message.content

    -- Handle string content
    if type(content) == "string" then
        return content
    end

    -- Handle array content - look for text blocks
    if type(content) == "table" then
        for _, block in ipairs(content) do
            if block.type == "text" and block.text then
                return block.text
            end
        end

        -- For tool results, try to get the first result's content
        for _, block in ipairs(content) do
            if block.type == "tool_result" and type(block.content) == "string" then
                return block.content
            end
        end
    end

    return nil
end

---Get tool results from the message
---@return table[] Array of tool result objects
function UserMessage:get_tool_results()
    local results = {}

    if not self.data.message or not self.data.message.content then
        return results
    end

    local content = self.data.message.content

    -- Only process array content
    if type(content) == "table" then
        for _, block in ipairs(content) do
            if block.type == "tool_result" then
                table.insert(results, {
                    tool_use_id = block.tool_use_id,
                    content = block.content,
                    is_error = block.is_error,
                })
            end
        end
    end

    return results
end

---Check if the message contains SimpleClaude commands
---@return boolean
function UserMessage:has_simple_claude_command()
    local text = self:get_text_content()
    if text then
        return text:match("^<command%-args>") ~= nil or text:match("^<command%-message>") ~= nil
    end
    return false
end

---Extract SimpleClaude command information
---@return table? Command info with name and args
function UserMessage:get_simple_claude_command()
    if not self:has_simple_claude_command() then
        return nil
    end

    local text = self:get_text_content()
    if not text then
        return nil
    end

    local command_match = text:match("<command>(.-)</command>")
    local query_match = text:match("<query>(.-)</query>")
    local args_match = text:match("<command%-args>(.-)</command%-args>")

    return {
        command = command_match,
        query = query_match,
        args = args_match,
        raw = text,
    }
end

---Get the role (should always be "user" for UserMessage)
---@return string
function UserMessage:get_role()
    if self.data.message and self.data.message.role then
        return self.data.message.role
    end
    return "user"
end

return UserMessage
