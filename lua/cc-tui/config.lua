local log = require("cc-tui.utils.log")

local CcTui = {}

---Check if we're in testing mode (SECURITY: prevents loading real user data)
---@return boolean is_testing True if testing mode is active
function CcTui.is_testing_mode()
    -- Check multiple sources for testing mode in order of reliability
    return vim.env.CC_TUI_TESTING == "1" -- Environment variable (most reliable)
        or vim.env.TESTING == "1" -- Generic testing environment
        or package.loaded["mini.test"] ~= nil -- MiniTest is loaded
        or _G.CcTui_Testing == true -- Global flag set in tests
        or (_G.CcTui and _G.CcTui.options and _G.CcTui.options.testing_mode == true) -- Config option
end

--- CcTui configuration with its default values.
---
---@type table
--- Default values:
---@eval return MiniDoc.afterlines_to_code(MiniDoc.current.eval_section)
CcTui.options = {
    -- Prints useful logs about what event are triggered, and reasons actions are executed.
    debug = false,

    -- SECURITY: Testing mode prevents loading real user conversation data
    testing_mode = false,

    -- Content classification and display thresholds
    content = {
        -- Thresholds for determining display strategies
        thresholds = {
            -- Line count thresholds
            rich_display_lines = 5, -- Use rich display for content > 5 lines
            popup_lines = 3, -- Use popup for content > 3 lines
            inline_max_lines = 2, -- Keep inline for content <= 2 lines

            -- Character count thresholds
            rich_display_chars = 200, -- Use rich display for content > 200 chars
            popup_chars = 100, -- Use popup for content > 100 chars
            inline_max_chars = 80, -- Keep inline for content <= 80 chars

            -- Performance thresholds
            classification_timeout_ms = 10, -- Max time for content classification
            json_parse_max_size = 1024 * 1024, -- Max JSON size to attempt parsing (1MB)
        },

        -- Display strategy preferences
        display_strategies = {
            tool_input = "json_popup_always",
            json_api = "json_popup_with_folding",
            error_object = "error_json_popup",
            file_content = "syntax_highlighted_popup",
            command_output = "terminal_style_popup",
            generic_text = "adaptive_popup_or_inline",
        },

        -- Content type classification settings
        classification = {
            -- Enable robust JSON validation using vim.fn.json_decode
            use_robust_json_validation = true,

            -- Enable tool-aware context classification
            enable_tool_context = true,

            -- Enable MCP response detection
            enable_mcp_detection = true,

            -- Content type confidence thresholds
            confidence = {
                high = 0.9, -- High confidence classification
                medium = 0.7, -- Medium confidence classification
                low = 0.5, -- Low confidence classification
                fallback = 0.1, -- Fallback classification
            },
        },
    },
}

---@private
local defaults = vim.deepcopy(CcTui.options)

--- Defaults CcTui options by merging user provided options with the default plugin values.
---
---@param options table Module config table. See |CcTui.options|.
---
---@private
function CcTui.defaults(options)
    CcTui.options = vim.deepcopy(vim.tbl_deep_extend("keep", options or {}, defaults or {}))

    -- let your user know that they provided a wrong value, this is reported when your plugin is executed.
    assert(type(CcTui.options.debug) == "boolean", "`debug` must be a boolean (`true` or `false`).")

    return CcTui.options
end

--- Define your cc-tui setup.
---
---@param options table Module config table. See |CcTui.options|.
---
---@usage `require("cc-tui").setup()` (add `{}` with your |CcTui.options| table)
function CcTui.setup(options)
    CcTui.options = CcTui.defaults(options or {})

    log.warn_deprecation(CcTui.options)

    return CcTui.options
end

return CcTui
