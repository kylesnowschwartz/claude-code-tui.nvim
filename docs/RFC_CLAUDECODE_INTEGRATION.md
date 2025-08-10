# RFC: Direct Integration of cc-tui.nvim with claudecode.nvim

**RFC Number**: 001  
**Title**: Native Integration Architecture for cc-tui.nvim and claudecode.nvim  
**Status**: Draft v2  
**Author**: Kyle Snow Schwartz  
**Created**: 2025-01-10  
**Updated**: 2025-01-10 (Incorporating architectural review feedback)  
**Type**: Architecture  

## Executive Summary

This RFC proposes a direct integration architecture between cc-tui.nvim (advanced UI for Claude interactions) and claudecode.nvim (native Neovim MCP server implementation). The integration aims to combine cc-tui's sophisticated visualization capabilities with claudecode's native Neovim tool execution, creating a seamless AI-powered development environment within Neovim.

## 1. Background and Current State

### 1.1 cc-tui.nvim
- **Purpose**: Advanced terminal UI for Claude Code CLI with hierarchical tree visualization
- **Strengths**:
  - Sophisticated JSONL stream processing
  - NuiTree-based hierarchical visualization
  - Content classification system
  - Rich content rendering with syntax highlighting
  - Stream context threading for enhanced classification
- **Current Limitation**: Depends on external Claude Code CLI for actual AI interaction

### 1.2 claudecode.nvim
- **Purpose**: Native Neovim integration providing WebSocket MCP server
- **Strengths**:
  - Zero dependencies (pure Lua implementation)
  - Full MCP protocol compliance
  - VS Code extension feature parity (10 tools)
  - Native buffer manipulation
  - Selection tracking and diff support
  - Secure UUID v4 authentication
- **Current Limitation**: No advanced UI for displaying Claude's responses

### 1.3 Integration Opportunity
Both plugins complement each other perfectly:
- claudecode.nvim provides the **execution engine** (MCP tools, WebSocket server)
- cc-tui.nvim provides the **visualization layer** (tree UI, content rendering)

## 2. Integration Objectives

### Primary Goals
1. **Unified Experience**: Single plugin interface for Claude interactions within Neovim
2. **Native Performance**: Eliminate subprocess overhead by using claudecode's WebSocket server
3. **Rich Visualization**: Display Claude's responses using cc-tui's tree interface
4. **Tool Execution**: Leverage claudecode's native MCP tools for file operations
5. **Bidirectional Communication**: Enable real-time updates between UI and tool execution

### Secondary Goals
- Maintain backward compatibility with standalone usage
- Support both streaming and non-streaming modes
- Enable plugin-to-plugin communication without external dependencies
- Preserve existing user configurations

## 3. Proposed Architecture

### 3.1 High-Level Architecture (Revised)

```
┌─────────────────────────────────────────────────────────────┐
│                         User Input                           │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────┐
│                    cc-tui.nvim                               │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  Input Handler: Enhanced prompt with send-to-claude   │   │
│  └──────────────────────────────────────────────────────┘   │
│                         │                                    │
│                         ▼                                    │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  Integration Bridge (NEW)                             │   │
│  │  - Message formatting                                 │   │
│  │  - Event subscription via Neovim RPC                  │   │
│  │  - State synchronization                              │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────┬────────────────────────────────────┘
                         │
                  Neovim RPC Events
                         │
┌─────────────────────────┼────────────────────────────────────┐
│                    claudecode.nvim                           │
│                         ▼                                    │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  Event Emitter System                                 │   │
│  │  - Tool execution events                              │   │
│  │  - Selection change events                            │   │
│  │  - State update broadcasts                            │   │
│  └──────────────────────────────────────────────────────┘   │
│                         │                                    │
│                         ▼                                    │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  WebSocket Server (for Claude CLI)                    │   │
│  │  - Authentication                                     │   │
│  │  - MCP Tool Handlers                                  │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────┬────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────┐
│                    Claude Code CLI                           │
│              (Connected via WebSocket)                       │
└───────────────────────────────────────────────────────────────┘
```

