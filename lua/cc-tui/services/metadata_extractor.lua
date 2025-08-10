---@brief [[
--- Metadata Extractor - Conversation file content analysis
--- Handles extraction of titles, message counts, and timestamps from JSONL files
---@brief ]]

local PathSecurity = require("cc-tui.utils.path_security")
local log = require("cc-tui.utils.log")

---@class CcTui.Services.MetadataExtractor
local M = {}

-- Title extraction constants
local TITLE_MAX_LENGTH = 80
local TITLE_TRUNCATE_SUFFIX = "..."

-- Metadata cache to avoid redundant file I/O (HIGH-2 optimization)
-- Cache structure: { [file_path] = { title, message_count, timestamp, mtime } }
local metadata_cache = {}

---Clear metadata cache for a specific file or all files
---@param file_path? string Optional file path to clear, or nil to clear all
function M.clear_cache(file_path)
    if file_path then
        metadata_cache[file_path] = nil
    else
        metadata_cache = {}
    end
end

---Extract title from user message content
---@param first_user_message string The first user message text
---@return string? title Extracted title or nil
local function extract_title_from_message(first_user_message)
    if not first_user_message then
        return nil
    end

    local extracted_title

    -- Handle SimpleClaude command format
    local command_args = first_user_message:match("<command%-args>(.-)</command%-args>")
    if command_args then
        -- Use the first line of command args as title
        extracted_title = command_args:match("^[^\n]*") or command_args
    else
        -- Use first line for regular messages
        extracted_title = first_user_message:match("^[^\n]*") or first_user_message
    end

    -- Trim and limit length
    local title = extracted_title:gsub("^%s+", ""):gsub("%s+$", "") -- trim whitespace
    if #title > TITLE_MAX_LENGTH then
        title = title:sub(1, TITLE_MAX_LENGTH - #TITLE_TRUNCATE_SUFFIX) .. TITLE_TRUNCATE_SUFFIX
    end

    return title
end

---Parse message content from JSON data
---@param data table JSON decoded message data
---@return string? content Extracted message content
local function parse_message_content(data)
    if not data.message or not data.message.content then
        return nil
    end

    -- Handle both array and string formats
    if type(data.message.content) == "table" then
        -- Array format (from tests)
        for _, content in ipairs(data.message.content) do
            if content.type == "text" and content.text then
                return content.text
            end
        end
    elseif type(data.message.content) == "string" then
        -- String format (from real Claude CLI)
        local content = data.message.content

        -- Skip tool results and other non-meaningful content
        if not content:match("<status>") and not content:match("tool_use_id") and content:len() > 10 then
            return content
        end
    end

    return nil
end

---Extract metadata from conversation file (title, message count, timestamp) - ASYNC
---@param conversation_path string Path to conversation JSONL file
---@param callback function Callback(title, message_count, timestamp)
function M.extract_async(conversation_path, callback)
    vim.validate({
        conversation_path = { conversation_path, "string" },
        callback = { callback, "function" },
    })

    -- Schedule async work to avoid blocking UI thread
    vim.schedule(function()
        local title, count, timestamp = M.extract_sync(conversation_path)
        callback(title, count, timestamp)
    end)
end

---Extract metadata from conversation file (title, message count, timestamp) - SYNC
---@param conversation_path string Path to conversation JSONL file
---@return string? title First user message as title
---@return number message_count Total number of messages
---@return string? timestamp ISO timestamp from first message
function M.extract_sync(conversation_path)
    -- Validate path security
    local safe, err = PathSecurity.is_safe_claude_path(conversation_path)
    if not safe then
        log.debug_safe("MetadataExtractor", "Unsafe path rejected: " .. (err or "unknown error"))
        return nil, 0
    end

    -- Check file stats for cache invalidation
    local stat = vim.loop.fs_stat(conversation_path)
    if not stat then
        return nil, 0
    end

    -- Check cache first (HIGH-2: avoid redundant I/O)
    local cached = metadata_cache[conversation_path]
    if cached and cached.mtime == stat.mtime.sec then
        return cached.title, cached.message_count, cached.timestamp
    end

    local file = io.open(conversation_path, "r")
    if not file then
        return nil, 0
    end

    local title = nil
    local message_count = 0
    local first_user_message = nil
    local timestamp = nil

    -- Read file line by line
    for line in file:lines() do
        if line and line ~= "" then
            message_count = message_count + 1

            local success, data = pcall(vim.fn.json_decode, line)
            if success and data and type(data) == "table" then
                -- Extract timestamp from first message
                if not timestamp and data.timestamp then
                    timestamp = data.timestamp
                end

                -- Try to extract title from first user message
                if not first_user_message and data.type == "user" then
                    first_user_message = parse_message_content(data)

                    if first_user_message then
                        title = extract_title_from_message(first_user_message)
                    end
                end
            end
        end
    end

    file:close()

    -- Cache the results (HIGH-2: avoid redundant I/O)
    metadata_cache[conversation_path] = {
        title = title,
        message_count = message_count,
        timestamp = timestamp,
        mtime = stat.mtime.sec,
    }

    return title, message_count, timestamp
end

return M
