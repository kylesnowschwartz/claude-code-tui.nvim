---@brief [[
--- Claude Code conversation service
--- Provides access to most recent conversations
---@brief ]]

local ProjectDiscovery = require("cc-tui.services.project_discovery")
local log = require("cc-tui.utils.log")

---@class CcTui.Services.ClaudeState
local M = {}

---Get the most recent conversation for a project
---@param project_name string Project name
---@return table? conversation {path: string, timestamp: number} or nil
function M.get_most_recent_conversation(project_name)
    vim.validate({
        project_name = { project_name, "string" },
    })

    -- Get all conversations for the project
    local conversations = ProjectDiscovery.list_conversations(project_name)

    if not conversations or #conversations == 0 then
        return nil
    end

    -- Conversations are already sorted by modification time (newest first)
    -- Return the first one
    local most_recent = conversations[1]

    if most_recent then
        return {
            path = most_recent.path,
            timestamp = most_recent.modified,
            title = most_recent.title,
        }
    end

    return nil
end

---Get the current active conversation
---NOTE: We cannot detect which conversation is "current" without Claude Code's internal state
---This returns nil as we don't have access to that information
---@return nil
function M.get_current_conversation()
    -- We cannot determine the current conversation without access to Claude Code's runtime state
    -- The statusline API provides this info but only within the statusline script context
    return nil
end

---Check if a conversation path is the current active one
---NOTE: Always returns false as we cannot detect current conversation
---@param conversation_path string Path to conversation file
---@return boolean is_current Always false
function M.is_conversation_current(conversation_path)
    vim.validate({
        conversation_path = { conversation_path, "string" },
    })

    -- We cannot determine if a conversation is current
    return false
end

return M
