---@brief [[
--- Display Strategy Service
--- Extracted from content_classifier.lua for display logic separation
--- Handles display strategy recommendations based on content type
---@brief ]]

local Config = require("cc-tui.utils.content_classifier_config")

---@class CcTui.Utils.DisplayStrategy
local M = {}

---Get recommended display strategy for content type
---@param content_type CcTui.ContentClassificationType Content type
---@return string display_strategy Strategy name
function M.get_display_strategy(content_type)
    local config = Config.get_config()

    -- Map content types to display strategies
    local strategy_map = {
        [Config.ContentType.TOOL_INPUT] = "json_popup_always",
        [Config.ContentType.JSON_API_RESPONSE] = config.display.json_folding_for_mcp and "json_popup_with_folding"
            or "json_popup",
        [Config.ContentType.ERROR_OBJECT] = config.display.error_highlighting and "error_popup_highlighted"
            or "text_popup",
        [Config.ContentType.FILE_CONTENT] = "syntax_highlighted_popup", -- File content display
        [Config.ContentType.COMMAND_OUTPUT] = config.display.terminal_style_for_bash and "terminal_style_popup"
            or "text_popup",
        [Config.ContentType.ERROR_CONTENT] = config.display.error_highlighting and "error_popup_highlighted"
            or "text_popup",
        [Config.ContentType.GENERIC_TEXT] = "inline_or_popup", -- Size-based decision
    }

    return strategy_map[content_type] or "text_popup"
end

---Check if content should use rich display based on size and type
---@param content string Content to analyze
---@param is_error? boolean Whether content represents an error
---@param tool_name? string Tool name for context
---@return boolean should_use_rich True if rich display recommended
function M.should_use_rich_display(content, is_error, tool_name)
    local config = Config.get_config()

    -- Always use rich display for errors if enabled
    if is_error and config.display.error_highlighting then
        return true
    end

    -- Always use rich display for specific tools
    if tool_name and config.display.force_popup_for_tools then
        local force_popup_tools = {
            "Write",
            "Edit",
            "Read", -- File operations
            "mcp__", -- All MCP tools (prefix match)
        }

        for _, tool in ipairs(force_popup_tools) do
            if tool_name:find(tool, 1, true) then
                return true
            end
        end
    end

    -- Size-based decision
    local line_count = M.count_lines(content)
    local char_count = #content

    return line_count > config.thresholds.rich_display_lines or char_count > config.thresholds.rich_display_chars
end

---Count lines in content
---@param content string Content to analyze
---@return number line_count Number of lines
function M.count_lines(content)
    if not content or content == "" then
        return 0
    end

    local lines = 1
    for _ in content:gmatch("\n") do
        lines = lines + 1
    end

    return lines
end

---Check if content should use rich display based on structured data
---@param structured_data table Structured message data
---@param content string Content text
---@return boolean should_use_rich True if rich display recommended
function M.should_use_rich_display_structured(structured_data, content)
    local config = Config.get_config()

    -- Tool inputs always get rich display if configured
    if structured_data.type == "tool_use" and config.display.force_popup_for_tools then
        return true
    end

    -- Check message content for tool_use items
    if structured_data.message and structured_data.message.content then
        local message_content = structured_data.message.content

        -- Handle array content format
        if type(message_content) == "table" and message_content[1] then
            for _, content_item in ipairs(message_content) do
                if content_item and content_item.type == "tool_use" and config.display.force_popup_for_tools then
                    return true
                end
            end
        end
    end

    -- Fallback to content-based analysis
    return M.should_use_rich_display(content, false, nil)
end

return M
