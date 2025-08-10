---@brief [[
--- Conversation data provider for loading Claude project conversations
--- Extends the base DataProvider to load JSONL conversation files
---@brief ]]

local DataProvider = require("cc-tui.providers.base")
local Parser = require("cc-tui.parser.stream")
local log = require("cc-tui.util.log")

---@class CcTui.ConversationProvider : CcTui.DataProvider
---@field file_path string Path to conversation JSONL file
---@field messages CcTui.Message[] Cached parsed messages
local M = setmetatable({}, { __index = DataProvider })

---Create a new conversation provider instance
---@param file_path string Path to conversation JSONL file
---@return CcTui.ConversationProvider provider New provider instance
function M.new(file_path)
    vim.validate({
        file_path = { file_path, "string" },
    })

    -- Create base provider instance
    local provider = DataProvider:new()

    -- Set up conversation-specific properties
    provider.file_path = file_path
    provider.messages = nil -- Lazy load

    setmetatable(provider, { __index = M })

    log.debug("ConversationProvider", string.format("Created provider for: %s", file_path))

    return provider
end

---Load and parse the conversation file
---@return CcTui.Message[] messages Parsed messages
---@return string? error Error message if loading failed
function M:load_conversation()
    -- Return cached if already loaded
    if self.messages then
        return self.messages, nil
    end

    -- Check file exists
    if vim.fn.filereadable(self.file_path) == 0 then
        local error_msg = string.format("Conversation file not found: %s", self.file_path)
        log.debug("ConversationProvider", error_msg)
        return {}, error_msg
    end

    -- Read file content
    local file = io.open(self.file_path, "r")
    if not file then
        local error_msg = string.format("Failed to open conversation file: %s", self.file_path)
        log.debug("ConversationProvider", error_msg)
        return {}, error_msg
    end

    local lines = {}
    for line in file:lines() do
        if line and line ~= "" then
            table.insert(lines, line)
        end
    end
    file:close()

    log.debug("ConversationProvider", string.format("Read %d lines from %s", #lines, self.file_path))

    -- Parse using existing parser
    local messages, errors = Parser.parse_lines(lines)

    -- Handle parsing errors
    if errors and #errors > 0 then
        local error_msg = string.format("Parsing errors in %s: %s", self.file_path, table.concat(errors, "; "))
        log.debug("ConversationProvider", error_msg)
        return {}, error_msg
    end

    -- Cache the messages
    self.messages = messages

    log.debug("ConversationProvider", string.format("Parsed %d messages", #messages))

    return messages, nil
end

---Get messages (DataProvider interface)
---@param callback function(messages: CcTui.Message[]) Callback with messages
---@return nil
function M:get_messages(callback)
    vim.validate({
        callback = { callback, "function" },
    })

    -- Load conversation synchronously (since we're reading from disk)
    local messages, error_msg = self:load_conversation()

    if error_msg then
        -- Return empty messages on error
        vim.notify(error_msg, vim.log.levels.ERROR)
        callback({})
    else
        callback(messages)
    end
end

---Start provider (no-op for static conversation files)
---@return nil
function M:start() -- luacheck: ignore 212/self
    -- No-op: conversation files are static
    log.debug("ConversationProvider", "Start called (no-op for static files)")
end

---Stop provider (clear cache)
---@return nil
function M:stop()
    -- Clear cached messages to free memory
    self.messages = nil
    log.debug("ConversationProvider", "Stopped and cleared cache")
end

---Get conversation metadata
---@return table metadata Conversation metadata
function M:get_metadata()
    local metadata = {
        type = "conversation",
        source = "file",
        path = self.file_path,
        filename = vim.fn.fnamemodify(self.file_path, ":t"),
    }

    -- Add message count if loaded
    if self.messages then
        metadata.message_count = #self.messages
    end

    -- Extract timestamp from filename if possible
    local timestamp = metadata.filename:match("conversation%-(.+)%.jsonl")
    if timestamp then
        metadata.timestamp = timestamp:gsub("%-", ":", 3)
    end

    return metadata
end

---Check if conversation is loaded
---@return boolean loaded Whether messages are loaded
function M:is_loaded()
    return self.messages ~= nil
end

---Get file size
---@return number size File size in bytes
function M:get_file_size()
    local stat = vim.loop.fs_stat(self.file_path)
    return stat and stat.size or 0
end

return M
