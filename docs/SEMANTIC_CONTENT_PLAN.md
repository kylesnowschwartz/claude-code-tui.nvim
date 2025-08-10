# Semantic Content Classification Plan: Enhanced UX for cc-tui.nvim

## Overview
Implementation plan for transforming cc-tui.nvim from basic content display into a semantic-aware visualization system that understands and appropriately renders different types of Claude Code tool interactions.

## Architecture Summary
- **Unified Content Classification**: Single source of truth for content type detection
- **Tool-Aware Semantics**: Distinguish tool inputs (always JSON) from outputs (context-dependent)
- **Strategic Display Logic**: Right content type in right format for optimal UX
- **Performance Optimization**: Lazy loading, caching, and efficient rendering
- **Backward Compatibility**: Existing workflows preserved during transition

## Implementation Phases

### ⏳ Phase 1: Foundation - Unified Content Classification [CRITICAL]
**Goal**: Replace fragmented detection logic with unified semantic classifier

**Dependencies**: Current content rendering system
**Tasks:**
- [ ] 1.1 Create `ContentClassifier` service (`lua/cc-tui/utils/content_classifier.lua`)
- [ ] 1.2 Implement robust JSON validation using `pcall(vim.fn.json_decode)`
- [ ] 1.3 Define comprehensive content type taxonomy (TOOL_INPUT, JSON_API_RESPONSE, etc.)
- [ ] 1.4 Centralize display thresholds in `config.lua`
- [ ] 1.5 **Validation**: All three existing detection functions replaced with unified logic

**Success Criteria**: Same content always classified identically across all modules

---

### ⏳ Phase 2: Tool Input/Output Distinction [HIGH PRIORITY]
**Goal**: Semantic awareness of tool parameters vs tool results

**Dependencies**: Phase 1 complete
**Tasks:**
- [ ] 2.1 Add context parameter to `ContentClassifier.classify(content, tool_name, context)`
- [ ] 2.2 Implement tool input detection (always JSON popup display)
- [ ] 2.3 Add tool output classification (file content, command output, API responses)
- [ ] 2.4 Update `tree_builder.lua` to pass input/output context
- [ ] 2.5 **Validation**: Tool parameters always show as JSON, results show contextually

**Success Criteria**: Clear visual distinction between what user sent vs what tool returned

---

### ⏳ Phase 3: Enhanced MCP Response Handling [HIGH PRIORITY]
**Goal**: Proper handling of MCP server responses with structured data awareness

**Dependencies**: Phase 2 complete
**Tasks:**
- [ ] 3.1 Add MCP JSON-RPC response detection (`"jsonrpc": "2.0"` pattern)
- [ ] 3.2 Implement specialized MCP response renderer with enhanced folding
- [ ] 3.3 Add MCP metadata extraction (api_source, response_type)
- [ ] 3.4 Create MCP-specific display strategies in content renderer
- [ ] 3.5 **Validation**: MCP responses (like Context7 library data) display as structured JSON

**Success Criteria**: 9181-character MCP responses are navigable with proper JSON folding

---

### ⏳ Phase 4: Smart File Content Detection [MEDIUM PRIORITY]
**Goal**: File-extension and content-aware syntax highlighting

**Dependencies**: Phase 3 complete
**Tasks:**
- [ ] 4.1 Enhance file extension detection in `ContentClassifier`
- [ ] 4.2 Add file-type specific rendering strategies (.json, .js, .py, .lua, etc.)
- [ ] 4.3 Implement syntax highlighting selection based on detected file type
- [ ] 4.4 Add special handling for configuration files (package.json, .nvimrc, etc.)
- [ ] 4.5 **Validation**: Read tool results show with appropriate syntax highlighting

**Success Criteria**: File contents display with correct syntax highlighting automatically

---

### ⏳ Phase 5: Performance & Caching Optimization [MEDIUM PRIORITY]
**Goal**: Efficient handling of large content with lazy loading and caching

