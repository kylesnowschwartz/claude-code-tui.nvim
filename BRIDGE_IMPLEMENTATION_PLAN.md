# Bridge Implementation Plan: Dual-Mode Architecture for cc-tui.nvim

## Overview
Implementation plan for extending cc-tui.nvim to handle both static JSONL test data and live streaming JSON from Claude Code CLI using a Provider Pattern architecture.

## Architecture Summary
- **Provider Pattern**: Abstract data sources through common interface
- **Incremental Updates**: Delta updates for live streaming without full rebuilds
- **Backward Compatibility**: Existing test data workflow preserved
- **Async Safety**: All UI updates via `vim.schedule()` for thread safety

## Implementation Phases

### ✅ Phase 1: Provider Abstraction Foundation
**Goal**: Create provider interface and migrate existing static data loading

**Tasks:**
- [x] 1.1 Create `DataProvider` base interface (`lua/cc-tui/providers/base.lua`)
- [ ] 1.2 Implement `StaticProvider` wrapping existing test data logic (`lua/cc-tui/providers/static.lua`)
- [ ] 1.3 Refactor `main.lua` to use provider abstraction instead of direct test data loading
- [ ] 1.4 **Validation**: Existing test data workflow works unchanged

**Success Criteria**: Plugin works identically to current behavior with provider abstraction

---

### ⏳ Phase 2: Parser Refactoring
**Goal**: Make parsing logic reusable for both batch and streaming modes

**Dependencies**: Phase 1 complete
**Tasks:**
- [ ] 2.1 Extract reusable parsing logic from `lua/cc-tui/parser/stream.lua`
- [ ] 2.2 Add `parse_line()` method for single-line processing
- [ ] 2.3 Maintain `parse_batch()` method for static data
- [ ] 2.4 **Validation**: Both parsing modes produce identical results for same input

**Success Criteria**: Parser handles both batch JSONL files and individual streaming lines

---

### ⏳ Phase 3: TreeBuilder Enhancement
**Goal**: Add incremental update capabilities for live streaming

**Dependencies**: Phase 2 complete
**Tasks:**
- [ ] 3.1 Add incremental update methods to `TreeBuilder`
- [ ] 3.2 Implement `add_message()` for new messages
- [ ] 3.3 Implement `update_message()` for delta updates
- [ ] 3.4 Add message ID tracking for efficient lookups
- [ ] 3.5 **Validation**: Tree structure updates correctly without full rebuilds

**Success Criteria**: Tree can be updated incrementally while maintaining structure integrity

---

### ⏳ Phase 4: Bridge Implementation
**Goal**: Implement Claude CLI subprocess integration and event mapping

**Dependencies**: Phase 3 complete
**Tasks:**
- [ ] 4.1 Create `EventBridge` for Claude CLI event mapping (`lua/cc-tui/bridge/event_bridge.lua`)
- [ ] 4.2 Implement `StreamProvider` with subprocess management (`lua/cc-tui/providers/stream.lua`)
- [ ] 4.3 Add error handling and graceful subprocess termination
- [ ] 4.4 Map Claude CLI events (`system.init`, `completion`, `text`, `assistant`, etc.) to internal message format
- [ ] 4.5 **Validation**: Claude CLI integration produces correct message objects

**Success Criteria**: Can spawn Claude CLI and receive structured events as internal messages

---

### ⏳ Phase 5: Live Update Coordination
**Goal**: Coordinate async UI updates with thread safety

**Dependencies**: Phase 4 complete
**Tasks:**
- [ ] 5.1 Implement `UpdateCoordinator` for async UI updates (`lua/cc-tui/coordinator/update.lua`)
- [ ] 5.2 Add `vim.schedule()` integration for thread safety
- [ ] 5.3 Coordinate tree updates with existing UI components
- [ ] 5.4 Handle update batching and queue management
- [ ] 5.5 **Validation**: Live streaming updates display correctly in tree UI

**Success Criteria**: Real-time streaming data appears in tree UI without blocking or crashes

---

## Component Architecture

### New Components
- `lua/cc-tui/providers/base.lua` - Abstract DataProvider interface
- `lua/cc-tui/providers/static.lua` - Static JSONL file provider  
- `lua/cc-tui/providers/stream.lua` - Claude CLI streaming provider
- `lua/cc-tui/bridge/event_bridge.lua` - Claude event to message mapping
- `lua/cc-tui/coordinator/update.lua` - Async UI update coordination

### Enhanced Components
- `lua/cc-tui/parser/stream.lua` - Add reusable parsing methods
- `lua/cc-tui/models/tree_builder.lua` - Add incremental update methods
- `lua/cc-tui/main.lua` - Use provider abstraction

## Data Flow Patterns

### Static Mode (Current)
```
StaticProvider → Parser.parse_batch() → TreeBuilder.build_tree() → Tree UI
```

### Streaming Mode (Target)
```
StreamProvider → EventBridge → Parser.parse_line() → UpdateCoordinator → TreeBuilder.update_tree() → Tree UI (via vim.schedule)
```

## Risk Mitigation

**Subprocess Management**: Timeout handling, process monitoring, graceful fallback
**Memory Usage**: Message pruning, configurable limits, memory monitoring  
**UI Thread Safety**: Proper `vim.schedule()` usage, update queuing
**Parsing Compatibility**: Version detection, flexible event mapping

## Success Metrics

- **Backward Compatibility**: Existing test workflows unchanged
- **Performance**: Incremental updates faster than full rebuilds
- **Reliability**: Graceful handling of subprocess failures
- **User Experience**: Both modes appear identical to end user

---

## Current Status: Ready for Phase 1
**Next Action**: Implement DataProvider interface and StaticProvider wrapper
