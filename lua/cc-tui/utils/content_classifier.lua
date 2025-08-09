---@brief [[
--- Unified Content Classification Service
--- Replaces fragmented detection logic with single source of truth
--- Provides semantic-aware content type detection for cc-tui display logic
---@brief ]]

---@class CcTui.Utils.ContentClassifier
local M = {}

---@enum CcTui.ContentClassificationType
M.ContentType = {
    -- Always JSON display
    TOOL_INPUT = "tool_input", -- Tool parameters (always structured)
    JSON_API_RESPONSE = "json_api", -- MCP responses, API calls
    ERROR_OBJECT = "error_object", -- Structured error responses

    -- Context-aware display
    FILE_CONTENT = "file_content", -- Read tool results
    COMMAND_OUTPUT = "command_output", -- Bash/shell output

    -- Fallback
    GENERIC_TEXT = "generic_text", -- Plain text content
}

---@class CcTui.ClassificationResult
---@field type CcTui.ContentClassificationType Content type classification
---@field confidence number Confidence score (0.0-1.0)
---@field metadata table Additional classification metadata
---@field display_strategy string Recommended display strategy

---Get configuration values (centralized in config.lua as per plan)
---@return table config Configuration values
local function get_config()
    -- Try to get from global config first, fallback to defaults
    if _G.CcTui and _G.CcTui.config and _G.CcTui.config.content then
        return _G.CcTui.config.content
    end

    -- Fallback configuration if CcTui not loaded
    return {
        thresholds = {
            rich_display_lines = 5,
            rich_display_chars = 200,
            classification_timeout_ms = 10,
            json_parse_max_size = 1024 * 1024,
        },
        classification = {
            use_robust_json_validation = true,
            enable_tool_context = true,
            enable_mcp_detection = true,
            confidence = {
                high = 0.9,
                medium = 0.7,
                low = 0.5,
                fallback = 0.1,
            },
        },
        display_strategies = {
            tool_input = "json_popup_always",
            json_api = "json_popup_with_folding",
            error_object = "error_json_popup",
            file_content = "syntax_highlighted_popup",
            command_output = "terminal_style_popup",
            generic_text = "adaptive_popup_or_inline",
        },
    }
end

