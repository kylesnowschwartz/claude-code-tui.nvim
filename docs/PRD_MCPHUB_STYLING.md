# PRD: MCPHub-Style Professional Interface Upgrade

## Overview

Transform CC-TUI's current interface to match MCPHub's professional, polished look and feel. This upgrade will enhance the user experience through consistent spacing, professional typography, proper highlighting, and sophisticated visual hierarchy. docs/mcphub-ui.png

## Current State Analysis

**Current CC-TUI Interface Issues:**

- Basic tab bar without proper spacing and highlighting
- Inconsistent padding and margins throughout views
- Lack of visual hierarchy and professional polish
- Missing dividers and section separators
- Simple text rendering without proper highlighting
- No consistent spacing patterns

**MCPHub Interface Strengths:**

- Professional logo/title rendering with ASCII art
- Consistent horizontal padding (`HORIZONTAL_PADDING = 2`)
- Sophisticated highlight system with theme integration
- Proper visual hierarchy with dividers and separators
- Centered tab navigation with professional button styling
- Consistent spacing and alignment patterns

## Goals

1. **Visual Consistency**: Match MCPHub's professional appearance
2. **Spacing Standards**: Implement consistent padding, margins, and alignment
3. **Typography Hierarchy**: Clear visual distinction between headers, content, and metadata
4. **Professional Polish**: Dividers, separators, and sophisticated highlighting
5. **Theme Integration**: Proper colorscheme integration and highlight groups

## Technical Requirements

### 1. Spacing and Layout Standards

**Implement MCPHub's spacing system:**

- `HORIZONTAL_PADDING = 2` for all content
- Consistent line padding with `pad_line()` function
- Proper alignment with `align_text()` for centering
- Standardized divider lines with `divider()` function

**Layout Patterns:**

```lua
-- All content should use consistent padding
M.pad_line(content, highlight, padding)  -- Default padding = 2

-- Centered content alignment
M.align_text(text, width, "center", highlight)

-- Professional dividers between sections
M.divider(width, is_full)  -- Creates horizontal separator lines

-- Empty lines with consistent padding
M.empty_line()  -- Maintains padding consistency
```

### 2. Professional Tab Bar

**Upgrade current tab bar to match MCPHub style:**

**Current Implementation:**

```lua
-- Simple centered tabs without professional styling
local tab_text = string.format("%s %s", tab.key, tab.label)
tab_group:append(" " .. tab_text .. " ", is_selected and "CcTuiTabActive" or "CcTuiTabInactive")
```

**Target MCPHub Implementation:**

```lua
-- Professional button-style tabs with proper highlighting
function M.create_button(label, shortcut, selected)
    if selected then
        line:append(" " .. shortcut, M.highlights.header_btn_shortcut)
        line:append(" " .. label .. " ", M.highlights.header_btn)
    else
        line:append(" " .. shortcut, M.highlights.header_shortcut)
        line:append(" " .. label .. " ", M.highlights.header)
    end
end
```

### 3. Professional Header System

**Add CC-TUI ASCII logo similar to MCPHub:**

```
╔═╗╔═╗  ╔╦╗╦ ╦╦
║  ║    ║ ║║ ║║
╚═╝╚═╝  ╩ ╚╝╚═╝╩
```

**Header Structure:**

1. ASCII logo (centered)
2. Tab navigation bar (centered)
3. Divider line
4. Content area with proper padding

### 4. Comprehensive Highlight System

**Implement MCPHub's highlight groups:**

**Essential Highlights:**

- `CcTuiTitle` - Headers and important text
- `CcTuiHeader` - Section headers
- `CcTuiHeaderBtn` - Active tab background
- `CcTuiHeaderBtnShortcut` - Active tab shortcut
- `CcTuiHeaderShortcut` - Inactive tab shortcut
- `CcTuiMuted` - Dividers, metadata, secondary text
- `CcTuiSuccess` - Success states and positive indicators
- `CcTuiInfo` - Information and primary content
- `CcTuiWarn` - Warnings and caution states
- `CcTuiError` - Errors and problem indicators

**Theme Integration:**

```lua
-- Auto-adapt to user's colorscheme
local normal_bg = get_color("Normal", "bg", "#1a1b26")
local title_color = get_color("Title", "fg", "#c792ea")
local error_color = get_color("DiagnosticError", "fg", "#f44747")
```

### 5. Content Rendering Upgrades

**Professional Content Layout:**

**Current View Structure:**

```
[Basic Tab Bar]
[Raw Content]
```

**Target MCPHub Structure:**

