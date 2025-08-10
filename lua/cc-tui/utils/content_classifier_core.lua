---@brief [[
--- Content Classifier Core - Refactored Main Classification Logic
--- Delegates to focused modules for better separation of concerns
--- Replaces the monolithic content_classifier.lua with clean architecture
---@brief ]]

local Config = require("cc-tui.utils.content_classifier_config")
local DisplayStrategy = require("cc-tui.utils.display_strategy")
local JsonDetector = require("cc-tui.utils.json_detector")
local ToolContext = require("cc-tui.utils.tool_context")

---@class CcTui.Utils.ContentClassifierCore
local M = {}

-- Re-export content types for backward compatibility
M.ContentType = Config.ContentType

---@class CcTui.ClassificationResult
---@field type CcTui.ContentClassificationType Content type classification
---@field confidence number Confidence score (0.0-1.0)
---@field metadata table Additional classification metadata
---@field display_strategy string Recommended display strategy

---Classify content from structured Claude Code data (deterministic)
---@param structured_data table Claude Code JSONL message structure
---@param content string Content text to classify
---@return CcTui.ClassificationResult result Classification result
function M.classify_from_structured_data(structured_data, content)
    vim.validate({
        structured_data = { structured_data, "table" },
        content = { content, "string" },
    })

    -- Initialize result structure
    local result = {
        type = M.ContentType.GENERIC_TEXT,
        confidence = 1.0, -- Always 100% confident with structured data
        metadata = {
            content_length = #content,
            line_count = DisplayStrategy.count_lines(content),
            structured_source = true,
        },
        display_strategy = "adaptive_popup_or_inline",
    }

    -- DETERMINISTIC CLASSIFICATION based on Claude Code JSON structure

    -- Tool Input: content.type == "tool_use"
    if structured_data.type == "tool_use" then
        result.type = M.ContentType.TOOL_INPUT
        result.display_strategy = "json_popup_always"
        result.metadata.tool_name = structured_data.name
        result.metadata.tool_id = structured_data.id
        result.metadata.is_tool_input = true
        return result
    end

    -- Tool Result: Check if this is a tool_result type or has tool_result in message
    if structured_data.type == "tool_result" then
        result.type = M.ContentType.COMMAND_OUTPUT
        result.metadata.is_tool_result = true
        result.metadata.tool_use_id = structured_data.tool_use_id

        -- Use tool name from structured data or infer
        local tool_name = structured_data.tool_name or ToolContext.infer_tool_name_from_context(structured_data)
        if tool_name then
            result = ToolContext.classify_tool_output(content, tool_name, result, 1.0)
        end

        result.display_strategy = DisplayStrategy.get_display_strategy(result.type)
        return result
    end

    -- Also check message content for tool_result items
    if structured_data.message and structured_data.message.content then
        local message_content = structured_data.message.content

        -- Handle both array and string content formats
        if type(message_content) == "table" then
            for _, content_item in ipairs(message_content) do
                if content_item and type(content_item) == "table" and content_item.type == "tool_result" then
                    result.type = M.ContentType.COMMAND_OUTPUT
                    result.metadata.is_tool_result = true
                    result.metadata.tool_use_id = content_item.tool_use_id

                    -- Infer tool name and classify accordingly
                    local tool_name = ToolContext.infer_tool_name_from_context(structured_data)
                    if tool_name then
                        result = ToolContext.classify_tool_output(content, tool_name, result, 1.0)
                    end

                    result.display_strategy = DisplayStrategy.get_display_strategy(result.type)
                    return result
                end
            end
        end
    end

    -- Check for JSON content in the message
    local is_json, parsed_json = JsonDetector.is_json_content(content)
    if is_json then
        result.type = M.ContentType.JSON_API_RESPONSE
        result.metadata.json_parsed = parsed_json ~= nil
        result.metadata.json_type = type(parsed_json)
        result.metadata.is_json = true

        -- Check if it's an MCP response pattern
        if parsed_json and type(parsed_json) == "table" then
            if parsed_json.jsonrpc or (parsed_json.result and parsed_json.id) then
                result.metadata.is_mcp_response = true
            end
            if parsed_json.error then
                result.type = M.ContentType.ERROR_OBJECT
                result.metadata.is_json_error = true
            end
        end

        result.display_strategy = "json_popup_with_folding"
        return result
    end

    -- Error detection
    if M.detect_error_patterns(content) then
        result.type = M.ContentType.ERROR_OBJECT
        result.metadata.error_detected = true
        result.metadata.error_type = M.infer_error_type(content)
        result.display_strategy = "error_popup_highlighted"
        return result
    end

    -- Fallback: determine display strategy based on content
    result.display_strategy = DisplayStrategy.get_display_strategy(result.type)
    return result
end

---Legacy classification method (delegates to structured version)
---@param content string Content to classify
---@param tool_name? string Tool name for context
---@param context? string|table Context - can be "input", "output", or additional data
---@return CcTui.ClassificationResult result Classification result
function M.classify(content, tool_name, context)
    -- Create minimal structured data for backward compatibility
    local structured_data = {
        type = "generic",
        message = { content = content },
    }

    -- If context indicates this is tool input, treat it as tool_use
    if context == "input" and tool_name then
        structured_data.type = "tool_use"
        structured_data.name = tool_name
        structured_data.id = "legacy_" .. tool_name
    end

    local result = M.classify_from_structured_data(structured_data, content)

    -- Apply tool-specific classification if tool_name provided and context is output
    if tool_name and (context == "output" or context == nil) then
        result = ToolContext.classify_tool_output(content, tool_name, result, result.confidence)
    end

    return result
end

---Detect error patterns in content
---@param content string Content to analyze
---@return boolean has_errors True if error patterns detected
function M.detect_error_patterns(content)
    if not content or content == "" then
        return false
    end

    local error_patterns = {
        "error:",
        "Error:",
        "ERROR:",
        "failed:",
        "Failed:",
        "FAILED:",
        "exception:",
        "Exception:",
        "EXCEPTION:",
        "traceback",
        "Traceback",
        "TRACEBACK",
        "panic:",
        "fatal:",
        "not found",
        "Not found",
        "NOT FOUND",
        "permission denied",
        "Permission denied",
        "access denied",
        "Access denied",
    }

    local content_lower = content:lower()
    for _, pattern in ipairs(error_patterns) do
        if content_lower:find(pattern:lower(), 1, true) then
            return true
        end
    end

    return false
end

---Infer specific error type from content
---@param content string Content to analyze
---@return string error_type Inferred error type
function M.infer_error_type(content)
    if not content or content == "" then
        return "unknown"
    end

    local content_lower = content:lower()

    if content_lower:find("not found", 1, true) or content_lower:find("no such file", 1, true) then
        return "file_not_found"
    elseif content_lower:find("permission denied", 1, true) or content_lower:find("access denied", 1, true) then
        return "permission_denied"
    elseif content_lower:find("syntax error", 1, true) or content_lower:find("parse error", 1, true) then
        return "syntax_error"
    elseif content_lower:find("timeout", 1, true) or content_lower:find("timed out", 1, true) then
        return "timeout"
    end

    return "generic"
end

-- Delegate methods to appropriate modules
M.get_display_strategy = DisplayStrategy.get_display_strategy
M.should_use_rich_display = DisplayStrategy.should_use_rich_display
M.should_use_rich_display_structured = DisplayStrategy.should_use_rich_display_structured
M.is_json_content = function(content, tool_name, context)
    local is_json, _ = JsonDetector.is_json_content(content)
    return is_json
end

return M
