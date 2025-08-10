---@brief [[
--- Base interface for data providers
--- Provides common callback mechanism for data streaming
---@brief ]]

-- Conditionally require log to handle test environments where global state isn't initialized
local log
if pcall(require, "cc-tui.utils.log") and _G.CcTui then
    log = require("cc-tui.utils.log")
else
    -- Simple fallback for test environments
    log = {
        debug = function(_, _) end,
    }
end

---@class CcTui.DataProvider
---@field callbacks table<string, function> Registered event callbacks
local M = {}

---Valid callback events that providers can trigger
---@type string[]
local VALID_EVENTS = {
    "on_data", -- New data line received
    "on_error", -- Error occurred
    "on_complete", -- Data stream completed
    "on_start", -- Data stream started
}

---Create a new data provider instance
---@return CcTui.DataProvider provider New provider instance
function M:new()
    vim.validate({})

    local provider = {
        callbacks = {},
    }

    setmetatable(provider, { __index = self })

    log.debug("provider.base", "Created new data provider instance")
    return provider
end

---Register a callback for a specific event
---@param event string Event name to register for
---@param callback function Function to call when event occurs
---@return nil
function M:register_callback(event, callback)
    vim.validate({
        event = { event, "string" },
        callback = { callback, "function" },
    })

    -- Validate event name
    local valid_event = false
    for _, valid in ipairs(VALID_EVENTS) do
        if event == valid then
            valid_event = true
            break
        end
    end

    if not valid_event then
        error(string.format("Invalid event name: %s. Valid events: %s", event, table.concat(VALID_EVENTS, ", ")))
    end

    self.callbacks[event] = callback
    log.debug("provider.base", string.format("Registered callback for event: %s", event))
end

---Start the data provider (abstract method - must be implemented by concrete providers)
---@return nil
function M:start()
    error("start() method must be implemented by concrete provider")
end

---Stop the data provider (abstract method - must be implemented by concrete providers)
---@return nil
function M:stop()
    error("stop() method must be implemented by concrete provider")
end

---Trigger a callback if it's registered
---@param event string Event name
---@param ... any Arguments to pass to callback
---@return nil
---@private
function M:_trigger_callback(event, ...)
    vim.validate({
        event = { event, "string" },
    })

    local callback = self.callbacks[event]
    if callback then
        log.debug("provider.base", string.format("Triggering callback for event: %s", event))
        callback(...)
    end
end

return M
