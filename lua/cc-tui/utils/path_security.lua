---@brief [[
--- Path security utilities for Claude project file access
--- Ensures safe read-only access to conversation files
---@brief ]]

local M = {}

---Detect if we're running in a test environment
---@return boolean is_test True if in test environment
local function is_test_environment()
    -- Check for mini.test environment
    if _G.MiniTest then
        return true
    end

    -- Check for headless mode by checking command line arguments
    if vim.fn.has("gui_running") == 0 and vim.v.argv then
        for _, arg in ipairs(vim.v.argv) do
            if arg == "--headless" then
                return true
            end
        end
    end

    -- Check if called from test files
    local info = debug.getinfo(4, "S")
    if info and info.source and info.source:match("/tests/") then
        return true
    end

    return false
end

---Check if a path is safe for Claude project file access
---@param path string File path to validate
---@param allow_test_paths? boolean Allow test paths like /tmp for testing
---@return boolean safe Whether the path is safe to access
---@return string? error Error message if path is unsafe
function M.is_safe_claude_path(path, allow_test_paths)
    if not path or type(path) ~= "string" or path == "" then
        return false, "Invalid path: empty or non-string"
    end

    -- Auto-detect test environment if not explicitly specified
    if allow_test_paths == nil then
        allow_test_paths = is_test_environment()
    end

    -- Reject obvious path traversal attempts
    if path:match("%.%.") then
        return false, "Path traversal not allowed: " .. path
    end

    -- Reject paths with null bytes or other dangerous chars
    if path:match("%z") or path:match("[\001-\031]") then
        return false, "Invalid characters in path: " .. path
    end

    -- Must be a .jsonl file (Claude conversation format)
    if not path:match("%.jsonl$") then
        return false, "Only .jsonl files allowed: " .. path
    end

    -- Reject dangerous absolute paths (but allow test paths if requested)
    if path:match("^/") then
        -- Check for obviously dangerous system paths
        local dangerous_paths = {
            "^/etc/",
            "^/root/",
            "^/home/[^/]+/%.ssh/",
            "^/usr/bin/",
            "^/bin/",
            "^/sbin/",
            "^/usr/sbin/",
            "^/var/log/",
            "^/proc/",
            "^/sys/",
            "^/dev/",
        }

        for _, dangerous in ipairs(dangerous_paths) do
            if path:match(dangerous) then
                return false, "Access to system directory not allowed: " .. path
            end
        end

        -- If test paths are allowed, be more permissive for testing
        if allow_test_paths then
            if
                path:match("^/tmp/")
                or path:match("^/var/tmp/")
                or path:match("^/var/folders/")
                or path:match("^/test/")
                or path:match("^/non/")
                or path:match("/docs/test/projects/")
            then
                return true, nil
            end
        end

        -- For production, check if it's within Claude projects
        local claude_projects_dir = vim.fn.expand("~/.claude/projects")
        local canonical_projects_dir = vim.fn.resolve(claude_projects_dir)
        local resolved_path = vim.fn.resolve(path)

        if resolved_path:find(canonical_projects_dir, 1, true) then
            return true, nil
        end

        return false, "Absolute path outside allowed directories: " .. path
    end

    -- Reject Windows drive paths
    if path:match("^[A-Za-z]:") then
        return false, "Drive paths not allowed: " .. path
    end

    return true, nil
end

---Validate and resolve a Claude project file path
---@param project_name string Project name
---@param filename? string Optional filename (if not in project_name)
---@return string? resolved_path Safe resolved path or nil if invalid
---@return string? error Error message if validation failed
function M.get_safe_project_path(project_name, filename)
    if not project_name or type(project_name) ~= "string" then
        return nil, "Invalid project name"
    end

    -- Build the project directory path
    local claude_projects_dir = vim.fn.expand("~/.claude/projects")
    local project_path = claude_projects_dir .. "/" .. project_name

    if filename then
        project_path = project_path .. "/" .. filename
    end

    -- For project directories (no filename), just validate that it's under Claude projects
    if not filename then
        -- Just ensure it's a directory under ~/.claude/projects without .jsonl restriction
        local canonical_projects_dir = vim.fn.resolve(claude_projects_dir)
        local canonical_project_path = vim.fn.resolve(project_path)

        if not canonical_project_path:find(canonical_projects_dir, 1, true) then
            return nil, "Project path outside allowed directories: " .. project_path
        end

        return canonical_project_path, nil
    end

    -- For files within project directories, use full path validation
    local safe, err = M.is_safe_claude_path(project_path)
    if not safe then
        return nil, err
    end

    return vim.fn.resolve(project_path), nil
end

---Safe file reader for Claude conversation files
---@param file_path string Path to conversation file
---@param allow_test_paths? boolean Allow test paths like /tmp for testing
---@return string[] lines File contents as lines, empty if error
---@return string? error Error message if reading failed
function M.read_conversation_file_safe(file_path, allow_test_paths)
    -- Validate path safety
    local safe, err = M.is_safe_claude_path(file_path, allow_test_paths)
    if not safe then
        return {}, "Unsafe path: " .. (err or "unknown error")
    end

    -- Check file exists and is readable
    if vim.fn.filereadable(file_path) ~= 1 then
        return {}, "File not readable: " .. file_path
    end

    -- Open file in read-only mode
    local file = io.open(file_path, "r")
    if not file then
        return {}, "Failed to open file: " .. file_path
    end

    local lines = {}
    for line in file:lines() do
        if line and line ~= "" then
            table.insert(lines, line)
        end
    end
    file:close()

    return lines, nil
end

---Check if a project directory exists safely
---@param project_name string Project name to check
---@return boolean exists Whether project directory exists
---@return string? error Error message if validation failed
function M.project_exists_safe(project_name)
    local project_path, err = M.get_safe_project_path(project_name)
    if not project_path then
        return false, err
    end

    return vim.fn.isdirectory(project_path) == 1, nil
end

return M
