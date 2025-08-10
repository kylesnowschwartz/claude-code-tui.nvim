---@brief [[
--- Content Classification Service
--- Simplified single-file implementation focused on Claude conversation parsing
--- Classifies content from structured Claude Code data for optimal display strategy
---@brief ]]

---@class CcTui.Utils.ContentClassifier
local M = {}

---Content type enumeration
---@enum CcTui.ContentClassificationType
M.ContentType = {
    -- Always JSON display
    TOOL_INPUT = "tool_input", -- Tool parameters (always structured)
    JSON_API_RESPONSE = "json_api", -- MCP responses, API calls
    ERROR_OBJECT = "error_object", -- Structured error responses

    -- Context-aware display
    FILE_CONTENT = "file_content", -- Read tool results
    COMMAND_OUTPUT = "command_output", -- Bash/shell output
    ERROR_CONTENT = "error_content", -- Error content from tools

    -- Fallback
    GENERIC_TEXT = "generic_text", -- Plain text content
}

---@class CcTui.ClassificationResult
---@field type CcTui.ContentClassificationType Content type classification
---@field confidence number Confidence score (0.0-1.0)
---@field metadata table Additional classification metadata
---@field display_strategy string Recommended display strategy

---Configuration constants
local CONFIG = {
    thresholds = {
        rich_display_lines = 5,
        rich_display_chars = 200,
        json_parse_max_size = 1024 * 1024, -- 1MB limit for JSON parsing
    },
    display_strategies = {
        adaptive_popup_or_inline = "adaptive_popup_or_inline",
        json_popup_always = "json_popup_always",
        json_popup_with_folding = "json_popup_with_folding",
        error_popup_highlighted = "error_popup_highlighted",
        terminal_style_popup = "terminal_style_popup",
        syntax_highlighted_popup = "syntax_highlighted_popup",
        inline_with_syntax = "inline_with_syntax",
        inline_small_text = "inline_small_text",
    },
}

---Count lines in content
---@param content string Content to analyze
---@return number lines Number of lines
local function count_lines(content)
    if not content or content == "" then
        return 0
    end
    local _, count = string.gsub(content, "\n", "\n")
    return count + 1
end

---Robust JSON validation using protected calls
---@param content string Content to validate
---@return boolean is_json True if valid JSON
---@return table? parsed_data Parsed JSON data if valid
local function robust_json_validation(content)
    -- Quick size check to avoid parsing very large content
    if #content > CONFIG.thresholds.json_parse_max_size then
        return false, nil
    end

    -- Trim whitespace and check for basic JSON indicators
    local trimmed = content:match("^%s*(.-)%s*$") or ""
    if #trimmed == 0 then
        return false, nil
    end

    -- Must start and end with JSON delimiters
    local first_char = trimmed:sub(1, 1)
    local last_char = trimmed:sub(-1)

    if not ((first_char == "{" and last_char == "}") or (first_char == "[" and last_char == "]")) then
        return false, nil
    end

    -- Try to parse JSON with protected call
    local success, result = pcall(vim.fn.json_decode, trimmed)
    if success and type(result) == "table" then
        return true, result
    end

    return false, nil
end

---Detect file type from path or content
---@param path? string Optional file path
---@param content? string Optional content to analyze
---@return string file_type Detected file type
---@return string? syntax_language Language for syntax highlighting
local function detect_file_type(path, content)
    local file_type = "txt"
    local syntax_language = nil

    if path then
        local ext = path:match("%.([^%.]+)$")
        if ext then
            file_type = ext:lower()

            -- Map extensions to syntax highlighting languages
            if file_type == "tsx" or file_type == "ts" then
                syntax_language = "typescript"
            elseif file_type == "jsx" or file_type == "js" then
                syntax_language = "javascript"
            elseif file_type == "py" then
                syntax_language = "python"
            elseif file_type == "lua" then
                syntax_language = "lua"
            elseif file_type == "sh" or file_type == "bash" then
                syntax_language = "bash"
            elseif file_type == "env" then
                syntax_language = "bash" -- env files use shell-like syntax
            elseif file_type == "json" then
                syntax_language = "json"
            elseif file_type == "yaml" or file_type == "yml" then
                syntax_language = "yaml"
            end
        end
    end

    -- Basic content-based detection
    if content then
        if content:match("^#!/bin/bash") or content:match("^#!/bin/sh") then
            file_type = "bash"
            syntax_language = "bash"
        elseif content:match("^<[%?%w]") then
            file_type = "xml"
            syntax_language = "xml"
        elseif content:match("import.*from") or content:match("export.*default") then
            -- Check for TypeScript/React patterns
            if content:match("interface ") or content:match("type ") or content:match("<%w+>") then
                file_type = "tsx"
                syntax_language = "typescript"
            else
                file_type = "js"
                syntax_language = "javascript"
            end
        end
    end

    return file_type, syntax_language