```
╔═╗╔═╗  ╔╦╗╦ ╦╦    <- ASCII Logo (centered)
║  ║    ║ ║║ ║║
╚═╝╚═╝  ╩ ╚═╝╚═╝╩

 C Current  B Browse  L Logs  ? Help    <- Professional Tab Bar (centered)
─────────────────────────────────────   <- Divider Line
                                        <- Consistent Padding
  📁 Browse Conversations ~ Project     <- Section Header with Icon
                                        <- Empty Line
    1. ● conversation title...          <- Padded Content List
    2. ○ another conversation...        <- Consistent Indentation
    3. ● third conversation...
                                        <- Empty Line
  [j/k] Navigate [Enter] Open [r] Refresh  <- Action Bar
```

### 6. View-Specific Improvements

**Current View (Tree Display):**

- Professional tree indicators (`●` `○` `▶` `▼`)
- Proper indentation with consistent spacing
- Color-coded message types and statuses
- Metadata display with muted highlights

**Browse View (Conversation List):**

- Professional list formatting with icons
- Truncated titles with ellipsis handling
- Status indicators and metadata
- Consistent item spacing

**Logs View (Debug Display):**

- Color-coded log levels with badges
- Timestamp formatting with muted highlight
- Module names with info highlight
- Proper message truncation

**Help View (Documentation):**

- Section headers with icons
- Organized keyboard shortcut tables
- Professional formatting for instructions
- Clear visual hierarchy

## Implementation Plan

### Phase 1: Core Infrastructure (Priority: Critical)

1. **Create text utility module** (`lua/cc-tui/utils/text.lua`)

   - Implement spacing constants and helper functions
   - Add `pad_line()`, `align_text()`, `divider()`, `empty_line()`
   - Create professional button rendering

2. **Implement comprehensive highlight system** (`lua/cc-tui/utils/highlights.lua`)

   - Define all highlight groups with theme integration
   - Auto-adapt colors from user's colorscheme
   - Handle colorscheme change events

3. **Create ASCII logo and header system**
   - Design CC-TUI ASCII logo
   - Implement centered header rendering
   - Professional tab bar with button styling

### Phase 2: View Upgrades (Priority: High)

1. **Upgrade TabbedManager**

   - Replace current tab bar with professional button system
   - Add logo header and divider lines
   - Implement consistent content padding

2. **Upgrade BaseView helpers**

   - Replace basic helpers with professional text utilities
   - Add icon support and visual indicators
   - Implement proper spacing patterns

3. **Upgrade individual views**
   - Current: Professional tree display with indicators
   - Browse: List formatting with status icons
   - Logs: Color-coded entries with badges
   - Help: Organized documentation layout

### Phase 3: Polish and Refinement (Priority: Medium)

1. **Advanced features**

   - JSON syntax highlighting for debug content
   - Markdown rendering for documentation
   - Enhanced visual indicators and icons

2. **Performance optimization**
   - Efficient rendering with minimal redraws
   - Cached highlight group lookups
   - Optimized text processing

### Phase 4: Testing and Validation (Priority: Medium)

1. **Theme compatibility testing**

   - Test with popular colorschemes
   - Validate highlight group fallbacks
   - Ensure consistent appearance

2. **Layout testing**
   - Test with different terminal sizes
   - Validate responsive behavior
   - Check content truncation handling

## Success Metrics

**Visual Quality:**

- Interface matches MCPHub's professional appearance
- Consistent spacing and alignment throughout
- Proper visual hierarchy with clear sections

**User Experience:**

- Enhanced readability with proper highlighting
- Intuitive navigation with professional tab styling
- Clear information architecture with organized content

**Technical Excellence:**

- Theme integration works across colorschemes
- Responsive layout adapts to terminal sizes
- Efficient rendering with smooth performance

## Risk Mitigation

**Compatibility Risks:**

- Maintain backward compatibility with existing functionality
- Graceful degradation for terminal limitations
- Fallback colors for unsupported themes

**Performance Risks:**

- Profile rendering performance with large datasets
- Optimize text processing for complex layouts
- Cache expensive operations like highlight lookups

**Maintenance Risks:**

- Document new utility functions and patterns
- Establish clear guidelines for future view development
- Create examples and templates for consistency

## Future Considerations

**Advanced Features:**

- Custom themes and color customization
- Animation support for state transitions
- Enhanced accessibility features

**Integration Opportunities:**

- Share text utilities with other Neovim plugins
- Contribute improvements back to MCPHub project
- Establish design system for ecosystem consistency

---

_This PRD establishes the foundation for transforming CC-TUI into a professional, polished interface that rivals MCPHub's sophisticated appearance while maintaining excellent functionality and user experience._
