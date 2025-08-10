---@brief [[
--- JSON Detection and Validation Service
--- Extracted from content_classifier.lua for better separation of concerns
--- Handles JSON parsing, validation, and pattern detection
---@brief ]]

---@class CcTui.Utils.JsonDetector
local M = {}

---Robust JSON validation using protected calls
---@param content string Content to validate
---@return boolean is_json True if valid JSON
---@return table? parsed_data Parsed JSON data if valid
function M.robust_json_validation(content)
    -- Quick size check to avoid parsing very large content
    local Config = require("cc-tui.utils.content_classifier_config")
    local config = Config.get_config()
    if #content > config.thresholds.json_parse_max_size then
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

---Pattern-based JSON detection for edge cases
---@param content string Content to check
---@param base_result table Base classification result
---@param confidence number Current confidence level
---@return table updated_result Updated classification result
function M.pattern_based_json_detection(content, base_result, confidence)
    local json_patterns = {
        "^%s*{.*}%s*$", -- Object pattern
        "^%s*%[.*%]%s*$", -- Array pattern
        '"[^"]*":%s*[%[{]', -- Key-value with complex value
        '"[^"]*":%s*"[^"]*"', -- Simple key-value pairs
        '"type"%s*:%s*"[^"]*"', -- Common type field
    }

    local pattern_matches = 0
    for _, pattern in ipairs(json_patterns) do
        if content:match(pattern) then
            pattern_matches = pattern_matches + 1
        end
    end

    -- Higher pattern match count suggests JSON
    if pattern_matches >= 2 then
        base_result.confidence = math.min(1.0, confidence + 0.2)
        base_result.metadata.pattern_matches = pattern_matches
        base_result.metadata.json_indicators = true
    end

    return base_result
end

---Check if content contains JSON structure
---@param content string Content to analyze
---@return boolean is_json True if JSON detected
---@return table? parsed_data Parsed data if JSON is valid
function M.is_json_content(content)
    -- First try robust validation
    local is_valid, parsed = M.robust_json_validation(content)
    if is_valid then
        return true, parsed
    end

    -- Fall back to pattern detection for malformed JSON
    local dummy_result = { confidence = 0.0, metadata = {} }
    local pattern_result = M.pattern_based_json_detection(content, dummy_result, 0.5)

    return pattern_result.metadata.json_indicators or false, nil
end

return M
