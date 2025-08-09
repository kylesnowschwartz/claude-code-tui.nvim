local log = require("cc-tui.util.log")

local CcTui = {}

--- CcTui configuration with its default values.
---
---@type table
--- Default values:
---@eval return MiniDoc.afterlines_to_code(MiniDoc.current.eval_section)
CcTui.options = {
    -- Prints useful logs about what event are triggered, and reasons actions are executed.
    debug = false,
}

---@private
local defaults = vim.deepcopy(CcTui.options)

--- Defaults CcTui options by merging user provided options with the default plugin values.
---
---@param options table Module config table. See |CcTui.options|.
---
---@private
function CcTui.defaults(options)
    CcTui.options =
        vim.deepcopy(vim.tbl_deep_extend("keep", options or {}, defaults or {}))

    -- let your user know that they provided a wrong value, this is reported when your plugin is executed.
    assert(
        type(CcTui.options.debug) == "boolean",
        "`debug` must be a boolean (`true` or `false`)."
    )

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
