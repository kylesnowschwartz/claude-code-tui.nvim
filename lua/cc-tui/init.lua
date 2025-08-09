local config = require("cc-tui.config")
local main = require("cc-tui.main")

local CcTui = {}

--- Toggle the plugin by calling the `enable`/`disable` methods respectively.
function CcTui.toggle()
    if _G.CcTui.config == nil then
        _G.CcTui.config = config.options
    end

    main.toggle("public_api_toggle")
end

--- Initializes the plugin, sets event listeners and internal state.
function CcTui.enable(scope)
    if _G.CcTui.config == nil then
        _G.CcTui.config = config.options
    end

    main.toggle(scope or "public_api_enable")
end

--- Disables the plugin, clear highlight groups and autocmds, closes side buffers and resets the internal state.
function CcTui.disable()
    main.toggle("public_api_disable")
end

-- setup CcTui options and merge them with user provided ones.
function CcTui.setup(opts)
    _G.CcTui.config = config.setup(opts)
end

_G.CcTui = CcTui

return _G.CcTui