**Key Architecture Change**: The integration now uses **Neovim RPC Events** instead of direct WebSocket connection between cc-tui and claudecode, simplifying the architecture and leveraging native Neovim capabilities.

### 3.2 Component Architecture

#### 3.2.1 Integration Bridge Module (Revised)
```lua
-- lua/cc-tui/integration/claudecode_bridge.lua
local M = {}

-- Connection management (simplified)
M.connection = {
  mode = "rpc", -- Primary mode: Neovim RPC events
  fallback_mode = "subprocess", -- Fallback if RPC unavailable
  status = "disconnected" | "connecting" | "connected",
  event_subscriptions = {}
}

-- Event subscription system
M.setup = function()
  -- Subscribe to claudecode events via Neovim autocmds
  vim.api.nvim_create_autocmd("User", {
    pattern = "ClaudeCodeToolExecution",
    callback = function(args)
      M.handle_tool_execution(args.data)
    end
  })
  
  vim.api.nvim_create_autocmd("User", {
    pattern = "ClaudeCodeToolResult", 
    callback = function(args)
      M.handle_tool_result(args.data)
    end
  })
  
  vim.api.nvim_create_autocmd("User", {
    pattern = "ClaudeCodeSelectionChange",
    callback = function(args)
      M.handle_selection_change(args.data)
    end
  })
end

-- Error boundary system
M.error_boundary = {
  handle_error = function(error, context)
    -- Log error without crashing integration
    vim.notify("Integration error: " .. error, vim.log.levels.WARN)
    -- Attempt graceful recovery
    M.attempt_recovery(context)
  end,
  
  attempt_recovery = function(context)
    -- Fallback to standalone mode if needed
    if context.critical then
      M.disable_integration()
    end
  end
}

-- State synchronization
M.state_sync = {
  claudecode_state = {},
  cc_tui_state = {},
  
  sync = function()
    -- Periodic state reconciliation
    vim.defer_fn(function()
      M.reconcile_states()
    end, 100)
  end
}
```

#### 3.2.2 Enhanced cc-tui Stream Processor
```lua
-- Extend existing stream processor for claudecode integration
local StreamProcessor = require("cc-tui.parser.stream")

function StreamProcessor:process_claudecode_event(event)
  -- Handle native claudecode events
  if event.type == "tool_execution" then
    self:add_tool_node(event.tool_name, event.params)
  elseif event.type == "tool_result" then
    self:add_result_node(event.result, event.tool_context)
  elseif event.type == "selection_update" then
    self:update_selection_context(event.selection)
  end
end
```

#### 3.2.3 Claudecode Event Emitter
```lua
-- Extend claudecode to emit events for cc-tui
-- lua/claudecode/events.lua
local M = {}

M.listeners = {}

function M.emit(event_type, data)
  for _, listener in ipairs(M.listeners[event_type] or {}) do
    listener(data)
  end
end

function M.on(event_type, callback)
  M.listeners[event_type] = M.listeners[event_type] or {}
  table.insert(M.listeners[event_type], callback)
end

-- Integration points in existing claudecode tools
-- Example in lua/claudecode/tools/open_file.lua:
local events = require("claudecode.events")

function handler(params)
  -- Existing logic...
  events.emit("tool:open_file", {
    file = params.path,
    line = params.line,
    timestamp = os.time()
  })
  -- Continue with existing logic...
end
```

### 3.3 Communication Patterns (Revised)

