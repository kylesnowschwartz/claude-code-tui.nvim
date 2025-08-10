---@brief [[
--- Conversation Repository - Data access layer for Claude conversations
--- Handles file system operations for discovering and listing conversation files
---@brief ]]

local ClaudePathMapper = require("cc-tui.services.claude_path_mapper")
local MetadataExtractor = require("cc-tui.services.metadata_extractor")
local log = require("cc-tui.util.log")

---@class CcTui.Services.ConversationRepository
local M = {}

---@class CcTui.ConversationMetadata
---@field filename string The JSONL filename
---@field path string Full path to the conversation file
---@field timestamp string ISO timestamp from JSON content
---@field size number File size in bytes
---@field modified number Last modified time (Unix timestamp)
---@field title? string Extracted conversation title (from first user message)
---@field message_count? number Number of messages in conversation

---List all conversation files in a project
---@param project_name string The project name
---@return CcTui.ConversationMetadata[] conversations List of conversation metadata
function M.list_conversations(project_name)
    vim.validate({
        project_name = { project_name, "string" },
    })

    local project_path = ClaudePathMapper.get_project_path(project_name)

    if vim.fn.isdirectory(project_path) == 0 then
        log.debug_safe("ConversationRepository", string.format("Project directory not found: %s", project_path))
        return {}
    end

    -- Find all JSONL files in project directory
    local files = vim.fn.glob(project_path .. "/*.jsonl", false, true)
    local conversations = {}

    for _, filepath in ipairs(files) do
        local filename = vim.fn.fnamemodify(filepath, ":t")
        local stat = vim.loop.fs_stat(filepath)

        if stat then
            table.insert(conversations, {
                filename = filename,
                path = filepath,
                timestamp = "unknown", -- Will be extracted from JSON content
                size = stat.size,
                modified = stat.mtime.sec,
                -- title and message_count will be populated by lazy loading
            })
        end
    end

    -- Sort by modified time initially (most recent first)
    -- This will be re-sorted by timestamp when metadata is enriched
    table.sort(conversations, function(a, b)
        return a.modified > b.modified
    end)

    log.debug_safe(
        "ConversationRepository",
        string.format("Found %d conversations in project %s", #conversations, project_name)
    )

    return conversations
end

---Get conversation metadata with lazy-loaded details - ASYNC
---@param conversation CcTui.ConversationMetadata Base conversation metadata
---@param callback function Callback(enriched_conversation)
function M.enrich_metadata_async(conversation, callback)
    vim.validate({
        conversation = { conversation, "table" },
        callback = { callback, "function" },
    })

    if conversation.title then
        -- Already enriched, call callback immediately
        callback(conversation)
        return
    end

    MetadataExtractor.extract_async(conversation.path, function(title, count, timestamp)
        conversation.title = title or "Untitled Conversation"
        conversation.message_count = count
        if timestamp then
            conversation.timestamp = timestamp
        end
        callback(conversation)
    end)
end

---Get conversation metadata with lazy-loaded details - SYNC
---@param conversation CcTui.ConversationMetadata Base conversation metadata
---@return CcTui.ConversationMetadata enriched Enriched with title, message count, and timestamp
function M.enrich_metadata_sync(conversation)
    if not conversation.title then
        local title, count, timestamp = MetadataExtractor.extract_sync(conversation.path)
        conversation.title = title or "Untitled Conversation"
        conversation.message_count = count
        if timestamp then
            conversation.timestamp = timestamp
        end
    end
    return conversation
end

---Sort conversations by timestamp (most recent first)
---@param conversations CcTui.ConversationMetadata[] List of conversation metadata
---@return CcTui.ConversationMetadata[] sorted Sorted conversations
function M.sort_by_timestamp(conversations)
    table.sort(conversations, function(a, b)
        -- If both have valid timestamps, use those
        if a.timestamp and a.timestamp ~= "unknown" and b.timestamp and b.timestamp ~= "unknown" then
            return a.timestamp > b.timestamp
        end
        -- Fall back to modified time
        return a.modified > b.modified
    end)
    return conversations
end

---Find the most recent conversation in a project
---@param project_name string The project name
---@return CcTui.ConversationMetadata? conversation Most recent conversation or nil
function M.get_most_recent(project_name)
    local conversations = M.list_conversations(project_name)
    if #conversations > 0 then
        return M.enrich_metadata_sync(conversations[1])
    end
    return nil
end

return M
