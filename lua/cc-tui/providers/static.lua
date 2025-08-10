---@brief [[
--- Static data provider for JSONL test data
--- Loads test data from files and provides via callback interface
---@brief ]]

local DataProvider = require("cc-tui.providers.base")
local TestData = require("cc-tui.parser.test_data")

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

---@class CcTui.StaticProvider : CcTui.DataProvider
---@field limit number Maximum number of lines to load
---@field lines string[]? Pre-loaded lines (if provided, skips TestData loading)
---@field uuid string? Conversation UUID (for real data identification)
local M = setmetatable({}, { __index = DataProvider })

---Default configuration for StaticProvider
---@type table
local default_config = {
    limit = 500, -- Maximum lines to load from test data
    lines = nil, -- Optional pre-loaded lines
    uuid = nil, -- Optional conversation UUID
}

---Create a new static data provider instance
---@param config? table Optional configuration
---@return CcTui.StaticProvider provider New static provider instance
function M:new(config)
    vim.validate({
        config = { config, "table", true },
    })

    config = vim.tbl_deep_extend("force", default_config, config or {})

    -- Create base provider instance
    local provider = DataProvider:new()

    -- Add StaticProvider-specific properties
    provider.limit = config.limit
    provider.lines = config.lines
    provider.uuid = config.uuid

    setmetatable(provider, { __index = self })

    if provider.lines then
        log.debug(
            "provider.static",
            string.format(
                "Created static provider with %d pre-loaded lines (UUID: %s)",
                #provider.lines,
                provider.uuid or "unknown"
            )
        )
    else
        log.debug("provider.static", string.format("Created static provider with limit: %d", provider.limit))
    end

    return provider
end

---Start the static data provider - loads test data and triggers callbacks
---@return nil
function M:start()
    log.debug("provider.static", "Starting static data provider")

    -- Trigger start callback
    self:_trigger_callback("on_start")

    local lines

    if self.lines then
        -- Use pre-loaded lines (real data)
        lines = self.lines
        log.debug("provider.static", string.format("Using %d pre-loaded lines", #lines))
    else
        -- Load test data from TestData module
        lines = TestData.load_sample_lines(self.limit)
        log.debug("provider.static", string.format("Loaded %d lines of test data", #lines))
    end

    if #lines == 0 then
        log.debug("provider.static", "No data available")
        self:_trigger_callback("on_error", "No data to provide")
        return
    end

    -- Trigger data callbacks for each line
    for _, line in ipairs(lines) do
        self:_trigger_callback("on_data", line)
    end

    -- Trigger completion callback
    self:_trigger_callback("on_complete")

    log.debug("provider.static", "Static data provider completed")
end

---Stop the static data provider (no-op for static provider)
---@return nil
function M:stop()
    log.debug("provider.static", "Static provider stopped")
    -- No-op for static provider since all data is provided synchronously
end

return M
