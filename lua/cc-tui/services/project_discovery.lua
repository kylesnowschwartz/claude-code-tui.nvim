---@brief [[
--- Project Discovery Service for Claude CLI conversation browsing
--- Maps working directories to Claude projects and discovers conversation files
---@brief ]]

local log = require("cc-tui.util.log")

---@class CcTui.Services.ProjectDiscovery
local M = {}

---Get the normalized project name from a directory path (matching Claude CLI convention)
---@param cwd string Current working directory path
---@return string project_name Project name matching Claude CLI's naming convention
function M.get_project_name(cwd)
    vim.validate({
        cwd = { cwd, "string" },
    })

    -- Claude CLI replaces all slashes and dots with hyphens
    local project_name = cwd:gsub("[/.]", "-")

    -- Safe logging (works even when _G.CcTui isn't initialized)
    if _G.CcTui and _G.CcTui.config and _G.CcTui.config.debug then
        log.debug("ProjectDiscovery", string.format("Mapped cwd '%s' to project '%s'", cwd, project_name))
    end

    return project_name
end

---Get the full path to a Claude project directory
---@param project_name string The project name
---@return string project_path Full path to project directory
function M.get_project_path(project_name)
    vim.validate({
        project_name = { project_name, "string" },
    })

    local home = vim.fn.expand("~")
    local project_path = string.format("%s/.claude/projects/%s", home, project_name)

    return project_path
end

---Check if a Claude project exists
---@param project_name string The project name to check
---@return boolean exists Whether the project directory exists
function M.project_exists(project_name)
    local project_path = M.get_project_path(project_name)
    return vim.fn.isdirectory(project_path) == 1
end

---List all available Claude projects
---@return string[] projects List of project names
function M.list_all_projects()
    local home = vim.fn.expand("~")
    local projects_dir = home .. "/.claude/projects"

    if vim.fn.isdirectory(projects_dir) == 0 then
        if _G.CcTui and _G.CcTui.config and _G.CcTui.config.debug then
            log.debug("ProjectDiscovery", "No Claude projects directory found")
        end
        return {}
    end

    local projects = {}
    local dirs = vim.fn.readdir(projects_dir, function(item)
        return vim.fn.isdirectory(projects_dir .. "/" .. item) == 1
    end)

    for _, dir in ipairs(dirs or {}) do
        table.insert(projects, dir)
    end

    if _G.CcTui and _G.CcTui.config and _G.CcTui.config.debug then
        log.debug("ProjectDiscovery", string.format("Found %d projects", #projects))
    end

    return projects
end

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

    local project_path = M.get_project_path(project_name)

    if vim.fn.isdirectory(project_path) == 0 then
        if _G.CcTui and _G.CcTui.config and _G.CcTui.config.debug then
            log.debug("ProjectDiscovery", string.format("Project directory not found: %s", project_path))
        end
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

    if _G.CcTui and _G.CcTui.config and _G.CcTui.config.debug then
        log.debug(
            "ProjectDiscovery",
            string.format("Found %d conversations in project %s", #conversations, project_name)
        )
    end

    return conversations
end

---Extract metadata from conversation file (title, message count, timestamp)
---@param conversation_path string Path to conversation JSONL file
---@return string? title First user message as title
---@return number message_count Total number of messages
---@return string? timestamp ISO timestamp from first message
function M.extract_conversation_metadata(conversation_path)
    vim.validate({
        conversation_path = { conversation_path, "string" },
    })

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
                    -- Extract text from user message
                    if data.message and data.message.content then
                        -- Handle both array and string formats
                        if type(data.message.content) == "table" then
                            -- Array format (from tests)
                            for _, content in ipairs(data.message.content) do
                                if content.type == "text" and content.text then
                                    first_user_message = content.text
                                    break
                                end
                            end
                        elseif type(data.message.content) == "string" then
                            -- String format (from real Claude CLI)
                            local content = data.message.content

                            -- Skip tool results and other non-meaningful content
                            if
                                not content:match("<status>")
                                and not content:match("tool_use_id")
                                and content:len() > 10
                            then
                                first_user_message = content
                            end
                        end

                        -- Extract title from first user message
                        if first_user_message then
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
                            title = extracted_title:gsub("^%s+", ""):gsub("%s+$", "") -- trim whitespace
                            if #title > 80 then
                                title = title:sub(1, 77) .. "..."
                            end
                        end
                    end
                end
            end
        end
    end

    file:close()

    return title, message_count, timestamp
end

---Get conversation metadata with lazy-loaded details
---@param conversation CcTui.ConversationMetadata Base conversation metadata
---@return CcTui.ConversationMetadata enriched Enriched with title, message count, and timestamp
function M.enrich_conversation_metadata(conversation)
    if not conversation.title then
        local title, count, timestamp = M.extract_conversation_metadata(conversation.path)
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
function M.sort_conversations_by_timestamp(conversations)
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
function M.get_most_recent_conversation(project_name)
    local conversations = M.list_conversations(project_name)
    if #conversations > 0 then
        return M.enrich_conversation_metadata(conversations[1])
    end
    return nil
end

---Format conversation metadata for display
---@param conversation CcTui.ConversationMetadata Conversation metadata
---@return string display_text Formatted display text for tab/list
function M.format_conversation_display(conversation)
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
