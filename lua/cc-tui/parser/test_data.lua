---@brief [[
--- Test data loader for Claude Code JSONL output
--- Provides helper functions to load and iterate through test data
---@brief ]]

local log = require("cc-tui.util.log")

---@class CcTui.Parser.TestData
local M = {}

---Load JSONL test data from file
---@param filepath? string Path to JSONL file (defaults to docs/claude-live-output.jsonl)
---@return string[] lines Array of JSONL lines
---@return string? error Error message if loading failed
function M.load_test_file(filepath)
    filepath = filepath or vim.fn.expand("~/Code/cc-tui.nvim/docs/claude-live-output.jsonl")

    vim.validate({
        filepath = { filepath, "string", true },
    })

    local file = io.open(filepath, "r")
    if not file then
        return {}, "Failed to open file: " .. filepath
    end

    local lines = {}
    for line in file:lines() do
        table.insert(lines, line)
    end
    file:close()

    log.debug("test_data", string.format("Loaded %d lines from %s", #lines, filepath))

    return lines, nil
end

---Create a mock streaming interface for development
---@param lines string[] Array of JSONL lines
---@return function next_line Iterator function that returns next line
function M.create_stream_iterator(lines)
    vim.validate({
        lines = { lines, "table" },
    })

    local index = 0
    return function()
        index = index + 1
        if index <= #lines then
            return lines[index]
        end
        return nil
    end
end

---Get sample messages for different types
---@return table samples Table of sample messages by type
function M.get_sample_messages()
    return {
        system_init = {
            type = "system",
            subtype = "init",
            session_id = "test-session-123",
            tools = { "Read", "Write", "Edit", "Bash" },
            model = "claude-3-5-sonnet",
            cwd = "/test/directory",
        },
        assistant_text = {
            type = "assistant",
            message = {
                id = "msg_test_123",
                role = "assistant",
                content = {
                    {
                        type = "text",
                        text = "I'll help you create a React component...",
                    },
                },
            },
            session_id = "test-session-123",
        },
        assistant_tool = {
            type = "assistant",
            message = {
                id = "msg_test_124",
                role = "assistant",
                content = {
                    {
                        type = "tool_use",
                        id = "toolu_test_001",
                        name = "Write",
                        input = {
                            file_path = "test.js",
                            content = "console.log('test');",
                        },
                    },
                },
            },
            session_id = "test-session-123",
        },
        user_result = {
            type = "user",
            message = {
                role = "user",
                content = {
                    {
                        type = "tool_result",
                        tool_use_id = "toolu_test_001",
                        content = { { type = "text", text = "File written successfully" } },
                    },
                },
            },
            session_id = "test-session-123",
        },
        result_success = {
            type = "result",
            subtype = "success",
            session_id = "test-session-123",
            total_cost_usd = 0.0123,
            duration_ms = 5432,
            num_turns = 3,
        },
    }
end

---Load a limited number of lines for testing
---@param limit? number Maximum number of lines to load (default 100)
---@return string[] lines Array of JSONL lines
function M.load_sample_lines(limit)
    limit = limit or 100

    local filepath = vim.fn.expand("~/Code/cc-tui.nvim/docs/claude-live-output.jsonl")
    local file = io.open(filepath, "r")
    if not file then
        log.debug("test_data", "Failed to open test file")
        return {}
    end

    local lines = {}
    local count = 0
    for line in file:lines() do
        table.insert(lines, line)
        count = count + 1
        if count >= limit then
            break
        end
    end
    file:close()

    log.debug("test_data", string.format("Loaded %d sample lines", #lines))

    return lines
end

return M
