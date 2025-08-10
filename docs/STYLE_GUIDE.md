# CC-TUI Style Guide

*Adopted from MCPHub.nvim's excellent code patterns*

## UI Component Guidelines

### NUI.nvim Usage
- **ALWAYS** use nui.nvim components as the foundation for UI elements
- **STUDY** MCPHub.nvim implementation patterns for UI excellence
- **CUSTOMIZE** nui components following MCPHub patterns when needed for enhanced UX

### MCPHub-Inspired Patterns
- **Tab bars**: Use NuiLine with custom highlighting (see MCPHub's `Text.create_tab_bar`)
- **List views**: Implement interactive lines with proper cursor tracking
- **Borders**: Use NUI borders with custom titles and styling
- **Text rendering**: Follow MCPHub's NuiLine patterns for rich text display
- **Keymaps**: Implement view-specific keymaps with clear action handlers

### Component Selection Priority
1. Use stock nui.nvim components when they meet requirements
2. Extend nui components with MCPHub patterns for enhanced functionality
3. Create custom components only when necessary, following MCPHub architecture

## Core Principles

- **Consistency over personal preference** - Follow established patterns religiously
- **Automated tooling over manual enforcement** - Let StyLua and luacheck handle formatting
- **Clear documentation over brevity** - Code should be self-documenting with proper annotations
- **Typed interfaces over implicit behavior** - Use LuaDoc annotations extensively

## Module Structure & Organization

### ✅ **GOOD: Standard Module Pattern**

```lua
---@brief [[
--- Core functionality for CC-TUI window management
--- Handles UI lifecycle, state coordination, and user interactions
---@brief ]]
local log = require("cc-tui.utils.log")
local state = require("cc-tui.state")
local Popup = require("nui.popup")

---@class CcTui.Main
---@field private _ui_components table<string, table> Active UI component references
local M = {}

---Initialize the main CC-TUI interface
---@param scope string Logging scope identifier
---@return boolean success True if initialization succeeded
---@return string? error Error message if initialization failed
function M.enable(scope)
    -- Implementation
end

return M
```

### ❌ **BAD: Inconsistent Module Style**

```lua
-- Missing documentation
local main = {}

function main.enable(scope)  -- No type annotations
    -- Implementation without error handling
end
```

## Documentation Standards

### **LuaDoc Annotations** (Mandatory)

- **Classes**: `---@class ClassName`
- **Functions**: `---@param name type description` and `---@return type description`  
- **Fields**: `---@field name type description`
- **Brief Descriptions**: Use `---@brief [[` multi-line blocks for complex descriptions

### ✅ **GOOD: Complete Documentation**

```lua
---@brief [[
--- Manages UI component lifecycle and state persistence
--- Provides centralized storage for component references with cleanup
---@brief ]]

---@class CcTui.State
---@field enabled boolean Whether CC-TUI is currently active
---@field ui_component table|nil Currently active UI component reference
local State = {}

---Sets the UI component reference with validation
---@param component table UI component instance (must have :unmount method)
---@return boolean success True if component was stored successfully
function State:set_ui_component(component)
    vim.validate({
        component = { component, "table" }
    })
    
    -- Cleanup existing component first
    if self.ui_component and self.ui_component.unmount then
        self.ui_component:unmount()
    end
    
    self.ui_component = component
    return true
end
```

## Method Calling & State Management

### ✅ **GOOD: Consistent Colon Syntax**

```lua
-- Always use colon syntax for object methods
state:set_enabled()
state:get_ui_component()
popup:mount()
```

### ✅ **GOOD: Validation Patterns**

```lua
function M.setup(opts)
    vim.validate({
        opts = { opts, "table", true },  -- optional table
        opts.size = { opts and opts.size, "table", true },
        opts.border = { opts and opts.border, "table", true },
    })
end
```

## Error Handling & Returns

### ✅ **GOOD: Structured Error Returns**

```lua
---@return boolean success
---@return string? error
function M.mount_window(opts)
    local success, err = pcall(function()
        popup:mount()
    end)
    
    if not success then
        return false, "Failed to mount CC-TUI window: " .. tostring(err)
    end
    
    return true, nil
end
```

### ✅ **GOOD: Null Safety Patterns**

```lua
local component = state:get_ui_component()
if component and component.unmount then
    component:unmount()
    state:set_ui_component(nil)
end
```

## Import Organization

### ✅ **GOOD: Sorted Requires (automatic with StyLua)**

```lua
local Job = require("plenary.job")          -- External dependencies first
local log = require("cc-tui.utils.log")     -- Internal utilities
local state = require("cc-tui.state")      -- Internal modules
local Popup = require("nui.popup")         -- UI components last
```

## Configuration & Constants

### ✅ **GOOD: Typed Configuration**

```lua
---@class CcTui.Config
---@field size {width: string|number, height: string|number}
---@field border {style: string, text: {top: string, top_align: string}}
---@field enter boolean Whether to enter the window on mount
---@field focusable boolean Whether window can receive focus
local default_config = {
    size = {
        width = "80%",
        height = "60%",
    },
    border = {
        style = "rounded",
        text = {
            top = " CC-TUI Main ",
            top_align = "center",
        },
    },
    enter = true,
    focusable = true,
}
```

## UI Component Patterns

### ✅ **GOOD: Component Lifecycle Management**

```lua
---@class CcTui.WindowManager
---@field private components table<string, table>
local WindowManager = {}

function WindowManager:create_window(opts)
    local popup = Popup(vim.tbl_deep_extend("force", default_config, opts or {}))
    
    -- Store reference before mounting
    self.components.main = popup
    
    local success, err = pcall(function()
        popup:mount()
    end)
    
    if not success then
        self.components.main = nil
        return false, "Mount failed: " .. err
    end
    
    return true, nil
end

function WindowManager:cleanup()
    for name, component in pairs(self.components) do
        if component and component.unmount then
            component:unmount()
        end
        self.components[name] = nil
    end
end
```

## Anti-Patterns to Avoid

### ❌ **Missing Type Annotations**

```lua
function bad_function(param)  -- No @param annotation
    return param  -- No @return annotation
end
```

### ❌ **Inconsistent Method Calls**

```lua
state.set_enabled(state)  -- Don't mix dot and colon syntax
```

### ❌ **Missing Validation**

```lua
function M.setup(opts)
    -- Direct usage without validation - dangerous!
    local width = opts.size.width
end
```

### ❌ **Poor Error Handling**

```lua
popup:mount()  -- Could throw error without handling
```

## Code Formatting Rules

- **Column Width**: 120 characters (matches MCPHub)
- **Sort Requires**: Automatic with StyLua configuration  
- **Line Endings**: Unix style
- **Indentation**: 4 spaces
- **Quote Style**: Auto-prefer double quotes

## Commands for Style Compliance

```bash
make style-fix     # Auto-fix formatting and sort requires
make style-check   # Verify style compliance (for CI)
```

## Summary Checklist

Before submitting code, ensure:

- [ ] All functions have `---@param` and `---@return` annotations
- [ ] Public APIs use `vim.validate()` for parameter checking  
- [ ] Methods use colon syntax: `object:method()`
- [ ] Error returns follow `success, error` pattern
- [ ] UI components are properly stored and cleaned up
- [ ] `make style-fix` has been run
- [ ] `make style-check` passes without errors