#### 3.3.1 Primary: Neovim RPC Bridge (Recommended)
```lua
-- Use Neovim's built-in RPC for plugin communication
local rpc_bridge = {
  setup = function()
    -- cc-tui subscribes to specific claudecode events
    local event_patterns = {
      "ClaudeCodeToolExecution",
      "ClaudeCodeToolResult",
      "ClaudeCodeSelectionChange",
      "ClaudeCodeDiffPreview",
      "ClaudeCodeStateUpdate"
    }
    
    for _, pattern in ipairs(event_patterns) do
      vim.api.nvim_create_autocmd("User", {
        pattern = pattern,
        callback = function(args)
          -- Process with error boundary
          local ok, err = pcall(function()
            cc_tui.process_event(pattern, args.data)
          end)
          if not ok then
            M.error_boundary.handle_error(err, { event = pattern })
          end
        end
      })
    end
  end,
  
  -- Emit events from claudecode
  emit = function(event_type, data)
    vim.api.nvim_exec_autocmds("User", {
      pattern = "ClaudeCode" .. event_type,
      data = data
    })
  end
}
```

#### 3.3.2 Fallback: Subprocess Mode
```lua
-- Fallback to subprocess if RPC unavailable
local subprocess_bridge = {
  setup = function()
    -- Only used if claudecode is not loaded or RPC fails
    local bridge_cmd = {
      "claude",
      "--output-format", "stream-json"
    }
    
    -- Start subprocess with proper error handling
    local handle = vim.loop.spawn(bridge_cmd[1], {
      args = vim.list_slice(bridge_cmd, 2),
      stdio = {stdin, stdout, stderr}
    }, function(code, signal)
      if code ~= 0 then
        M.error_boundary.handle_error("Subprocess failed", { code = code })
      end
    end)
  end
}
```

## 4. Technical Implementation Details

### 4.1 Data Flow (Optimized)

1. **User Input Phase**
   ```
   User types in cc-tui prompt → 
   cc-tui formats request → 
   Neovim RPC event to claudecode → 
   claudecode sends to Claude CLI
   ```

2. **Tool Execution Phase**
   ```
   Claude requests tool → 
   claudecode WebSocket receives → 
   MCP handler executes → 
   Emit RPC event to cc-tui → 
   Result sent back to Claude
   ```

3. **Visualization Phase**
   ```
   claudecode emits stream events → 
   cc-tui receives via RPC → 
   Tree builder creates nodes → 
   UI renders updates incrementally
   ```

**Key Improvement**: Reduced communication hops by using Neovim RPC events, eliminating the need for cc-tui to implement WebSocket client functionality.

### 4.2 Message Format Specification

#### Request Format (cc-tui → claudecode)
```json
{
  "type": "prompt",
  "content": "user prompt text",
  "context": {
    "current_file": "/path/to/file",
    "selection": { "start": [1, 0], "end": [10, 0] },
    "workspace": "/project/root"
  },
  "options": {
    "stream": true,
    "format": "jsonl"
  },
  "integration": {
    "source": "cc-tui",
    "version": "0.1.0",
    "ui_state": {
      "tree_expanded_nodes": ["node1", "node2"],
      "active_content_windows": []
    }
  }
}
```

#### Tool Event Format (claudecode → cc-tui)
```json
{
  "type": "tool_event",
  "tool": "openFile",
  "params": { "path": "/file.lua", "line": 42 },
  "result": { "success": true, "content": "..." },
  "timestamp": 1234567890
}
```

### 4.3 Configuration Schema (Enhanced)

```lua
require("cc-tui").setup({
  -- Existing cc-tui config...
  
  integration = {
    -- Enable claudecode integration
    claudecode = {
      enabled = true,
      mode = "rpc", -- Primary: "rpc", Fallback: "subprocess"
      
      -- Connection settings
      connection = {
        auto_connect = true,
        timeout = 5000,
        retry_attempts = 3,
        graceful_degradation = true -- Fallback to standalone on failure
      },
      
      -- Feature toggles
      features = {
        use_native_tools = true,
        sync_selection = true,
        show_tool_events = true,
        enhanced_diffs = true
      },
      
      -- Performance settings
      performance = {
        cache_size = 1000,
        cache_ttl_ms = 300000, -- 5 minutes
        event_debounce_ms = 100,
        max_memory_mb = 10
      },
      
      -- Error handling
      error_handling = {
        max_retries = 3,
        retry_delay_ms = 1000,
        fallback_to_standalone = true,
        log_level = "warn" -- "debug", "info", "warn", "error"
      }
    }
  }
})
```

