---@brief [[
--- Global state management for CC-TUI plugin
--- Handles enabled/disabled state and UI component lifecycle
---@brief ]]
local log = require("cc-tui.utils.log")

---@class CcTui.State
---@field enabled boolean Whether CC-TUI is currently active
---@field ui_component table|nil Currently active UI component reference
local state = { enabled = false, ui_component = nil }

---Sets the state to its original value.
---@return nil
---@private
function state:init()
    self.enabled = false
    self.ui_component = nil
end

---Saves the state in the global _G.CcTui.state object.
---@return nil
---@private
function state:save()
    log.debug("state.save", "saving state globally to _G.CcTui.state")

    _G.CcTui.state = self
end

--- Sets the global state as enabled.
---@return nil
---@private
function state:set_enabled()
    self.enabled = true
end

--- Sets the global state as disabled.
---@return nil
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

---Sets the UI component reference with validation.
---@param component table UI component instance (must have :unmount method)
---@return boolean success True if component was stored successfully
---@private
function state:set_ui_component(component)
    vim.validate({
        component = { component, "table", true }, -- Allow nil to clear
    })

    -- Cleanup existing component first
    if self.ui_component and self.ui_component.unmount then
        self.ui_component:unmount()
    end

    self.ui_component = component
    return true
end

return state
