---@brief [[
--- Claude Path Mapper - Project name to path mapping utilities
--- Handles conversion between directory paths and Claude CLI project naming conventions
---@brief ]]

local Config = require("cc-tui.config")
local PathSecurity = require("cc-tui.utils.path_security")
local log = require("cc-tui.utils.log")

---@class CcTui.Services.ClaudePathMapper
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
    log.debug_safe("ClaudePathMapper", string.format("Mapped cwd '%s' to project '%s'", cwd, project_name))

    return project_name
end

---Get the full path to a Claude project directory
---@param project_name string The project name
---@return string project_path Full path to project directory
function M.get_project_path(project_name)
    vim.validate({
        project_name = { project_name, "string" },
    })

    -- SECURITY: Use test data directory during testing to prevent real user data access
    if Config.is_testing_mode() then
        -- Point to docs/test/projects/ for safe test data
        local plugin_dir = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h:h")
        local test_path = string.format("%s/docs/test/projects/%s", plugin_dir, project_name)
        log.debug("ClaudePathMapper", string.format("Testing mode: Using test path %s", test_path))
        return test_path
    end

    local home = vim.fn.expand("~")
    local project_path = string.format("%s/.claude/projects/%s", home, project_name)

    return project_path
end

---Check if a Claude project exists
---@param project_name string The project name to check
---@return boolean exists Whether the project directory exists
function M.project_exists(project_name)
    local exists, err = PathSecurity.project_exists_safe(project_name)
    if err then
        log.debug_safe("ClaudePathMapper", "Project check failed: " .. err)
    end
    return exists
end

---List all available Claude projects
---@return string[] projects List of project names
function M.list_all_projects()
    local home = vim.fn.expand("~")
    local projects_dir = home .. "/.claude/projects"

    if vim.fn.isdirectory(projects_dir) == 0 then
        log.debug_safe("ClaudePathMapper", "No Claude projects directory found")
        return {}
    end

    local projects = {}
    local dirs = vim.fn.readdir(projects_dir, function(item)
        return vim.fn.isdirectory(projects_dir .. "/" .. item) == 1
    end)

    for _, dir in ipairs(dirs or {}) do
        table.insert(projects, dir)
    end

    log.debug_safe("ClaudePathMapper", string.format("Found %d projects", #projects))

    return projects
end

return M
