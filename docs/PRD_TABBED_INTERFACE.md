# PRD: CC-TUI Tabbed Interface Redesign

## Overview

Transform CC-TUI from separate commands (`:CcTui` and `:CcTuiBrowse`) into a unified tabbed interface following MCPHub's UX patterns. This consolidates functionality into a single window with tab-based navigation and consistent keyboard shortcuts.

## Current State Analysis

### Current Commands
- `:CcTui` - Opens tree view of current conversation
- `:CcTuiBrowse` - Opens conversation browser in separate window
- Separate UI instances with different lifecycles
- Inconsistent user experience between views

### Current Architecture
- `lua/cc-tui/main.lua` - Primary toggle/enable logic
- `lua/cc-tui/ui/conversation_browser.lua` - Browser UI component
- Plugin lifecycle managed through `main.toggle()` and `main.browse()`
- State management via `cc-tui.state` module

## Proposed Solution

### Tab Structure
Following MCPHub's `H Hub M Marketplace C Config L Logs ? Help` pattern:

| Key | Tab | Description |
|-----|-----|-------------|
| `C` | **Current** | Tree view of current conversation (replaces `:CcTui`) |
| `B` | **Browse** | Conversation browser (replaces `:CcTuiBrowse`) |
| `L` | **Logs** | Debug/activity logs for CC-TUI |
| `?` | **Help** | Keybindings and usage instructions |

### Unified Entry Point
- **Single Command**: `:CcTui` opens tabbed interface
- **Remove Command**: `:CcTuiBrowse` deprecated
- **Default Tab**: Opens to `C` (Current) tab by default
- **State Persistence**: Remember last active tab across sessions

## Technical Implementation

### Architecture Changes

#### 1. New Tabbed UI Manager (`lua/cc-tui/ui/tabbed_manager.lua`)
```lua
---@class CcTui.TabbedManager
---@field current_tab string Currently active tab
---@field tabs table<string, CcTui.TabConfig> Tab configuration
---@field window number Main window handle
---@field buffer number Main buffer handle
```

Key responsibilities:
- Tab navigation and rendering
- Tab content switching
- Keyboard shortcut handling
- Window lifecycle management

#### 2. Tab Content Views
- `lua/cc-tui/ui/views/current.lua` - Current conversation tree
- `lua/cc-tui/ui/views/browse.lua` - Conversation browser
- `lua/cc-tui/ui/views/logs.lua` - Debug/activity logs
- `lua/cc-tui/ui/views/help.lua` - Help and documentation

#### 3. MCPHub-Inspired Tab Bar
Using NuiLine patterns from MCPHub:
```lua
local tabs = {
    { key = "C", label = "Current", view = "current", selected = true },
    { key = "B", label = "Browse", view = "browse", selected = false },
    { key = "L", label = "Logs", view = "logs", selected = false },
    { key = "?", label = "Help", view = "help", selected = false },
}
```

### UI Components

#### Tab Bar Rendering
- Centered horizontal tab bar at top of window
- Active tab highlighted with `button_active` highlight group
- Inactive tabs with `button_inactive` highlight group
- Keyboard shortcuts clearly visible: `C Current  B Browse  L Logs  ? Help`

#### Content Area
- Full window space below tab bar
- Tab-specific content rendered based on active tab
- Smooth transition between tabs (no window reconstruction)

#### Status Information
- Current tab indicator in status line
- Tab-specific status information (e.g., conversation count, log level)

### Keyboard Navigation

#### Primary Tab Shortcuts
- `C` - Switch to Current tab
- `B` - Switch to Browse tab  
- `L` - Switch to Logs tab
- `?` - Switch to Help tab

#### Secondary Navigation
- `Tab` / `Shift+Tab` - Cycle through tabs
- `q` - Close CC-TUI window
- `R` - Refresh current tab content

#### Tab-Specific Shortcuts
Each tab maintains its own key mappings for tab-specific functionality.

## User Experience

### Workflow Improvements

#### Before (Current State)
1. User runs `:CcTui` to see current conversation
2. Realizes they need to browse other conversations
3. Closes current window with `q`
4. Runs `:CcTuiBrowse` to open browser
5. Separate window management and state

#### After (Tabbed Interface)
1. User runs `:CcTui` (opens to Current tab)
2. Presses `B` to switch to Browse tab instantly
3. Presses `C` to switch back to Current tab
4. Single unified interface with shared state

### Visual Consistency
- Follows MCPHub's established UX patterns
- Consistent styling and highlight groups
- Professional tabbed interface appearance
- Clear visual hierarchy with tab bar and content area

## Implementation Plan

### Phase 1: Core Tabbed Infrastructure
1. Create `TabbedManager` class with basic tab switching
2. Implement MCPHub-style tab bar rendering
3. Set up keyboard shortcut system
4. Create base tab content interface

### Phase 2: Tab Content Migration  
1. Migrate current tree view to `current.lua` tab
2. Migrate conversation browser to `browse.lua` tab
3. Create `logs.lua` tab with debug output
4. Create `help.lua` tab with documentation

### Phase 3: Integration & Polish
1. Update `main.lua` to use tabbed interface
2. Deprecate `:CcTuiBrowse` command
3. Add state persistence for active tab
4. Comprehensive testing and refinement

### Phase 4: Documentation & Migration
1. Update README with new usage patterns
2. Create migration guide for existing users
3. Add examples and screenshots
4. Update plugin help documentation

## Success Metrics

### User Experience
- **Reduced cognitive load**: Single interface vs. multiple commands
- **Faster navigation**: Tab switching vs. command re-execution  
- **Consistent UX**: Follows established MCPHub patterns
- **Enhanced discoverability**: Tab bar shows all available views

### Technical Quality
- **Maintainable architecture**: Clear separation of tab concerns
- **Performance**: Smooth tab switching without reconstruction
- **Code reuse**: Leverage existing conversation browser logic
- **Testing coverage**: Comprehensive test suite for tabbed interface

## Future Enhancements

### Additional Tabs (Future Iterations)
- **S** - **Settings** tab for CC-TUI configuration
- **H** - **History** tab for recent conversation activity
- **F** - **Favorites** tab for bookmarked conversations

### Advanced Features
- **Tab badges**: Show count indicators (e.g., unread logs)
- **Tab context menus**: Right-click for tab-specific options
- **Workspace tabs**: Project-specific conversation views
- **Split view mode**: Show multiple tabs simultaneously

## Risk Mitigation

### Breaking Changes
- **Command deprecation**: Gradual phase-out of `:CcTuiBrowse`
- **User communication**: Clear migration documentation
- **Backward compatibility**: Support legacy commands during transition

### Implementation Risks
- **UI complexity**: Follow MCPHub patterns to reduce risk
- **State management**: Careful tab state isolation
- **Performance**: Lazy-load tab content as needed
- **Testing**: Comprehensive test coverage for all tab scenarios

## References

- **MCPHub Screenshot**: `docs/mcphub-ui.png` - Reference implementation
- **MCPHub Tab Bar**: `/Users/kyle/Code/mcphub.nvim/lua/mcphub/utils/text.lua:create_tab_bar()`
- **MCPHub UI Manager**: `/Users/kyle/Code/mcphub.nvim/lua/mcphub/ui/init.lua`
- **CC-TUI Style Guide**: `docs/STYLE_GUIDE.md` - Implementation standards

---

*This PRD provides the foundation for creating a unified, professional tabbed interface that enhances user experience while maintaining architectural quality.*
