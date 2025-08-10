---@brief [[
--- Data Loading and Processing
--- Extracted from main.lua for better separation of concerns
--- Handles conversation loading, parsing, and tree building
---@brief ]]

local ConversationProvider = require("cc-tui.providers.conversation")
local Parser = require("cc-tui.parser.stream")
local StaticProvider = require("cc-tui.providers.static")
local TreeBuilder = require("cc-tui.models.tree_builder")
local log = require("cc-tui.util.log")

---@class CcTui.Core.DataLoader
local M = {}

---Load and parse test data using StaticProvider
---@return CcTui.BaseNode? root Root node or nil
---@return string? error Error message if failed
---@return CcTui.Message[]? messages Parsed messages if successful
function M.load_test_data()
    local provider = StaticProvider:new({ limit = 500 })
    local lines = {}
    local error_message = nil

    -- Set up callbacks to collect data
    provider:register_callback("on_data", function(line)
        table.insert(lines, line)
    end)

    provider:register_callback("on_error", function(err)
        error_message = err
    end)

    -- Start provider (synchronous for StaticProvider)
    provider:start()

    -- Check for errors
    if error_message then
        return nil, error_message, nil
    end

    if #lines == 0 then
        return nil, "Failed to load test data", nil
    end

    -- Parse lines
    local messages, errors = Parser.parse_lines(lines)
    if #errors > 0 then
        log.debug("data_loader", string.format("Parse errors: %s", table.concat(errors, ", ")))
    end

    -- Get session info
    local session_info = Parser.get_session_info(messages)

    -- Build tree
    local root = TreeBuilder.build_tree(messages, session_info)

    return root, nil, messages
end

---Load conversation from JSONL file and build tree
---@param conversation_path string Path to conversation JSONL file
---@param callback function Callback to handle loaded data (messages, root, session_info)
---@return nil
function M.load_conversation(conversation_path, callback)
    vim.validate({
        conversation_path = { conversation_path, "string" },
        callback = { callback, "function" },
    })

    log.debug("data_loader", string.format("Loading conversation: %s", conversation_path))

    -- Create conversation provider
    local provider = ConversationProvider.new(conversation_path)

    -- Load messages
    provider:get_messages(function(messages)
        if #messages == 0 then
            vim.notify("Failed to load conversation", vim.log.levels.ERROR)
            return
        end

        -- Get session info
        local session_info = Parser.get_session_info(messages)

        -- Build tree
        local root = TreeBuilder.build_tree(messages, session_info)

        -- Call back with loaded data
        callback(messages, root, session_info, conversation_path)
    end)
end

---Parse streaming line data into messages
---@param line string Raw JSONL line from stream
---@return CcTui.Message? message Parsed message or nil if invalid
---@return string? error Error message if parsing failed
function M.parse_stream_line(line)
    if not line or line:match("^%s*$") then
        return nil, "Empty line"
    end

    local success, result = pcall(vim.fn.json_decode, line)
    if not success or not result then
        return nil, "JSON decode failed: " .. tostring(result)
    end

    -- Convert to internal message format if needed
    -- This would depend on your specific message structure requirements
    return result, nil
end

---Build tree from parsed messages
---@param messages CcTui.Message[] Array of parsed messages
---@return CcTui.BaseNode? root Root tree node or nil
---@return string? error Error message if failed
function M.build_tree_from_messages(messages)
    vim.validate({
        messages = { messages, "table" },
    })

    if #messages == 0 then
        return nil, "No messages to build tree"
    end

    -- Get session info
    local session_info = Parser.get_session_info(messages)

    -- Build tree
    local root = TreeBuilder.build_tree(messages, session_info)

    return root, nil
end

return M