end

---Infer tool name from structured data context
---@param structured_data table JSONL message structure
---@return string? tool_name Inferred tool name
local function infer_tool_name_from_context(structured_data)
    -- Direct tool name from structured data
    if structured_data.name then
        return structured_data.name
    end

    -- Check for tool_name field in structured data
    if structured_data.tool_name then
        return structured_data.tool_name
    end

    -- Check message content for tool_use items
    if structured_data.message and structured_data.message.content then
        local message_content = structured_data.message.content

        if type(message_content) == "table" then
            for _, content_item in ipairs(message_content) do
                if content_item and content_item.type == "tool_use" and content_item.name then
                    return content_item.name
                end
            end
        end
    end

    -- Check for parent context in tool results
    if structured_data.type == "tool_result" and structured_data.tool_use_id then
        -- Try to extract tool name from common MCP patterns
        local tool_use_id = structured_data.tool_use_id or ""
        if tool_use_id:match("bash") or tool_use_id:match("Bash") then
            return "Bash"
        elseif tool_use_id:match("read") or tool_use_id:match("Read") then
            return "Read"
        elseif tool_use_id:match("mcp__") then
            local mcp_tool = tool_use_id:match("mcp__([^_]+__[^_]+)")
            if mcp_tool then
                return "mcp__" .. mcp_tool
            end
        end
    end

    return nil
end

---Check if parsed JSON has nested structure
---@param parsed_json table Parsed JSON data
---@return boolean has_nested True if JSON has nested objects or arrays
local function has_nested_json_structure(parsed_json)
    if not parsed_json or type(parsed_json) ~= "table" then
        return false
    end

    -- Check if any values are nested objects or arrays
    for _, value in pairs(parsed_json) do
        if type(value) == "table" then
            return true
        end
    end

    return false
end

---Classify tool-specific output
---@param content string Tool output content
---@param tool_name string Tool name
---@param base_result table Base classification result
---@param confidence number Current confidence level
---@param stream_context? table Optional context from tool linking
---@return table updated_result Updated classification result
local function classify_tool_output(content, tool_name, base_result, confidence, stream_context)
    local result = vim.deepcopy(base_result)
    result.metadata.tool_name = tool_name

    -- Tool-specific classification
    if tool_name == "Read" then
        result.type = M.ContentType.FILE_CONTENT
        result.metadata.is_file_content = true

        -- Try to get file path from context for better type detection
        local file_path = nil
        if stream_context and stream_context.original_input and stream_context.original_input.file_path then
            file_path = stream_context.original_input.file_path
        end

        local file_type, syntax_language = detect_file_type(file_path, content)
        result.metadata.file_type = file_type
        if syntax_language then
            result.metadata.syntax_language = syntax_language
        end

        -- Determine display strategy based on size and content type
        local line_count = count_lines(content)
        local char_count = #content

        -- For Read tool results, prefer popup if it looks like code/structured content
        local looks_like_code = content:match("export ")
            or content:match("import ")
            or content:match("function ")
            or content:match("const ")
            or content:match("let ")
            or content:match("var ")

        if
            line_count <= CONFIG.thresholds.rich_display_lines
            and char_count <= CONFIG.thresholds.rich_display_chars
            and not looks_like_code
        then
            result.display_strategy = CONFIG.display_strategies.inline_with_syntax
            result.force_popup = false
        else
            result.display_strategy = CONFIG.display_strategies.syntax_highlighted_popup
            result.force_popup = true
        end
    elseif tool_name == "Bash" then
        result.type = M.ContentType.COMMAND_OUTPUT
        result.display_strategy = CONFIG.display_strategies.terminal_style_popup
        result.metadata.is_command_output = true
        result.force_popup = true -- Bash output always gets popup
        result.metadata.styling = "terminal"

        -- Extract command from stream context if available
        if stream_context and stream_context.original_input and stream_context.original_input.command then
            result.metadata.command = stream_context.original_input.command
        end
    elseif tool_name:match("^mcp__") then
        -- MCP tools often return JSON
        local is_json, parsed = robust_json_validation(content)
        if is_json then
            result.type = M.ContentType.JSON_API_RESPONSE
            result.display_strategy = CONFIG.display_strategies.json_popup_with_folding
            result.metadata.is_mcp_response = true
            result.metadata.is_mcp_tool = true
            result.metadata.json_parsed = parsed ~= nil
            result.metadata.is_json = true
            result.metadata.has_nested_structure = has_nested_json_structure(parsed)
            result.force_popup = true
            result.metadata.api_source = tool_name
        else
            result.display_strategy = CONFIG.display_strategies.adaptive_popup_or_inline
        end
    else
        -- Generic tool output
        result.display_strategy = CONFIG.display_strategies.adaptive_popup_or_inline
    end

    return result