## 5. Benefits and Trade-offs

### Benefits
1. **Performance**: Native execution without subprocess overhead
2. **Reliability**: Direct communication reduces failure points
3. **Feature Richness**: Combines best features of both plugins
4. **User Experience**: Seamless integration within Neovim
5. **Maintainability**: Clear separation of concerns

### Trade-offs
1. **Complexity**: Additional integration layer to maintain
2. **Dependencies**: cc-tui now depends on claudecode for full functionality
3. **Testing**: Requires comprehensive integration testing
4. **Migration**: Users need to install both plugins

## 6. Migration Strategy (Revised)

### Phase 1: Foundation (Week 1-2)
- [ ] Create integration bridge module with RPC event system
- [ ] Implement Neovim event emitters in claudecode tools
- [ ] Add error boundary system
- [ ] Create configuration schema with graceful degradation

### Phase 2: Core Integration (Week 2-3)
- [ ] Implement RPC-based message passing
- [ ] Connect stream processor to claudecode events
- [ ] Add state synchronization layer
- [ ] Implement fallback subprocess mode

### Phase 3: MVP Release (Week 4)
- [ ] Basic tool execution visualization
- [ ] Integration testing framework
- [ ] Performance monitoring
- [ ] Alpha release for early adopters

### Phase 4: Enhancement (Week 5-6)
- [ ] Advanced features (selection sync, diff preview)
- [ ] Cache optimization
- [ ] Resource management
- [ ] Beta release

### Phase 5: Stabilization (Week 7-8)
- [ ] Community testing
- [ ] Bug fixes and performance tuning
- [ ] Complete documentation
- [ ] Official release

**Critical Success Factors**:
- Backward compatibility maintained throughout
- Graceful degradation at every integration point
- No performance regression in standalone mode
- Clear migration path for existing users

## 7. Future Considerations

### 7.1 Extended Features
- **Collaborative Editing**: Multiple users sharing Claude session
- **Tool Marketplace**: Custom MCP tools integration
- **AI Model Selection**: Support for different Claude models
- **Persistent Sessions**: Save/restore Claude conversations

### 7.2 Performance Optimizations
- **Lazy Loading**: Load components on demand
- **Caching Layer**: Cache tool results and responses
- **Batch Operations**: Group multiple tool executions
- **Incremental Updates**: Efficient tree updates

### 7.3 Ecosystem Integration
- **LSP Integration**: Combine with language servers
- **DAP Integration**: Debugging support
- **Telescope Integration**: Search Claude history
- **Which-key Integration**: Contextual key hints

## 8. Security Considerations (Enhanced)

### Authentication Flow
```
1. claudecode generates UUID v4 token
2. Token stored in lock file with restricted permissions
3. cc-tui validates token format before use
4. Periodic token rotation (configurable interval)
5. Secure RPC communication within Neovim process
```

### Permission Model
```lua
-- Enhanced permission scoping
local permissions = {
  cc_tui = {
    read = {
      tool_events = true,
      selection_state = true,
      file_changes = true
    },
    write = {
      execute_tools = false, -- cc-tui cannot execute tools directly
      modify_files = false,
      change_settings = false
    }
  },
  event_filtering = {
    allowed_events = {
      "ToolExecution",
      "ToolResult", 
      "SelectionChange"
    },
    blocked_events = {
      "ConfigChange",
      "APIKeyAccess"
    }
  }
}
```

### Security Best Practices
- No direct file system access from integration layer
- API keys never transmitted through RPC events
- Sensitive data scrubbed from logs
- User approval required for destructive operations

## 9. Testing Strategy (Comprehensive)

### Unit Tests
- Bridge module functions with mocked dependencies
- RPC event handling with various payloads
- Error boundary recovery scenarios
- State synchronization logic
- Cache management and eviction

