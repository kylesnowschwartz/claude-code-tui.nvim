---@brief [[
--- Tool Context Analysis Service
--- Extracted from content_classifier.lua for tool-specific logic separation
--- Handles tool-specific content classification and context analysis
---@brief ]]

local Config = require("cc-tui.utils.content_classifier_config")

---@class CcTui.Utils.ToolContext
local M = {}

---Classify tool output based on tool name and content
---@param content string Tool output content
---@param tool_name string Tool name
---@param base_result table Base classification result
---@param confidence number Current confidence level
---@return table updated_result Updated classification result
function M.classify_tool_output(content, tool_name, base_result, confidence)
    -- MCP tools (API responses)
    if tool_name:match("^mcp__") then
        base_result.type = Config.ContentType.JSON_API_RESPONSE
        base_result.confidence = math.min(1.0, confidence + 0.3)
        base_result.metadata.tool_type = "mcp"
        base_result.metadata.tool_name = tool_name -- Preserve tool name
        base_result.metadata.api_source = tool_name -- Full tool name as api_source
        base_result.metadata.is_json = true -- MCP responses are JSON
        base_result.display_strategy = "json_popup_with_folding"
        return base_result
    end

    -- Bash/shell commands
    if tool_name:match("^[Bb]ash") or tool_name == "sh" then
        base_result.type = Config.ContentType.COMMAND_OUTPUT
        base_result.confidence = math.min(1.0, confidence + 0.2)
        base_result.metadata.tool_type = "shell"
        base_result.metadata.tool_name = tool_name -- Preserve tool name
        base_result.display_strategy = "terminal_style_popup"
        return base_result
    end

    -- File operations
    local file_tools = {
        ["Read"] = Config.ContentType.FILE_CONTENT,
        ["Write"] = Config.ContentType.TOOL_INPUT,
        ["Edit"] = Config.ContentType.TOOL_INPUT,
        ["Glob"] = Config.ContentType.FILE_CONTENT,
        ["LS"] = Config.ContentType.FILE_CONTENT,
    }

    if file_tools[tool_name] then
        base_result.type = file_tools[tool_name]
        base_result.confidence = math.min(1.0, confidence + 0.2)
        base_result.metadata.tool_type = "file_operation"
        base_result.metadata.tool_name = tool_name -- Preserve tool name
        base_result.metadata.operation = tool_name:lower()

        -- File content gets syntax-aware display
        if base_result.type == Config.ContentType.FILE_CONTENT then
            base_result.metadata.file_type = M.detect_file_type(content)
            base_result.display_strategy = "syntax_highlighted_popup"
        end

        return base_result
    end

    -- Generic tool (likely tool input if structured)
    base_result.metadata.tool_type = "generic"
    base_result.metadata.tool_name = tool_name

    return base_result
end

---Detect file type from content
---@param content string File content to analyze
---@return string file_type Detected file type
function M.detect_file_type(content)
    if not content or content == "" then
        return "text"
    end

    local content_lower = content:sub(1, 200):lower() -- Check first 200 chars

    -- JSON detection
    if content_lower:match("^%s*[{%[]") then
        return "json"
    end

    -- XML/HTML detection
    if content_lower:match("<%?xml") or content_lower:match("<!doctype") or content_lower:match("^%s*<[%w]") then
        return content_lower:match("<!doctype html") and "html" or "xml"
    end

    -- Programming languages
    local language_patterns = {
        { pattern = "^%s*function", lang = "javascript" },
        { pattern = "^%s*import.*from", lang = "javascript" },
        { pattern = "^%s*def%s+", lang = "python" },
        { pattern = "^%s*class%s+.*:", lang = "python" },
        { pattern = "^%s*package%s+", lang = "go" },
        { pattern = "^%s*func%s+", lang = "go" },
        { pattern = "^%s*#include", lang = "c" },
        { pattern = "^%s*local%s+.*=", lang = "lua" },
    }

    for _, pattern_info in ipairs(language_patterns) do
        if content:match(pattern_info.pattern) then
            return pattern_info.lang
        end
    end

    -- Configuration files
    if content_lower:match("^%s*%[.*%]") and content:match("=") then
        return "ini"
    end

    if content:match("^%s*[%w_]+%s*[:=]") then
        return "config"
    end

    return "text"
end

---Infer tool name from structured data context
---@param structured_data table Structured message data
---@return string? tool_name Inferred tool name or nil
function M.infer_tool_name_from_context(structured_data)
    if not structured_data or type(structured_data) ~= "table" then
        return nil
    end

    -- Check for tool_use in content
    if structured_data.message and structured_data.message.content then
        local content = structured_data.message.content
        if type(content) == "table" and content[1] then
            for _, content_item in ipairs(content) do
                if content_item and content_item.type == "tool_use" and content_item.name then
                    return content_item.name
                end
            end
        end
    end

    -- Check for tool_result
    if structured_data.message and structured_data.message.content then
        local content = structured_data.message.content
        if type(content) == "table" and content[1] then
            for _, content_item in ipairs(content) do
                if content_item and content_item.type == "tool_result" then
                    -- Tool name might be in metadata or we need to infer from content
                    return "unknown_tool"
                end
            end
        end
    end

    return nil
end

return M