end

---Get display strategy based on content type and size
---@param content_type CcTui.ContentClassificationType Content type
---@param content? string Optional content for size analysis
---@return string strategy Display strategy
local function get_display_strategy(content_type, content)
    if content_type == M.ContentType.TOOL_INPUT then
        return CONFIG.display_strategies.json_popup_always
    elseif content_type == M.ContentType.JSON_API_RESPONSE then
        return CONFIG.display_strategies.json_popup_with_folding
    elseif content_type == M.ContentType.ERROR_OBJECT then
        return CONFIG.display_strategies.error_popup_highlighted
    elseif content_type == M.ContentType.FILE_CONTENT then
        return CONFIG.display_strategies.file_content_popup
    elseif content_type == M.ContentType.COMMAND_OUTPUT then
        return CONFIG.display_strategies.terminal_output_popup
    else
        -- Adaptive display for generic content
        if content then
            local line_count = count_lines(content)
            local char_count = #content

            if
                line_count <= CONFIG.thresholds.rich_display_lines
                and char_count <= CONFIG.thresholds.rich_display_chars
            then
                return CONFIG.display_strategies.inline_small_text
            end
        end

        return CONFIG.display_strategies.adaptive_popup_or_inline
    end
end

---Detect error patterns in content
---@param content string Content to analyze
---@return boolean has_errors True if error patterns detected
local function detect_error_patterns(content)
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
local function infer_error_type(content)
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

---Check if content contains JSON structure
---@param content string Content to analyze
---@return boolean is_json True if JSON detected
---@return table? parsed_data Parsed data if JSON is valid
function M.is_json_content(content)
    return robust_json_validation(content)
end

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
            line_count = count_lines(content),
            structured_source = true,
        },
        display_strategy = CONFIG.display_strategies.adaptive_popup_or_inline,
    }

    -- DETERMINISTIC CLASSIFICATION based on Claude Code JSON structure

    -- Tool Input: content.type == "tool_use"
    if structured_data.type == "tool_use" then
        result.type = M.ContentType.TOOL_INPUT
        result.display_strategy = CONFIG.display_strategies.json_popup_always
        result.metadata.tool_name = structured_data.name
        result.metadata.tool_id = structured_data.id
        result.metadata.is_tool_input = true
        result.metadata.classification_method = "structured_tool_use"
        result.force_popup = true -- Tool inputs always force popup
        return result
    end

    -- Tool Result: Check if this is a tool_result type or has tool_result in message
    if structured_data.type == "tool_result" then
        result.type = M.ContentType.COMMAND_OUTPUT
        result.metadata.is_tool_result = true
        result.metadata.tool_use_id = structured_data.tool_use_id

        -- Use tool name from structured data or infer
        local tool_name = structured_data.tool_name or infer_tool_name_from_context(structured_data)
        if tool_name then
            result = classify_tool_output(content, tool_name, result, 1.0, nil)
        else
            result.display_strategy = get_display_strategy(result.type, content)
        end

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
                    local tool_name = structured_data.tool_name or infer_tool_name_from_context(structured_data)
                    if tool_name then
                        result = classify_tool_output(content, tool_name, result, 1.0, nil)
                    else
                        result.display_strategy = get_display_strategy(result.type, content)
                    end

                    return result
                end
            end
        end
    end

    -- Check for JSON content in the message
    local is_json, parsed_json = robust_json_validation(content)
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

        result.display_strategy = CONFIG.display_strategies.json_popup_with_folding
        return result
    end

    -- Error detection
    if detect_error_patterns(content) then
        result.type = M.ContentType.ERROR_OBJECT
        result.metadata.error_detected = true
        result.metadata.error_type = infer_error_type(content)
        result.display_strategy = CONFIG.display_strategies.error_popup_highlighted
        return result
    end

    -- Fallback: determine display strategy based on content
    result.display_strategy = get_display_strategy(result.type, content)
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
        result = classify_tool_output(content, tool_name, result, result.confidence)
    end

    return result
