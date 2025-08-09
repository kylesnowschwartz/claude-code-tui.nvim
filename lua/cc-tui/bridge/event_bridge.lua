---@brief [[
--- EventBridge for mapping Claude CLI JSON events to internal message format
--- Handles conversion between Claude CLI output and cc-tui internal structures
---@brief ]]

---@class CcTui.Bridge.EventBridge
local M = {}

---Validate if an event has the required structure
---@param event table Event object to validate
---@return boolean valid True if event is valid
function M.is_valid_event(event)
    vim.validate({
        event = { event, "table" },
    })

    -- Must have type field as string
    if not event.type or type(event.type) ~= "string" then
        return false
    end

    return true
end

---Map Claude CLI event to internal message format
---@param cli_event table Claude CLI JSON event
---@return CcTui.Message? message Mapped internal message or nil if invalid
function M.map_event(cli_event)
    vim.validate({
        cli_event = { cli_event, "table" },
    })

    -- Validate event structure
    if not M.is_valid_event(cli_event) then
        return nil
    end

    -- For most event types, pass through with minimal transformation
    -- This provides forward compatibility for unknown event types
    local mapped_event = vim.deepcopy(cli_event)

    -- Apply specific transformations based on event type
    if cli_event.type == "system" then
        return M._map_system_event(mapped_event)
    elseif cli_event.type == "assistant" then
        return M._map_assistant_event(mapped_event)
    elseif cli_event.type == "user" then
        return M._map_user_event(mapped_event)
    elseif cli_event.type == "result" then
        return M._map_result_event(mapped_event)
    else
        -- Unknown event types pass through unchanged for forward compatibility
        return mapped_event
    end
end

---Map system events (init, etc.)
---@param event table System event
---@return CcTui.Message message Mapped system message
function M._map_system_event(event)
    -- System events generally pass through unchanged
    -- They contain: type, subtype, session_id, model, cwd, etc.
    return event
end

---Map assistant message events
---@param event table Assistant event
---@return CcTui.Message message Mapped assistant message
function M._map_assistant_event(event)
    -- Assistant events contain message structure that should pass through
    -- Format: { type = "assistant", message = { id, role, content = [...] }, session_id }
    return event
end

---Map user message events
---@param event table User event
---@return CcTui.Message message Mapped user message
function M._map_user_event(event)
    -- User events (including tool results) pass through
    -- Format: { type = "user", message = { content = [{ type = "tool_result", ... }] } }
    return event
end

---Map result events (success/error summaries)
---@param event table Result event
---@return CcTui.Message message Mapped result message
function M._map_result_event(event)
    -- Result events contain session summary information
    -- Format: { type = "result", subtype = "success", total_cost_usd, duration_ms, etc. }
    return event
end

return M