### Integration Tests
```lua
-- Example integration test structure
describe("cc-tui and claudecode integration", function()
  it("handles tool execution events", function()
    -- Setup both plugins
    -- Emit tool event from claudecode
    -- Verify cc-tui receives and visualizes
  end)
  
  it("gracefully degrades on connection failure", function()
    -- Simulate RPC failure
    -- Verify fallback to subprocess mode
    -- Ensure no data loss
  end)
  
  it("maintains backward compatibility", function()
    -- Test standalone cc-tui operation
    -- Test standalone claudecode operation
    -- Verify no regression
  end)
end)
```

### Performance Tests
- RPC event latency measurement
- Memory usage with large event streams
- Cache hit/miss ratios
- Tree update performance with 1000+ nodes
- Resource cleanup verification

## 10. Documentation Requirements

### User Documentation
- Installation guide
- Configuration reference
- Usage examples
- Troubleshooting guide

### Developer Documentation
- Architecture overview
- API reference
- Contributing guidelines
- Plugin development guide

## Appendix A: API Specifications

### cc-tui Public API
```lua
-- Core functions exposed for integration
M.send_to_claude(prompt, options)
M.process_stream(jsonl_data)
M.render_tree(node_data)
M.show_content(content_data)
```

### claudecode Public API
```lua
-- Functions available for cc-tui
M.get_server_info()
M.execute_tool(name, params)
M.get_current_selection()
M.subscribe_to_events(callback)
```

## Appendix B: Compatibility Matrix

| Feature | Standalone cc-tui | Standalone claudecode | Integrated |
|---------|------------------|----------------------|------------|
| Tree UI | ✅ | ❌ | ✅ |
| Native Tools | ❌ | ✅ | ✅ |
| Stream Processing | ✅ | ❌ | ✅ |
| WebSocket Server | ❌ | ✅ | ✅ |
| Content Classification | ✅ | ❌ | ✅ |
| Diff Preview | ❌ | ✅ | ✅ |

## Appendix C: Risk Assessment (Updated)

| Risk | Probability | Impact | Mitigation |
|------|------------|--------|------------|
| Breaking changes in claudecode | Medium | High | Version pinning, API contracts, compatibility tests |
| RPC event failures | Low | Low | Graceful degradation to subprocess mode |
| State synchronization issues | Medium | Medium | Periodic reconciliation, event replay |
| Performance degradation | Low | Medium | Profiling, caching, lazy loading |
| Memory leaks | Low | High | Resource monitoring, automatic cleanup |
| User adoption challenges | Medium | Low | Clear documentation, migration tools |

## Appendix D: Performance Optimization Strategies

### Caching Strategy
```lua
local cache_strategy = {
  -- LRU cache with TTL
  eviction_policy = "lru",
  max_items = 1000,
  ttl_ms = 300000, -- 5 minutes
  
  -- Memory-aware eviction
  memory_limit_mb = 10,
  monitor_interval_ms = 5000,
  
  -- Pre-compiled templates for common operations
  template_cache = {
    tool_events = {},
    tree_nodes = {}
  }
}
```

### Event Debouncing
```lua
local debounce_config = {
  selection_change = 100, -- ms
  tree_update = 50,
  content_render = 150
}
```

## Appendix E: Version Compatibility Matrix

| cc-tui Version | claudecode Version | Integration Status |
|----------------|-------------------|-------------------|
| 0.1.x | 0.1.x | Full compatibility |
| 0.1.x | 0.2.x | Partial (fallback mode) |
| 0.2.x | 0.1.x | Partial (limited features) |
| 0.2.x | 0.2.x | Full compatibility |

---

**END OF RFC v2**

This RFC has been updated based on architectural review feedback. Key changes include:
- Simplified communication using Neovim RPC instead of WebSocket
- Added error boundary and graceful degradation systems
- Enhanced security model with permission scoping
- Improved performance strategies with caching and debouncing
- More realistic migration timeline with MVP approach

The revised architecture prioritizes simplicity, reliability, and maintainability while preserving the core benefits of the integration.
