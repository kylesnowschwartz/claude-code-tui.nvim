---@brief [[
--- Conversation Formatter - UI display formatting utilities
--- Handles formatting conversation metadata for display in lists and tabs
---@brief ]]

---@class CcTui.UI.ConversationFormatter
local M = {}

---Format conversation metadata for display
---@param conversation CcTui.ConversationMetadata Conversation metadata
---@return string display_text Formatted display text for tab/list
function M.format_display(conversation)
    -- Format timestamp for display
    local timestamp_display = "unknown"
    if conversation.timestamp and conversation.timestamp ~= "unknown" then
        -- Parse ISO timestamp and format nicely
        local year, month, day, hour, min = conversation.timestamp:match("(%d+)%-(%d+)%-(%d+)T(%d+):(%d+)")
        if year then
            timestamp_display = string.format("%s/%s %s:%s", month, day, hour, min)
        end
    end

    -- Format size
    local size_display = "0B"
    if conversation.size then
        if conversation.size < 1024 then
            size_display = string.format("%dB", conversation.size)
        elseif conversation.size < 1024 * 1024 then
            size_display = string.format("%.1fKB", conversation.size / 1024)
        else
            size_display = string.format("%.1fMB", conversation.size / (1024 * 1024))
        end
    end

    -- Build display text
    local title = conversation.title or "Loading..."
    local message_info = conversation.message_count and string.format(" (%d msgs)", conversation.message_count) or ""

    return string.format("%s%s • %s • %s", title, message_info, timestamp_display, size_display)
end

return M
