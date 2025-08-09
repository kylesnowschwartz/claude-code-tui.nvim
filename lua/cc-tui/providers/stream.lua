---@brief [[
--- Streaming data provider for Claude CLI subprocess integration
--- Spawns Claude CLI process and streams JSON events through callback interface
---@brief ]]

local DataProvider = require("cc-tui.providers.base")
local EventBridge = require("cc-tui.bridge.event_bridge")

-- Conditionally require log to handle test environments where global state isn't initialized
local log
if pcall(require, "cc-tui.util.log") and _G.CcTui then
    log = require("cc-tui.util.log")
else
    -- Simple fallback for test environments
    log = {
        debug = function(_, _) end,
    }
end

---@class CcTui.StreamProvider : CcTui.DataProvider
---@field command string Command to execute
---@field args string[] Command arguments
---@field timeout number Timeout in milliseconds
---@field job_id number? Active job ID
local M = setmetatable({}, { __index = DataProvider })

---Default configuration for StreamProvider
---@type table
local default_config = {
    command = "claude-code",
    args = { "--output-format", "stream-json" },
    timeout = 30000, -- 30 seconds
}

---Create a new stream provider instance
---@param config table Configuration with command, args, timeout
---@return CcTui.StreamProvider provider New stream provider instance
function M:new(config)
    vim.validate({
        config = { config, "table" },
        ["config.command"] = { config.command, "string" },
        ["config.args"] = { config.args, "table", true },
        ["config.timeout"] = { config.timeout, "number", true },
    })

    config = vim.tbl_deep_extend("force", default_config, config or {})

    -- Create base provider instance
    local provider = DataProvider:new()

    -- Add StreamProvider-specific properties
    provider.command = config.command
    provider.args = config.args or {}
    provider.timeout = config.timeout
    provider.job_id = nil

    setmetatable(provider, { __index = self })

    log.debug(
        "provider.stream",
        string.format("Created stream provider: %s %s", provider.command, table.concat(provider.args, " "))
    )
    return provider
end

---Start the streaming provider - spawns subprocess and begins streaming
---@return nil
function M:start()
    log.debug("provider.stream", "Starting stream provider")

    -- Trigger start callback
    self:_trigger_callback("on_start")

    -- Build command args
    local cmd_args = vim.deepcopy(self.args)

    -- Spawn subprocess using vim.fn.jobstart
    local job_opts = {
        stdout_buffered = false,
        stderr_buffered = false,
        on_stdout = function(_, data, _)
            self:_handle_stdout(data)
        end,
        on_stderr = function(_, data, _)
            self:_handle_stderr(data)
        end,
        on_exit = function(_, exit_code, _)
            self:_handle_exit(exit_code)
        end,
    }

    -- Use pcall to catch jobstart errors (e.g., command not found)
    local ok, job_id = pcall(vim.fn.jobstart, vim.list_extend({ self.command }, cmd_args), job_opts)

    if not ok or job_id <= 0 then
        local error_msg = string.format(
            "Failed to start command '%s': %s",
            self.command,
            not ok and job_id or "command not found or invalid"
        )
        log.debug("provider.stream", error_msg)
        self:_trigger_callback("on_error", error_msg)
        return
    end

    self.job_id = job_id

    log.debug("provider.stream", string.format("Started subprocess with job ID: %d", self.job_id))
end

---Stop the streaming provider - terminates subprocess gracefully
---@return nil
function M:stop()
    log.debug("provider.stream", "Stopping stream provider")

    if self.job_id and self.job_id > 0 then
        -- Try graceful termination first
        vim.fn.jobstop(self.job_id)
        log.debug("provider.stream", string.format("Stopped job ID: %d", self.job_id))
        self.job_id = nil
    end
end

---Handle stdout data from subprocess
---@param data string[] Raw output lines from subprocess
---@return nil
function M:_handle_stdout(data)
    if not data or #data == 0 then
        return
    end

    for _, line in ipairs(data) do
        if line and line ~= "" then
            log.debug("provider.stream", string.format("Received line: %s", line))

            -- Try to parse as JSON and map through EventBridge
            local ok, json_event = pcall(vim.json.decode, line)
            if ok and EventBridge.is_valid_event(json_event) then
                local mapped_event = EventBridge.map_event(json_event)
                if mapped_event then
                    -- Convert back to JSON string for consistency with StaticProvider
                    local json_line = vim.json.encode(mapped_event)
                    self:_trigger_callback("on_data", json_line)
                else
                    log.debug("provider.stream", string.format("Failed to map event: %s", line))
                end
            else
                -- Pass through non-JSON lines (might be error messages or other output)
                self:_trigger_callback("on_data", line)
            end
        end
    end
end

---Handle stderr data from subprocess
---@param data string[] Error output lines from subprocess
---@return nil
function M:_handle_stderr(data)
    if not data or #data == 0 then
        return
    end

    for _, line in ipairs(data) do
        if line and line ~= "" then
            log.debug("provider.stream", string.format("Stderr: %s", line))
            self:_trigger_callback("on_error", line)
        end
    end
end

---Handle subprocess exit
---@param exit_code number Exit code from subprocess
---@return nil
function M:_handle_exit(exit_code)
    log.debug("provider.stream", string.format("Subprocess exited with code: %d", exit_code))

    self.job_id = nil

    if exit_code == 0 then
        self:_trigger_callback("on_complete")
    else
        self:_trigger_callback("on_error", string.format("Process exited with code: %d", exit_code))
    end
end

return M
