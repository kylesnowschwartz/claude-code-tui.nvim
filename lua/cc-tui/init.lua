local config = require("cc-tui.config")
local main = require("cc-tui.main")

local CcTui = {}

--- Toggle the tabbed interface (opens unified CC-TUI with C/B/L/? tabs)
function CcTui.toggle()
    if _G.CcTui.config == nil then
        _G.CcTui.config = config.options
    end

    main.toggle("public_api_toggle")
end

--- Enable the tabbed interface with optional default tab
---@param default_tab? string Default tab to open ("current", "browse", "logs", "help")
function CcTui.enable(default_tab)
    if _G.CcTui.config == nil then
        _G.CcTui.config = config.options
    end

    main.enable("public_api_enable", default_tab)
end

--- Disable the tabbed interface and clean up resources
function CcTui.disable()
    main.disable("public_api_disable")
end

--- Browse Claude conversations in the current project
---@deprecated Use CcTui.enable("browse") or simply :CcTui then press 'B' - this maintains backward compatibility
function CcTui.browse()
    if _G.CcTui.config == nil then
        _G.CcTui.config = config.options
    end

    main.browse()
end

-- setup CcTui options and merge them with user provided ones.
function CcTui.setup(opts)
    _G.CcTui.config = config.setup(opts)
end

_G.CcTui = CcTui

return _G.CcTui
