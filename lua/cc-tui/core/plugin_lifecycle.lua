---@brief [[
--- Plugin Lifecycle Management
--- Extracted from main.lua for better separation of concerns
--- Handles plugin enable/disable state and initialization/cleanup
---@brief ]]

local log = require("cc-tui.utils.log")
local state = require("cc-tui.state")

---@class CcTui.Core.PluginLifecycle
local M = {}

---Initialize the plugin by delegating to UI and data loaders
---@param scope string Internal identifier for logging purposes
---@param ui_manager table UI manager instance
---@param data_loader table Data loader instance
---@param callback? function Optional callback to store messages (messages, root) -> nil
---@return boolean success True if initialization succeeded
function M.initialize(scope, ui_manager, data_loader, callback)
    vim.validate({
        scope = { scope, "string" },
        ui_manager = { ui_manager, "table" },
        data_loader = { data_loader, "table" },
        callback = { callback, "function", true },
    })

    if state:get_enabled() then
        log.debug(scope, "cc-tui is already enabled")
        return true
    end

    state:set_enabled()

    -- Load test data
    local root, err, messages = data_loader.load_test_data()
    if not root then
        log.debug("plugin_lifecycle", "Failed to load test data: " .. (err or "unknown error"))
        vim.notify("CC-TUI: Failed to load test data", vim.log.levels.ERROR)
        state:set_disabled()
        return false
    end

    -- Store messages if callback provided
    if callback and messages then
        callback(messages, root)
    end

    -- Initialize UI with loaded data
    local success = ui_manager.initialize(root, messages)
    if not success then
        log.debug("plugin_lifecycle", "Failed to initialize UI")
        state:set_disabled()
        return false
    end

    return true
end

---Cleanup and disable the plugin
---@param scope string Internal identifier for logging purposes
---@param ui_manager table UI manager instance
---@param stream_manager? table Optional stream manager for cleanup
---@return nil
function M.cleanup(scope, ui_manager, stream_manager)
    vim.validate({
        scope = { scope, "string" },
        ui_manager = { ui_manager, "table" },
        stream_manager = { stream_manager, "table", true },
    })

    if not state:get_enabled() then
        log.debug(scope, "cc-tui is already disabled")
        return
    end

    -- Stop any active streaming first
    if stream_manager then
        stream_manager.stop_streaming()
    end

    -- Cleanup UI components
    ui_manager.cleanup()

    -- Update state
    state:set_disabled()

    log.debug(scope, "cc-tui cleanup completed")
end

---Toggle plugin state (enable if disabled, disable if enabled)
---@param scope string Internal identifier for logging purposes
---@param ui_manager table UI manager instance
---@param data_loader table Data loader instance
---@param stream_manager? table Optional stream manager for cleanup
---@param callback? function Optional callback to store messages (messages, root) -> nil
---@return nil
function M.toggle(scope, ui_manager, data_loader, stream_manager, callback)
    vim.validate({
        scope = { scope, "string" },
        ui_manager = { ui_manager, "table" },
        data_loader = { data_loader, "table" },
        stream_manager = { stream_manager, "table", true },
        callback = { callback, "function", true },
    })

    if state:get_enabled() then
        log.debug(scope, "cc-tui is now disabled!")
        M.cleanup(scope, ui_manager, stream_manager)
    else
        log.debug(scope, "cc-tui is now enabled!")
        M.initialize(scope, ui_manager, data_loader, callback)
    end
end

---Check if plugin is currently enabled
---@return boolean enabled True if plugin is enabled
function M.is_enabled()
    return state:get_enabled()
end

return M
