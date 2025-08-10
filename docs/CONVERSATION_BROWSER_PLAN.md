# Claude Conversation Browser Implementation Plan

## Overview
Transform cc-tui.nvim from single-conversation viewer to multi-conversation browser with tabbed interface for exploring Claude project history.

## Architecture Components

### 1. Project Discovery Service
**File**: `lua/cc-tui/services/project_discovery.lua`
```lua
-- Core functions:
-- get_project_name(cwd) -> "project-name" 
-- get_project_path(project_name) -> "~/.claude/projects/project-name"
-- list_conversations(project_path) -> {files, metadata}
```

### 2. Conversation Provider  
**File**: `lua/cc-tui/providers/conversation.lua`
```lua
-- Extends DataProvider to load conversation JSONL files
-- Provides caching and lazy loading
-- Integrates with existing parser/tree builder
```

### 3. Tab Manager
**File**: `lua/cc-tui/ui/tab_manager.lua`
```lua
-- Manages tab state and switching
-- Creates tab headers with conversation metadata
-- Handles keyboard navigation between tabs
```

### 4. Conversation Browser UI
**File**: `lua/cc-tui/ui/conversation_browser.lua`
```lua
-- Orchestrates tabbed interface
-- Coordinates tab selection with tree display
-- Manages overall browser layout
```

## Implementation Phases

### Phase 1: Foundation (Day 1)
- [x] Project discovery service
- [ ] Conversation file listing
- [ ] Basic conversation provider

### Phase 2: Tab Interface (Day 2)  
- [ ] Tab manager component
- [ ] Tab header rendering
- [ ] Tab switching logic

### Phase 3: Integration (Day 3)
- [ ] Browser UI orchestration
- [ ] Connect tabs to tree view
- [ ] User commands and keymaps

## User Experience Flow

1. **Launch Browser**: `:CcTuiBrowse` opens conversation browser
2. **Project Detection**: Automatically finds current project's conversations
3. **Tab Display**: Shows tabs for each conversation (with timestamps/titles)
4. **Navigation**: 
   - `gt`/`gT` - next/previous tab
   - `1gt` - go to tab 1
   - `<leader>cb` - toggle browser
5. **Tree Display**: Selected conversation renders in existing tree view

## Technical Decisions

### Tab Implementation
Using nui.nvim Split with custom header rendering (not Tab component) for better control:
```lua
-- Split layout:
-- [Tab1] [Tab2] [Tab3] ... (header line)
-- -------------------------
-- Tree content for selected tab
```

### Data Loading Strategy
- **Lazy Loading**: Conversations load only when tab selected
- **Caching**: Keep N most recent conversations in memory
- **Metadata Preload**: Load conversation metadata (title, timestamp) upfront

### File Structure Discovery
```
~/.claude/projects/
├── project-name-1/
│   ├── conversation-{timestamp}.jsonl
│   ├── conversation-{timestamp}.jsonl
│   └── ...
└── project-name-2/
    └── ...
```

## Integration Points

### With Existing Code
- **Parser**: Reuse `parser.stream` for JSONL parsing
- **TreeBuilder**: Use existing `build_tree()` for conversation display
- **ContentClassifier**: Leverage for tool result formatting
- **Tree UI**: Display conversations without modification

### New Commands
```vim
:CcTuiBrowse        " Open conversation browser
:CcTuiRefresh       " Refresh conversation list
:CcTuiSelectProject " Manually select project
```

## MVP Deliverables

### Minimum Viable Product
1. **Project Discovery**: Auto-detect current project
2. **Conversation List**: Show all conversations as tabs
3. **Tab Selection**: Click/navigate to load conversation
4. **Tree Display**: Show selected conversation in tree

### Nice-to-Have (Post-MVP)
- Search across conversations
- Conversation metadata in tab headers
- Favorite/pin conversations
- Export conversation to markdown

## Success Metrics
- Can browse all conversations for current project
- Tab switching is responsive (<100ms)
- Memory usage stays reasonable with many conversations
- User can navigate entirely via keyboard

## Risk Mitigation
- **Large Files**: Implement streaming parser for huge conversations
- **Many Conversations**: Paginate or virtualize tab list
- **Missing Project**: Fallback to manual project selection
