---@brief [[
--- Claude Code state detection service
--- Detects current/active conversations and provides state tracking
---@brief ]]

local ProjectDiscovery = require("cc-tui.services.project_discovery")
local log = require("cc-tui.utils.log")

---@class CcTui.Services.ClaudeState
local M = {}

-- Cache for state file location
local state_cache = {
    path = nil,
    data = nil,
    last_check = 0,
}

-- Cache timeout in seconds
local CACHE_TIMEOUT = 5

---Try to find Claude Code's state file
---@return string? path Path to state file or nil
local function find_state_file()
    -- Check common locations for Claude state
    local possible_paths = {
        vim.fn.expand("~/.claude/state.json"),
        vim.fn.expand("~/.claude/current.json"),
        vim.fn.expand("~/.claude/statusline.json"),
        vim.fn.expand("~/.config/claude/state.json"),
    }

    for _, path in ipairs(possible_paths) do
        if vim.fn.filereadable(path) == 1 then
            log.debug("ClaudeState", string.format("Found state file at: %s", path))
            return path
        end
    end

    return nil
end

---Read and parse Claude state file
---@return table? state Parsed state data or nil
local function read_state_file()
    -- Check cache first
    local now = os.time()
    if state_cache.data and (now - state_cache.last_check) < CACHE_TIMEOUT then
        return state_cache.data
    end

    local state_path = state_cache.path or find_state_file()
    if not state_path then
        return nil
    end

    local ok, content = pcall(vim.fn.readfile, state_path)
    if not ok or not content then
        return nil
    end

    local json_str = table.concat(content, "\n")
    local success, data = pcall(vim.json.decode, json_str)

    if success and data then
        -- Update cache
        state_cache.path = state_path
        state_cache.data = data
        state_cache.last_check = now
        return data
    end

    return nil
end

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

---Get the current active conversation (if available)
---@return table? conversation {path: string, session_id: string} or nil
function M.get_current_conversation()
    -- Try to read state file
    local state = read_state_file()

    if not state then
        -- Fallback: check environment or command line
        local transcript_path = vim.env.CLAUDE_TRANSCRIPT_PATH
        if transcript_path and vim.fn.filereadable(transcript_path) == 1 then
            return {
                path = transcript_path,
                session_id = vim.env.CLAUDE_SESSION_ID,
            }
        end

        return nil
    end

    -- Extract transcript path from state
    if state.transcript_path and vim.fn.filereadable(state.transcript_path) == 1 then
        return {
            path = state.transcript_path,
            session_id = state.session_id,
            model = state.model and state.model.id,
        }
    end

    return nil
end

---Check if a conversation path is the current active one
---@param conversation_path string Path to conversation file
---@return boolean is_current True if this is the current conversation
function M.is_conversation_current(conversation_path)
    vim.validate({
        conversation_path = { conversation_path, "string" },
    })

    local current = M.get_current_conversation()

    if not current or not current.path then
        return false
    end

    -- Normalize paths for comparison
    local normalized_current = vim.fn.resolve(current.path)
    local normalized_check = vim.fn.resolve(conversation_path)

    return normalized_current == normalized_check
end

---Get model information from state
---@return table? model {id: string, name: string} or nil
function M.get_model_info()
    local state = read_state_file()

    if state and state.model then
        return {
            id = state.model.id,
            name = state.model.name or state.model.id,
        }
    end

    -- Try from current conversation
    local current = M.get_current_conversation()
    if current and current.model then
        return {
            id = current.model,
            name = current.model,
        }
    end

    return nil
end

---Clear the state cache (useful for testing or refresh)
function M.clear_cache()
    state_cache.data = nil
    state_cache.last_check = 0
end

return M
