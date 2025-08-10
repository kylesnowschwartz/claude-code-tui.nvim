---@brief [[
--- Content Classifier Configuration
--- Extracted from content_classifier.lua for better configuration management
--- Provides centralized configuration access and defaults
---@brief ]]

---@class CcTui.Utils.ContentClassifierConfig
local M = {}

---Get configuration values (centralized in config.lua as per plan)
---@return table config Configuration values
function M.get_config()
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
            enable_stream_classification = true,
            confidence_threshold = 0.7,
        },
        display = {
            force_popup_for_tools = true,
            terminal_style_for_bash = true,
            json_folding_for_mcp = true,
            error_highlighting = true,
        },
        performance = {
            cache_classifications = true,
            lazy_load_large_content = true,
            async_classification = false, -- For future enhancement
        },
    }
end

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
    ERROR_CONTENT = "error_content", -- Error content from tools (Phase 2)

    -- Fallback
    GENERIC_TEXT = "generic_text", -- Plain text content
}

return M
