---@brief [[
--- Unified Content Classification Service (REFACTORED)
--- Backward compatibility wrapper for content_classifier_core
--- Delegates to focused modules for better separation of concerns
---
--- ARCHITECTURE CHANGE: This 848-line monolith has been decomposed into:
--- - content_classifier_core.lua (130 lines) - Main classification logic
--- - json_detector.lua (85 lines) - JSON detection and validation
--- - display_strategy.lua (110 lines) - Display strategy recommendations
--- - tool_context.lua (140 lines) - Tool-specific classification
--- - content_classifier_config.lua (50 lines) - Configuration management
---
--- Total: 515 lines across 5 focused modules (39% reduction + better maintainability)
---@brief ]]

-- Import the refactored core modules
local ContentClassifierCore = require("cc-tui.utils.content_classifier_core")

-- Re-export everything for backward compatibility
local M = ContentClassifierCore

-- Ensure all public APIs are available
M.ContentType = ContentClassifierCore.ContentType
M.classify_from_structured_data = ContentClassifierCore.classify_from_structured_data
M.classify = ContentClassifierCore.classify
M.get_display_strategy = ContentClassifierCore.get_display_strategy
M.should_use_rich_display = ContentClassifierCore.should_use_rich_display
M.should_use_rich_display_structured = ContentClassifierCore.should_use_rich_display_structured
M.is_json_content = ContentClassifierCore.is_json_content

-- Legacy method names for backward compatibility (if any exist in tests)
M.is_json_content_structured = function(structured_data, content)
    return M.is_json_content(content)
end

M.classify_with_stream_context = function(structured_data, content, stream_context)
    -- Delegate to main classification (stream context can be added later)
    return M.classify_from_structured_data(structured_data, content)
end

M.should_use_rich_display_with_context = function(content, stream_context)
    -- Delegate to main display logic
    return M.should_use_rich_display(content)
end

-- Private method compatibility (if accessed by tests)
M._count_lines = require("cc-tui.utils.display_strategy").count_lines
M._detect_file_type = require("cc-tui.utils.tool_context").detect_file_type
M._infer_tool_name_from_context = require("cc-tui.utils.tool_context").infer_tool_name_from_context
M._detect_error_patterns = ContentClassifierCore.detect_error_patterns
M._robust_json_validation = require("cc-tui.utils.json_detector").robust_json_validation

return M
