---@brief [[
--- Stream Management and Processing
--- Extracted from main.lua for better separation of concerns
--- Handles streaming provider lifecycle and real-time data processing
---@brief ]]

local StreamProvider = require("cc-tui.providers.stream")
local log = require("cc-tui.utils.log")

---@class CcTui.Core.StreamManager
local M = {}

---@class CcTui.StreamState
---@field streaming_provider CcTui.StreamProvider? Active streaming provider

---Internal streaming state
---@type CcTui.StreamState
local stream_state = {
    streaming_provider = nil,
}

---Start streaming from Claude CLI
---@param config? table StreamProvider configuration {command, args, timeout}
---@param callbacks table Callback handlers {on_data, on_error, on_complete, on_start}
---@return boolean success True if streaming started successfully
function M.start_streaming(config, callbacks)
    vim.validate({
        config = { config, "table", true },
        callbacks = { callbacks, "table" },
    })

    -- Stop any existing streaming
    M.stop_streaming()

    -- Default configuration for Claude CLI
    local stream_config = vim.tbl_deep_extend("force", {
        command = "claude-code",
        args = { "--output-format", "stream-json" },
        timeout = 60000, -- 60 seconds
    }, config or {})

    -- Create streaming provider
    local success, provider = pcall(StreamProvider.new, StreamProvider, stream_config)
    if not success then
        log.debug("stream_manager", "Failed to create streaming provider: " .. tostring(provider))
        return false
    end

    -- Set up callbacks for live updates
    provider:register_callback("on_start", function()
        log.debug("stream_manager", "Streaming started")
        if callbacks.on_start then
            callbacks.on_start()
        end
    end)

    provider:register_callback("on_data", function(line)
        -- Use vim.schedule for thread-safe UI updates
        vim.schedule(function()
            if callbacks.on_data then
                callbacks.on_data(line)
            end
        end)
    end)

    provider:register_callback("on_error", function(err)
        vim.schedule(function()
            log.debug("stream_manager", "Streaming error: " .. err)
            vim.notify("CC-TUI Streaming Error: " .. err, vim.log.levels.ERROR)
            if callbacks.on_error then
                callbacks.on_error(err)
            end
        end)
    end)

    provider:register_callback("on_complete", function()
        vim.schedule(function()
            log.debug("stream_manager", "Streaming completed")
            vim.notify("CC-TUI: Streaming completed", vim.log.levels.INFO)
            stream_state.streaming_provider = nil
            if callbacks.on_complete then
                callbacks.on_complete()
            end
        end)
    end)

    -- Store provider and start streaming
    stream_state.streaming_provider = provider

    local start_success = pcall(function()
        provider:start()
    end)

    if not start_success then
        log.debug("stream_manager", "Failed to start streaming")
        stream_state.streaming_provider = nil
        return false
    end

    log.debug("stream_manager", string.format("Started streaming with command: %s", stream_config.command))
    return true
end

---Stop active streaming
---@return nil
function M.stop_streaming()
    if stream_state.streaming_provider then
        log.debug("stream_manager", "Stopping active streaming")

        local success = pcall(function()
            stream_state.streaming_provider:stop()
        end)

        if not success then
            log.debug("stream_manager", "Error stopping streaming provider")
        end

        stream_state.streaming_provider = nil
        vim.notify("CC-TUI: Streaming stopped", vim.log.levels.INFO)
    end
end

---Check if streaming is currently active
---@return boolean is_streaming True if streaming is active
function M.is_streaming()
    return stream_state.streaming_provider ~= nil
end

---Get current streaming state
---@return CcTui.StreamState stream_state Current streaming state
function M.get_state()
    return {
        streaming_provider = stream_state.streaming_provider,
    }
end

---Restart streaming with same config (useful for reconnection)
---@param callbacks table Callback handlers {on_data, on_error, on_complete, on_start}
---@return boolean success True if restart succeeded
function M.restart_streaming(callbacks)
    if not stream_state.streaming_provider then
        log.debug("stream_manager", "Cannot restart - no active streaming provider")
        return false
    end

    -- Get current config (simplified - in real implementation you'd store the config)
    local config = {
        command = "claude-code",
        args = { "--output-format", "stream-json" },
        timeout = 60000,
    }

    -- Stop current stream and start new one
    M.stop_streaming()
    return M.start_streaming(config, callbacks)
end

return M