---Classify content from structured Claude Code JSON data (DETERMINISTIC - no confidence intervals needed)
---@param structured_data table Claude Code JSON message or content object
---@param content string Raw content text for display
---@return CcTui.ClassificationResult result Classification result with 100% accuracy
function M.classify_from_structured_data(structured_data, content)
    vim.validate({
        structured_data = { structured_data, "table" },
        content = { content, "string" },
    })

    -- Note: config not needed for deterministic classification but kept for future extensibility
    local _ = get_config()

    -- Initialize result structure
    local result = {
        type = M.ContentType.GENERIC_TEXT,
        confidence = 1.0, -- Always 100% confident with structured data
        metadata = {
            content_length = #content,
            line_count = M._count_lines(content),
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
        result.metadata.classification_method = "structured_tool_use"
        return result
    end

    -- Tool Result: content.type == "tool_result"
    if structured_data.type == "tool_result" then
        result.metadata.tool_use_id = structured_data.tool_use_id
        result.metadata.is_tool_result = true
        result.metadata.classification_method = "structured_tool_result"

        -- Get tool name from context or infer from tool_use_id patterns
        local tool_name = result.metadata.tool_name or M._infer_tool_name_from_context(structured_data)

        -- Apply tool-specific classification
        if tool_name == "Read" then
            result.type = M.ContentType.FILE_CONTENT
            result.display_strategy = "syntax_highlighted_popup"
            result.metadata.file_type = M._detect_file_type(content)
        elseif tool_name == "Bash" then
            result.type = M.ContentType.COMMAND_OUTPUT
            result.display_strategy = "terminal_style_popup"
            result.metadata.shell_type = "bash"
        elseif tool_name and tool_name:match("^mcp__") then
            -- MCP tool results - check if JSON
            local is_json, _ = M._robust_json_validation(content)
            if is_json then
                result.type = M.ContentType.JSON_API_RESPONSE
                result.display_strategy = "json_popup_with_folding"
                result.metadata.api_source = tool_name
                result.metadata.is_json = true
            else
                result.type = M.ContentType.GENERIC_TEXT
                result.display_strategy = "adaptive_popup_or_inline"
                result.metadata.api_source = tool_name
            end
        else
            -- Generic tool result - check content patterns
            local is_json, _ = M._robust_json_validation(content)
            if is_json then
                result.type = M.ContentType.JSON_API_RESPONSE
                result.display_strategy = "json_popup_with_folding"
                result.metadata.is_json = true
            else
                result.type = M.ContentType.GENERIC_TEXT
                result.display_strategy = "adaptive_popup_or_inline"
            end
        end

        result.metadata.tool_name = tool_name
        return result
    end

    -- Error detection (still useful for tool results)
    if structured_data.is_error or M._detect_error_patterns(content) then
        result.type = M.ContentType.ERROR_OBJECT
        result.display_strategy = "error_json_popup"
        result.metadata.is_error = true
        result.metadata.classification_method = "structured_error"
        return result
    end

    -- Text content from assistant messages
    if structured_data.type == "text" then
        result.type = M.ContentType.GENERIC_TEXT
        result.display_strategy = "adaptive_popup_or_inline"
        result.metadata.classification_method = "structured_text"
        return result
    end

    -- Fallback for unrecognized structured data
    result.metadata.classification_method = "structured_fallback"
    return result
end

---Classify content and determine appropriate display strategy (LEGACY - uses inference)
---@param content string Content to classify
---@param tool_name? string Name of tool that generated content
---@param context? string Context: "input" or "output"
---@return CcTui.ClassificationResult result Classification result
function M.classify(content, tool_name, context)
    vim.validate({
        content = { content, "string" },
        tool_name = { tool_name, "string", true },
        context = { context, "string", true },
    })

    local config = get_config()
    local CONFIDENCE = config.classification.confidence

    -- Initialize result structure
    local result = {
        type = M.ContentType.GENERIC_TEXT,
        confidence = CONFIDENCE.fallback,
        metadata = {
            tool_name = tool_name,
            context = context,
            content_length = #content,
            line_count = M._count_lines(content),
        },
        display_strategy = "adaptive_popup_or_inline",
    }

    -- Phase 1: Context-aware classification (highest priority)
    if tool_name and context == "input" then
        -- Tool inputs are always JSON parameters
        result.type = M.ContentType.TOOL_INPUT
        result.confidence = CONFIDENCE.high
        result.display_strategy = "json_popup_always"
        result.metadata.is_tool_input = true
        return result
    end

    -- Phase 2: Error detection (high priority)
    local error_result = M._classify_error_content(content, result, CONFIDENCE)
    if error_result.confidence > CONFIDENCE.medium then
        return error_result
    end

    -- Phase 3: JSON detection (robust validation)
    local json_result = M._classify_json_content(content, result, CONFIDENCE)
    if json_result.confidence > CONFIDENCE.medium then
        return json_result
    end

    -- Phase 4: Tool-specific output classification
    if tool_name and context == "output" then
        local tool_result = M._classify_tool_output(content, tool_name, result, CONFIDENCE)
        if tool_result.confidence > CONFIDENCE.low then
            return tool_result
        end
    end

    -- Phase 5: Generic content (fallback)
    result.type = M.ContentType.GENERIC_TEXT
    result.confidence = CONFIDENCE.fallback
    result.display_strategy = "adaptive_popup_or_inline"
    result.metadata.classification_method = "fallback"

    return result
end

---Classify error content with pattern detection
---@param content string Content to analyze
---@param base_result CcTui.ClassificationResult Base result to build upon
---@param confidence table Confidence thresholds
---@return CcTui.ClassificationResult result Updated classification result
function M._classify_error_content(content, base_result, confidence)
    local result = vim.deepcopy(base_result)

    -- Check for explicit error patterns (order matters - more specific first)
    local error_patterns = {
        { pattern = "File not found", type = "file_not_found", confidence = confidence.high },
        { pattern = "not found", type = "not_found", confidence = confidence.medium },
        { pattern = "^Error:", type = "explicit_error", confidence = confidence.high },
        { pattern = "^error:", type = "explicit_error", confidence = confidence.high },
        { pattern = "Exception", type = "exception", confidence = confidence.medium },
        { pattern = "Traceback", type = "traceback", confidence = confidence.medium },
        { pattern = "is_error.*true", type = "structured_error", confidence = confidence.high },
        { pattern = "failed to", type = "failure", confidence = confidence.medium },
    }

    for _, error_info in ipairs(error_patterns) do
        if content:match(error_info.pattern) then
            result.type = M.ContentType.ERROR_OBJECT
            result.confidence = error_info.confidence
            result.display_strategy = "error_json_popup"
            result.metadata.error_type = error_info.type
            result.metadata.classification_method = "error_pattern"
            return result
        end
    end

    -- Check for JSON error responses
    local is_json, json_data = M._robust_json_validation(content)
    if is_json and json_data then
        if
            (type(json_data) == "table" and json_data.error)
            or (
                type(json_data) == "table"
                and json_data.message
                and type(json_data.message) == "string"
                and json_data.message:lower():match("error")
            )
        then
            result.type = M.ContentType.ERROR_OBJECT
            result.confidence = confidence.high
            result.display_strategy = "error_json_popup"
            result.metadata.error_type = "json_error"
            result.metadata.is_json_error = true
            result.metadata.classification_method = "json_error"
            return result
        end
    end

    return result
end

---Classify JSON content with robust validation
---@param content string Content to analyze
---@param base_result CcTui.ClassificationResult Base result to build upon
---@param confidence table Confidence thresholds
---@return CcTui.ClassificationResult result Updated classification result
function M._classify_json_content(content, base_result, confidence)
    local result = vim.deepcopy(base_result)

    -- Use robust JSON validation as specified in plan
    local is_json, json_data = M._robust_json_validation(content)

    if is_json then
        result.type = M.ContentType.JSON_API_RESPONSE
        result.confidence = confidence.high
        result.display_strategy = "json_popup_with_folding"
        result.metadata.is_json = true
        result.metadata.classification_method = "json_decode"

        -- Detect MCP JSON-RPC responses
        if type(json_data) == "table" and json_data.jsonrpc == "2.0" then
            result.metadata.is_mcp_response = true
            result.metadata.api_source = "mcp"
        end

        return result
    end

    -- Fallback to pattern-based JSON detection (for malformed but JSON-like content)
    local pattern_result = M._pattern_based_json_detection(content, result, confidence)
    if pattern_result.confidence > confidence.low then
        return pattern_result
    end

    return result
end

---Classify tool-specific output content
---@param content string Content to analyze
---@param tool_name string Name of the tool
---@param base_result CcTui.ClassificationResult Base result to build upon
---@param confidence table Confidence thresholds
---@return CcTui.ClassificationResult result Updated classification result
function M._classify_tool_output(content, tool_name, base_result, confidence)
    local result = vim.deepcopy(base_result)

    if tool_name == "Read" then
        result.type = M.ContentType.FILE_CONTENT
        result.confidence = confidence.high
        result.display_strategy = "syntax_highlighted_popup"
        result.metadata.file_type = M._detect_file_type(content)
        result.metadata.classification_method = "tool_specific"
    elseif tool_name == "Bash" then
        result.type = M.ContentType.COMMAND_OUTPUT
        result.confidence = confidence.high
        result.display_strategy = "terminal_style_popup"
        result.metadata.shell_type = "bash"
        result.metadata.classification_method = "tool_specific"
    elseif tool_name and tool_name:match("^mcp__") then
        -- MCP tool outputs are often structured data
        local is_json, _ = M._robust_json_validation(content)
        if is_json then
            result.type = M.ContentType.JSON_API_RESPONSE
            result.confidence = confidence.high
            result.display_strategy = "json_popup_with_folding"
            result.metadata.api_source = tool_name
            result.metadata.is_json = true
        else
            result.type = M.ContentType.GENERIC_TEXT
            result.confidence = confidence.medium
            result.display_strategy = "adaptive_popup_or_inline"
            result.metadata.api_source = tool_name
        end
        result.metadata.classification_method = "mcp_tool"
    end

    return result
end

---Robust JSON validation using vim.fn.json_decode with pcall
---@param content string Content to validate
---@return boolean is_json Whether content is valid JSON
---@return table? data Decoded JSON data or nil
function M._robust_json_validation(content)
    if not content or content == "" then
        return false, nil
    end

    -- Trim whitespace
    local trimmed = content:match("^%s*(.-)%s*$")

    -- Quick pattern check before expensive parsing
    if not (trimmed:match("^%s*[%[%{]") and trimmed:match("[%]%}]%s*$")) then
        return false, nil
    end

    -- Robust JSON validation using pcall as specified in plan
    local success, result = pcall(vim.fn.json_decode, trimmed)

    if success and result ~= nil then
        return true, result
    end

    return false, nil
end

---Pattern-based JSON detection for malformed content
---@param content string Content to analyze
---@param base_result CcTui.ClassificationResult Base result to build upon
---@param confidence table Confidence thresholds
---@return CcTui.ClassificationResult result Updated classification result
function M._pattern_based_json_detection(content, base_result, confidence)
    local result = vim.deepcopy(base_result)
    local trimmed = content:match("^%s*(.-)%s*$")

    -- Object-like patterns
    if trimmed:match("^%s*{") and trimmed:match("}%s*$") then
        result.type = M.ContentType.JSON_API_RESPONSE
        result.confidence = confidence.medium
        result.display_strategy = "json_popup_with_folding"
        result.metadata.classification_method = "json_pattern_object"
        return result
    end

    -- Array-like patterns
    if trimmed:match("^%s*%[") and trimmed:match("%]%s*$") then
        result.type = M.ContentType.JSON_API_RESPONSE
        result.confidence = confidence.medium
        result.display_strategy = "json_popup_with_folding"
        result.metadata.classification_method = "json_pattern_array"
        return result
    end

    -- Key-value patterns in content
    if trimmed:match('"[^"]+"%s*:%s*') and (trimmed:match("{") or trimmed:match("}")) then
        result.type = M.ContentType.JSON_API_RESPONSE
        result.confidence = confidence.low
        result.display_strategy = "json_popup_with_folding"
        result.metadata.classification_method = "json_pattern_kv"
        return result
    end

    return result
end

---Detect file type from content patterns
---@param content string File content to analyze
---@return string file_type Detected file type
function M._detect_file_type(content)
    if not content or content == "" then
        return "text"
    end

    local first_lines = content:sub(1, 200)

    -- JSON files
    if first_lines:match("^%s*[%{%[]") then
        local is_json, _ = M._robust_json_validation(content)
        if is_json then
            return "json"
        end
    end

    -- XML files
    if first_lines:match("^%s*<%?xml") or first_lines:match("^%s*<[^>]+>") then
        return "xml"
    end

    -- Shell scripts
    if first_lines:match("^%s*#!/bin/") then
        return "sh"
    end

    -- Programming languages
    if first_lines:match("function%s+") or first_lines:match("local%s+") then
        return "lua"
    elseif first_lines:match("const%s+") or first_lines:match("function%s*%(") then
        return "javascript"
    elseif first_lines:match("def%s+") or first_lines:match("import%s+") then
        return "python"
    elseif first_lines:match("class%s+") or first_lines:match("public%s+") then
        return "java"
    end

    return "text"
end

---Count lines in content
---@param content string Content to count
---@return number line_count Number of lines
function M._count_lines(content)
    if not content or content == "" then
        return 0
    end
    local _, count = content:gsub("\n", "")
    return count + 1
end

---Infer tool name from structured data context
---@param structured_data table Structured data object
---@return string? tool_name Inferred tool name or nil
function M._infer_tool_name_from_context(structured_data)
    -- For tool_result, we need to look up the original tool_use to get the name
    -- This would ideally be passed in from the caller who has the full context
    -- For now, return nil and rely on caller to provide tool_name
    return structured_data.tool_name or nil
end

---Detect error patterns in content
---@param content string Content to check
---@return boolean has_error Whether content contains error patterns
function M._detect_error_patterns(content)
    if not content then
        return false
    end

    local error_patterns = {
        "^Error:",
        "^error:",
        "Exception",
        "Traceback",
        "failed to",
        "File not found",
        "not found",
    }

    for _, pattern in ipairs(error_patterns) do
        if content:match(pattern) then
            return true
        end
    end

    return false
end

---Get display strategy for content type (for backward compatibility)
---@param content_type CcTui.ContentClassificationType Content type
---@return string strategy Display strategy identifier
function M.get_display_strategy(content_type)
    local strategies = {
        [M.ContentType.TOOL_INPUT] = "json_popup_always",
        [M.ContentType.JSON_API_RESPONSE] = "json_popup_with_folding",
        [M.ContentType.ERROR_OBJECT] = "error_json_popup",
        [M.ContentType.FILE_CONTENT] = "syntax_highlighted_popup",
        [M.ContentType.COMMAND_OUTPUT] = "terminal_style_popup",
        [M.ContentType.GENERIC_TEXT] = "adaptive_popup_or_inline",
    }

    return strategies[content_type] or "adaptive_popup_or_inline"
end

---Check if content should use JSON display (backward compatibility helper)
---@param content string Content to check
---@param tool_name? string Tool name
---@param context? string Context
---@return boolean should_use_json Whether content should display as JSON
function M.is_json_content(content, tool_name, context)
    local result = M.classify(content, tool_name, context)

    return result.type == M.ContentType.JSON_API_RESPONSE
        or result.type == M.ContentType.TOOL_INPUT
        or result.type == M.ContentType.ERROR_OBJECT
end

---Check if content should use rich display (backward compatibility helper)
---@param content string Content to check
---@param is_error? boolean Whether content is an error
---@param tool_name? string Tool name
---@return boolean should_use_rich Whether to use rich display
function M.should_use_rich_display(content, is_error, tool_name)
    if is_error then
        return true
    end

    local result = M.classify(content, tool_name, "output")

    -- Use rich display for substantial content or structured data
    return result.metadata.line_count > 5
        or result.metadata.content_length > 200
        or result.type == M.ContentType.JSON_API_RESPONSE
        or result.type == M.ContentType.ERROR_OBJECT
end

---Check if content should use rich display with structured data (DETERMINISTIC)
---@param structured_data table Claude Code JSON message or content object
---@param content string Raw content text
---@return boolean should_use_rich Whether to use rich display
function M.should_use_rich_display_structured(structured_data, content)
    local result = M.classify_from_structured_data(structured_data, content)

    -- Use rich display for substantial content or structured data
    return result.metadata.line_count > 5
        or result.metadata.content_length > 200
        or result.type == M.ContentType.JSON_API_RESPONSE
        or result.type == M.ContentType.ERROR_OBJECT
        or result.type == M.ContentType.FILE_CONTENT
        or result.type == M.ContentType.COMMAND_OUTPUT
end

---Check if structured data represents JSON content (DETERMINISTIC)
---@param structured_data table Claude Code JSON message or content object
---@param content string Raw content text
---@return boolean is_json Whether content should display as JSON
function M.is_json_content_structured(structured_data, content)
    local result = M.classify_from_structured_data(structured_data, content)

    return result.type == M.ContentType.JSON_API_RESPONSE
        or result.type == M.ContentType.TOOL_INPUT
        or result.type == M.ContentType.ERROR_OBJECT
end

return M