end

---Get display strategy for content type
---@param content_type CcTui.ContentClassificationType Content type
---@param content? string Optional content for size analysis
---@return string strategy Display strategy
function M.get_display_strategy(content_type, content)
    return get_display_strategy(content_type, content)
end

---Check if content should use rich display (popup)
---@param content string Content to analyze
---@return boolean should_use_rich True if should use rich display
function M.should_use_rich_display(content)
    if not content or content == "" then
        return false
    end

    -- JSON content always uses rich display (popup) regardless of size
    local is_json, _ = robust_json_validation(content)
    if is_json then
        return true
    end

    local line_count = count_lines(content)
    local char_count = #content

    return line_count > CONFIG.thresholds.rich_display_lines or char_count > CONFIG.thresholds.rich_display_chars
end

---Check if structured content should use rich display
---@param structured_data table JSONL message structure
---@param content string Content text
---@return boolean should_use_rich True if should use rich display
function M.should_use_rich_display_structured(structured_data, content)
    local result = M.classify_from_structured_data(structured_data, content)

    return result.display_strategy ~= CONFIG.display_strategies.inline_small_text
end

-- Backward compatibility methods for existing tests
M.is_json_content_structured = function(structured_data, content)
    return M.is_json_content(content)
end

M.classify_with_stream_context = function(structured_data, content, stream_context)
    local result = M.classify_from_structured_data(structured_data, content)

    -- Enhance with stream context if available
    if stream_context then
        -- Add stream context metadata
        if stream_context.tool_name then
            result.metadata.tool_name = stream_context.tool_name
        end
        if stream_context.tool_use_id then
            result.metadata.tool_use_id = stream_context.tool_use_id
        end
        if stream_context.is_tool_input then
            result.metadata.is_tool_input = true
        end
        if stream_context.is_tool_result then
            result.metadata.is_tool_result = true
        end

        -- Check for error flag in stream context or structured data
        if stream_context.is_error or (structured_data and structured_data.is_error) then
            result.type = M.ContentType.ERROR_CONTENT
            result.metadata.error_detected = true
            result.metadata.error_type = infer_error_type(content)
            result.display_strategy = CONFIG.display_strategies.error_popup_highlighted
            result.force_popup = true
            result.metadata.styling = "error_highlight"
            return result
        end

        -- Re-classify tool output with enhanced context if it's a tool result
        if stream_context.is_tool_result and stream_context.tool_name then
            result = classify_tool_output(content, stream_context.tool_name, result, result.confidence, stream_context)
        end

        -- Add additional metadata from stream context
        if stream_context.original_input then
            result.metadata.original_input = stream_context.original_input
        end
        if stream_context.session_id then
            result.metadata.session_id = stream_context.session_id
        end
        if stream_context.enhanced_context or stream_context.is_tool_input or stream_context.is_tool_result then
            result.metadata.enhanced_context = true
        end
    end

    return result
end

M.should_use_rich_display_with_context = function(content, stream_context)
    local basic_result = M.should_use_rich_display(content)

    -- Return enhanced result object for tests expecting additional metadata
    if stream_context then
        -- Create a fake structured_data for classification
        local structured_data = {
            type = "generic",
            message = { content = content },
        }

        -- If it's a tool result, set up proper structured data
        if stream_context.is_tool_result and stream_context.tool_name then
            structured_data.type = "tool_result"
            structured_data.tool_name = stream_context.tool_name
        end

        -- Get full classification to determine display strategy
        local classification_result = M.classify_with_stream_context(structured_data, content, stream_context)

        -- Return detailed decision object
        return {
            use_popup = classification_result.force_popup or basic_result,
            should_use_rich = basic_result,
            display_strategy = classification_result.display_strategy,
            context_aware = true,
            stream_context = stream_context,
        }
    end

    return basic_result
end

-- Private method compatibility for tests
M._count_lines = count_lines
M._detect_file_type = detect_file_type
M._infer_tool_name_from_context = infer_tool_name_from_context
M._detect_error_patterns = detect_error_patterns
M._robust_json_validation = robust_json_validation
M.detect_error_patterns = detect_error_patterns
M.infer_error_type = infer_error_type

return M
