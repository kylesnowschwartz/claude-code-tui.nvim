local log = {}

local longest_scope = 15

-- Log storage for tabbed interface
local log_entries = {}
local max_entries = 100

-- Add log entry to internal storage
local function add_log_entry(level, scope, message)
    local entry = {
        timestamp = os.date("%Y-%m-%d %H:%M:%S"),
        level = level,
        module = scope,
        message = message,
    }

    table.insert(log_entries, 1, entry) -- Add to front

    -- Trim to max entries
    if #log_entries > max_entries then
        for i = max_entries + 1, #log_entries do
            log_entries[i] = nil
        end
    end
end

--- prints only if debug is true.
---
---@param scope string: the scope from where this function is called.
---@param str string: the formatted string.
---@param ... any: the arguments of the formatted string.
---@private
function log.debug(scope, str, ...)
    return log.notify(scope, vim.log.levels.DEBUG, false, str, ...)
end

--- Safely prints debug messages only when the plugin is loaded and debug is enabled.
--- Eliminates the need for repeated `_G.CcTui and _G.CcTui.config and _G.CcTui.config.debug` checks.
---
---@param scope string: the scope from where this function is called.
---@param str string: the formatted string.
---@param ... any: the arguments of the formatted string.
function log.debug_safe(scope, str, ...)
    if _G.CcTui and _G.CcTui.config and _G.CcTui.config.debug then
        log.debug(scope, str, ...)
    end
end

--- prints only if debug is true.
---
---@param scope string: the scope from where this function is called.
---@param level string: the log level of vim.notify.
---@param verbose boolean: when false, only prints when config.debug is true.
---@param str string: the formatted string.
---@param ... any: the arguments of the formatted string.
---@private
function log.notify(scope, level, verbose, str, ...)
    if not verbose and _G.CcTui and _G.CcTui.config ~= nil and not _G.CcTui.config.debug then
        return
    end

    if string.len(scope) > longest_scope then
        longest_scope = string.len(scope)
    end

    for i = longest_scope, string.len(scope), -1 do
        if i < string.len(scope) then
            scope = string.format("%s ", scope)
        else
            scope = string.format("%s", scope)
        end
    end

    local formatted_message = string.format(str, ...)
    local full_message = string.format("[cc-tui.nvim@%s] %s", scope, formatted_message)

    -- Store debug messages in internal log instead of vim.notify for DEBUG level
    if level == vim.log.levels.DEBUG then
        add_log_entry("DEBUG", scope, formatted_message)
        return -- Don't send to vim.notify to avoid message buffer interruptions
    end

    -- Store all messages in internal log
    local level_name = "INFO"
    if level == vim.log.levels.WARN then
        level_name = "WARN"
    elseif level == vim.log.levels.ERROR then
        level_name = "ERROR"
    end
    add_log_entry(level_name, scope, formatted_message)

    -- Still send non-debug messages to vim.notify
    vim.notify(full_message, level, { title = "cc-tui.nvim" })
end

--- analyzes the user provided `setup` parameters and sends a message if they use a deprecated option, then gives the new option to use.
---
---@param options table: the options provided by the user.
---@private
function log.warn_deprecation(options)
    local uses_deprecated_option = false
    local notice = "is now deprecated, use `%s` instead."
    local root_deprecated = {
        foo = "bar",
        bar = "baz",
    }

    for name, warning in pairs(root_deprecated) do
        if options[name] ~= nil then
            uses_deprecated_option = true
            log.notify(
                "deprecated_options",
                vim.log.levels.WARN,
                true,
                string.format("`%s` %s", name, string.format(notice, warning))
            )
        end
    end

    if uses_deprecated_option then
        log.notify("deprecated_options", vim.log.levels.WARN, true, "sorry to bother you with the breaking changes :(")
        log.notify("deprecated_options", vim.log.levels.WARN, true, "use `:h CcTui.options` to read more.")
    end
end

-- Get stored log entries for logs view
function log.get_entries()
    return log_entries
end

-- Clear stored log entries
function log.clear_entries()
    log_entries = {}
end

return log
