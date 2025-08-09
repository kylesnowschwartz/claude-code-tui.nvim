local log = require("cc-tui.util.log")

local state = { enabled = false, ui_component = nil }

---Sets the state to its original value.
---
---@private
function state:init()
    self.enabled = false
    self.ui_component = nil
end

---Saves the state in the global _G.CcTui.state object.
---
---@private
function state:save()
    log.debug("state.save", "saving state globally to _G.CcTui.state")

    _G.CcTui.state = self
end

--- Sets the global state as enabled.
---
---@private
function state:set_enabled()
    self.enabled = true
end

--- Sets the global state as disabled.
---
---@private
function state:set_disabled()
    self.enabled = false
end

---Whether the CcTui is enabled or not.
---
---@return boolean: the `enabled` state value.
---@private
function state:get_enabled()
    return self.enabled
end

---Gets the UI component reference.
---
---@return table|nil: the UI component instance.
---@private
function state:get_ui_component()
    return self.ui_component
end

---Sets the UI component reference.
---
---@param component table: the UI component instance.
---@private
function state:set_ui_component(component)
    self.ui_component = component
end

return state