**Dependencies**: Phase 4 complete
**Tasks:**
- [ ] 5.1 Implement content classification result caching
- [ ] 5.2 Add lazy content loading for tree nodes (store references, not full content)
- [ ] 5.3 Create progressive loading for very large tool outputs
- [ ] 5.4 Add memory usage monitoring and cleanup
- [ ] 5.5 **Validation**: Large content (>10MB) loads without UI freezing

**Success Criteria**: Responsive UI even with massive tool outputs

---

## Component Architecture

### New Components
- `lua/cc-tui/utils/content_classifier.lua` - Unified content type detection service
- `lua/cc-tui/utils/display_strategies.lua` - Rendering strategy definitions
- `lua/cc-tui/renderers/mcp_response.lua` - Specialized MCP response renderer
- `lua/cc-tui/cache/classification_cache.lua` - Content classification caching

### Enhanced Components
- `lua/cc-tui/config.lua` - Centralized display thresholds and strategies
- `lua/cc-tui/ui/content_renderer.lua` - Strategy-based rendering dispatch
- `lua/cc-tui/models/tree_builder.lua` - Context-aware content classification calls
- `lua/cc-tui/parser/content.lua` - Remove duplicate detection, use classifier

## Semantic Content Types

### Content Type Taxonomy
```lua
ContentTypes = {
    -- Always JSON display
    TOOL_INPUT = "tool_input",           -- Tool parameters (always structured)
    JSON_API_RESPONSE = "json_api",      -- MCP responses, API calls
    ERROR_OBJECT = "error_object",       -- Structured error responses
    
    -- Context-aware display  
    FILE_CONTENT = "file_content",       -- Read tool results
    COMMAND_OUTPUT = "command_output",   -- Bash/shell output
    
    -- Fallback
    GENERIC_TEXT = "generic_text"        -- Plain text content
}
```

### Display Strategy Mapping
```lua
DisplayStrategies = {
    tool_input = "json_popup_always",
    json_api = "json_popup_with_folding", 
    error_object = "error_json_popup",
    file_content = "syntax_highlighted_popup",
    command_output = "terminal_style_popup",
    generic_text = "adaptive_popup_or_inline"
}
```

## Data Flow Patterns

### Current State (Fragmented)
```
content → [parser/content.lua].is_json_content() → display decision
content → [tree_builder.lua].is_json_content() → display decision  
content → [content_renderer.lua].is_json_content() → display decision
```

### Target State (Unified)
```
content + tool_name + context → ContentClassifier.classify() → 
{type, confidence, display_strategy, metadata} → 
DisplayStrategyDispatcher.render() → 
Appropriate UI Component
```

## Risk Mitigation

**Classification Accuracy**: Comprehensive test suite with real Claude Code output samples
**Performance Impact**: Lazy evaluation, result caching, progressive loading
**Backward Compatibility**: Feature flags, gradual migration, fallback strategies  
**Memory Usage**: Reference-based tree nodes, automatic cleanup, size limits
**User Experience**: Visual feedback, consistent behavior, intuitive semantics

## Success Metrics

- **Classification Consistency**: Same content → same display type (100% consistency)
- **Semantic Accuracy**: Tool inputs always JSON, outputs contextually appropriate
- **Performance**: Content classification <10ms for typical tool outputs
- **User Experience**: Reduced navigation time, clearer content understanding
- **Maintainability**: Single content classification function across all modules

---

## Current Status: Ready for Phase 1

**Next Action**: Create `ContentClassifier` service and replace first duplicate detection function

**Critical Path**: 
1. Week 1: Unified ContentClassifier (Phase 1)
2. Week 2: Tool input/output distinction (Phase 2) 
3. Week 3: MCP response handling (Phase 3)
4. Week 4: File content detection (Phase 4)

**Success Indicators**:
- [ ] MCP Context7 responses (9181 chars) display as navigable JSON
- [ ] Tool parameters always show JSON syntax highlighting
- [ ] Read tool results show appropriate file-type syntax highlighting
- [ ] No more inconsistent content classification across modules
- [ ] Large content loads without UI freezing

---

## Strategic Impact

This plan transforms cc-tui.nvim from a **basic content displayer** into a **semantic-aware visualization system** that understands the meaning and context of different Claude Code interactions, providing users with intuitive, contextually appropriate content presentation.
