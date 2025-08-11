---@brief [[
--- Object-oriented Message model for Claude Code JSONL data
--- Base class for all message types with field accessors
---@brief ]]

---@class CcTui.Models.Message
---@field data table Raw JSON data
---@field type string Message type
local Message = {}
Message.__index = Message

---Create a new Message instance
---@param data table Raw JSON data
---@return CcTui.Models.Message
function Message.new(data)
    local self = setmetatable({}, Message)
    self.data = data or {}
    self.type = data.type
    return self
end

---Factory method to create appropriate message type from JSON
---@param json_data table Parsed JSON data
---@return CcTui.Models.Message
function Message.from_json(json_data)
    vim.validate({
        json_data = { json_data, "table" },
    })

    local message_type = json_data.type

    -- Dispatch to appropriate subclass based on type
    if message_type == "user" then
        local UserMessage = require("cc-tui.models.user_message")
        return UserMessage.new(json_data)
    elseif message_type == "assistant" then
        local AssistantMessage = require("cc-tui.models.assistant_message")
        return AssistantMessage.new(json_data)
    elseif message_type == "summary" then
        -- Summary messages use base Message class
        return Message.new(json_data)
    elseif message_type == "system" then
        -- System messages use base Message class
        return Message.new(json_data)
    else
        -- Default to base Message for unknown types
        return Message.new(json_data)
    end
end

-- Field Accessors

---Get message type
---@return string
function Message:get_type()
    return self.data.type
end

---Get session ID (handles both sessionId and session_id)
---@return string?
function Message:get_session_id()
    return self.data.sessionId or self.data.session_id
end

---Get current working directory
---@return string?
function Message:get_cwd()
    return self.data.cwd
end

---Get git branch
---@return string?
function Message:get_git_branch()
    return self.data.gitBranch or self.data.git_branch
end

---Get version
---@return string?
function Message:get_version()
    return self.data.version
end

---Get timestamp
---@return string?
function Message:get_timestamp()
    return self.data.timestamp
end

---Get UUID
---@return string?
function Message:get_uuid()
    return self.data.uuid
end

---Get parent UUID
---@return string?
function Message:get_parent_uuid()
    return self.data.parentUuid or self.data.parent_uuid
end

---Get request ID (for assistant messages)
---@return string?
function Message:get_request_id()
    return self.data.requestId or self.data.request_id
end

---Get message content (for user/assistant messages)
---@return table?
function Message:get_message()
    return self.data.message
end

---Get content (for system messages)
---@return string?
function Message:get_content()
    return self.data.content
end

---Get level (for system messages)
---@return string?
function Message:get_level()
    return self.data.level
end

---Get summary (for summary messages)
---@return string?
function Message:get_summary()
    return self.data.summary
end

-- Type checking methods

---Check if this is a user message
---@return boolean
function Message:is_user()
    return self.data.type == "user"
end

---Check if this is an assistant message
---@return boolean
function Message:is_assistant()
    return self.data.type == "assistant"
end

---Check if this is a system message
---@return boolean
function Message:is_system()
    return self.data.type == "system"
end

---Check if this is a summary message
---@return boolean
function Message:is_summary()
    return self.data.type == "summary"
end

---Check if this is a result message
---@return boolean
function Message:is_result()
    return self.data.type == "result"
end

-- Metadata extraction

---Get all metadata as a table
---@return table
function Message:get_metadata()
    return {
        parent_uuid = self:get_parent_uuid(),
        session_id = self:get_session_id(),
        cwd = self:get_cwd(),
        git_branch = self:get_git_branch(),
        version = self:get_version(),
        timestamp = self:get_timestamp(),
        uuid = self:get_uuid(),
        type = self:get_type(),
    }
end

---Check if message is part of a sidechain
---@return boolean
function Message:is_sidechain()
    return self.data.isSidechain == true
end

---Get user type
---@return string?
function Message:get_user_type()
    return self.data.userType or self.data.user_type
end

return Message
