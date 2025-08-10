# CC-TUI.nvim Test Suite Refactoring Plan

## Executive Summary

This document outlines the comprehensive refactoring plan for CC-TUI.nvim's test suite, based on analysis from context-analyzer and system-architect agents. The plan focuses on removing backward compatibility code, implementing TDD red/green cycles for AI agent-driven development, and leveraging real Claude Code CLI output for authentic testing.

## Current State Analysis

### Test Data Assets
- **12 real JSONL conversation files** in `docs/test/projects/-Users-kyle-Code-cc-tui-nvim/`
- **Size range**: 2KB to 7.2MB providing comprehensive test scenarios
- **Content**: Authentic Claude Code CLI output with complete metadata and tool usage patterns

### Backward Compatibility Code to Remove
- **13 files** containing deprecated `CcTuiBrowse` references
- **Legacy ConversationBrowser component** (~1,200 lines)
- **Deprecated commands** and related infrastructure
- **Legacy keybindings** and documentation

### Current Test Structure
- **Framework**: mini.test with child process isolation
- **Helpers**: `tests/helpers.lua` with test utilities
- **Coverage**: Basic functionality with some integration tests
- **Gaps**: Limited UI testing, incomplete error handling, minimal performance testing

## Test Architecture Design

### Phase 1: Foundation & Cleanup (Iterations 1-4)

#### 1.1 Remove Backward Compatibility Code
**Goal**: Eliminate deprecated `CcTuiBrowse` infrastructure safely
```lua
-- Target files for removal/modification:
-- plugin/cc-tui.lua (remove CcTuiBrowse command)
-- lua/cc-tui/main.lua (remove M.browse() function)
-- CLAUDE.md (update documentation)
-- All test files referencing deprecated functionality
```

**TDD Approach**:
- **RED**: Write tests that verify deprecated code is completely removed
- **GREEN**: Remove code while maintaining passing tests
- **REFACTOR**: Clean up any remaining references or orphaned code

#### 1.2 Enhanced Test Data Infrastructure
**Goal**: Robust real data integration with categorized test scenarios
```lua
-- Enhanced RealDataLoader with categories:
local RealDataLoader = {
    categories = {
        tiny = {"file1.jsonl"},     -- 2KB, fast unit tests
        small = {"file2.jsonl"},    -- 140KB, integration tests  
        medium = {"file3.jsonl"},   -- 200-400KB, feature testing
        large = {"file4.jsonl"},    -- 900KB-1.2MB, stress testing
        huge = {"file5.jsonl"}      -- 3-7MB, performance validation
    },
    load_by_category = function(category, callback) end,
    load_all = function(callback) end,
    get_conversation_info = function(filepath) end
}
```

**TDD Approach**:
- **RED**: Write tests for conversation categorization and loading
- **GREEN**: Implement category-based loading with proper error handling
- **REFACTOR**: Optimize loading performance and memory usage

### Phase 2: Core Component Testing (Iterations 5-9)

#### 2.1 JSONL Parser & Message Linking Tests
**Goal**: Comprehensive parser testing with real conversation data

```lua
-- Test structure for parser module
describe("JSONL Parser", function()
    describe("parse_line", function()
        it("handles user messages correctly", function()
            -- RED: Define expected behavior for user message parsing
        end)
        
        it("handles assistant messages with tool calls", function()
            -- RED: Define expected tool call parsing and ID extraction
        end)
        
        it("links tool results to tool calls correctly", function()
            -- RED: Define expected tool linking behavior
        end)
    end)
    
    describe("get_session_info", function()
        it("extracts session metadata correctly", function()
            -- RED: Define expected session information extraction
        end)
    end)
    
    describe("error handling", function()
        it("handles malformed JSON gracefully", function()
            -- RED: Define expected error handling behavior
        end)
    end)
end)
```

**Real Data Integration**:
- Use tiny files for unit tests (fast execution)
- Use medium/large files for integration scenarios
- Test edge cases found in real conversation data

#### 2.2 Tree Building & Node Structure Tests
**Goal**: Validate tree construction with authentic conversation hierarchies

```lua
-- Test structure for tree builder
describe("TreeBuilder", function()
    describe("build_tree", function()
        it("creates proper message hierarchy", function()
            -- RED: Define expected tree structure for conversations
        end)
        
        it("handles tool call nesting correctly", function()
            -- RED: Define expected tool call node organization
        end)
        
        it("preserves message order and relationships", function()
            -- RED: Define expected chronological ordering
        end)
    end)
    
    describe("node operations", function()
        it("supports expand/collapse operations", function()
            -- RED: Define expected tree interaction behavior
        end)
    end)
end)
```

#### 2.3 Content Classification & Display Strategy Tests
**Goal**: Test sophisticated content analysis with real tool outputs

```lua
-- Test structure for content classifier
describe("ContentClassifier", function()
    describe("classify_content", function()
        it("detects JSON content correctly", function()
            -- RED: Test with real JSON outputs from conversations
        end)
        
        it("identifies code blocks accurately", function()
            -- RED: Test with actual code snippets from tool results
        end)
        
        it("handles error messages appropriately", function()
            -- RED: Test with real error outputs from conversations
        end)
    end)
    
    describe("display_strategy", function()
        it("selects appropriate display for content type", function()
            -- RED: Define expected strategy selection logic
        end)
    end)
end)
```

### Phase 3: UI Integration Testing (Iterations 10-13)

#### 3.1 Tabbed Interface Tests
**Goal**: Comprehensive testing of TabbedManager and all four tabs

```lua
-- Test structure for tabbed interface
describe("TabbedManager", function()
    describe("initialization", function()
        it("creates all required tabs", function()
            -- RED: Verify Current/Browse/Logs/Help tabs created
        end)
        
        it("handles window sizing correctly", function()
            -- RED: Test responsive sizing behavior
        end)
    end)
    
    describe("tab navigation", function()
        it("switches between tabs correctly", function()
            -- RED: Test C/B/L/? keybinding functionality
        end)
        
        it("preserves tab state during switches", function()
            -- RED: Test state persistence across tab changes
        end)
    end)
    
    describe("tab content", function()
        it("renders Current tab with conversation tree", function()
            -- RED: Test tree rendering with real conversation data
        end)
        
        it("renders Browse tab with conversation list", function()
            -- RED: Test conversation list functionality
        end)
    end)
end)
```

#### 3.2 Data Loading & Project Discovery Tests
**Goal**: Test realistic project discovery and conversation loading

```lua
-- Test structure for data loading
describe("DataLoader", function()
    describe("project_discovery", function()
        it("finds conversation files correctly", function()
            -- RED: Test with realistic project structures
        end)
        
        it("extracts metadata properly", function()
            -- RED: Test metadata extraction from real files
        end)
    end)
    
    describe("conversation_loading", function()
        it("loads conversations with proper error handling", function()
            -- RED: Test loading with various file conditions
        end)
        
        it("handles large files efficiently", function()
            -- RED: Test with huge category files (7MB)
        end)
    end)
end)
```

### Phase 4: Performance & Stress Testing (Iterations 14-16)

#### 4.1 Large File Performance Tests
**Goal**: Validate performance with realistic large conversation files

```lua
-- Performance testing structure
describe("Performance Tests", function()
    describe("large_file_handling", function()
        it("parses 7MB conversation files within timeout", function()
            -- RED: Define acceptable parsing time limits
        end)
        
        it("maintains UI responsiveness with large trees", function()
            -- RED: Define UI interaction performance criteria
        end)
        
        it("manages memory usage appropriately", function()
            -- RED: Define memory usage limits for large conversations
        end)
    end)
end)
```

#### 4.2 Stress Testing & Edge Cases
**Goal**: Test system limits and error recovery

```lua
-- Stress testing structure  
describe("Stress Tests", function()
    describe("edge_cases", function()
        it("handles empty conversation files", function()
            -- RED: Define behavior for edge case scenarios
        end)
        
        it("recovers from parsing errors gracefully", function()
            -- RED: Test error recovery mechanisms
        end)
        
        it("handles rapid tab switching correctly", function()
            -- RED: Test UI stability under rapid interactions
        end)
    end)
end)
```

## Implementation Strategy

### TDD Red/Green/Refactor Cycles

Each component follows this pattern:
1. **RED**: Write failing test defining expected behavior
2. **GREEN**: Implement minimal code to pass the test  
3. **REFACTOR**: Improve implementation while maintaining green tests

### Real Data Testing Approach

- **Tiny files (2KB)**: Fast unit tests, basic parsing validation
- **Small files (140KB)**: Standard integration tests, typical scenarios
- **Medium files (200-400KB)**: Feature testing, comprehensive workflows
- **Large files (900KB-1.2MB)**: Performance validation, stress scenarios
- **Huge files (3-7MB)**: Memory management, extreme edge cases

### Quality Gates

Before each phase completion:
1. All tests pass (`make test`)
2. Code formatting compliant (`make style-check`)
3. Static analysis clean (`make luals`)
4. Documentation updated
5. Performance benchmarks met

### Test Execution Strategy

```bash
# Run categorized tests
make test-tiny     # Fast unit tests with small data
make test-small    # Integration tests with typical data  
make test-medium   # Feature tests with realistic data
make test-large    # Performance tests with big data
make test-huge     # Stress tests with extreme data
make test-all      # Complete test suite
```

## Success Criteria

### Functional Requirements
- [ ] All backward compatibility code removed (0 CcTuiBrowse references)
- [ ] All 12 conversation files successfully tested
- [ ] Complete tabbed interface functionality validated
- [ ] All core components have comprehensive test coverage

### Performance Requirements
- [ ] 7MB conversation files parse within 5 seconds
- [ ] UI remains responsive during large file operations
- [ ] Memory usage stays within reasonable limits
- [ ] All tests complete within acceptable timeouts

### Quality Requirements
- [ ] 100% test pass rate maintained throughout refactor
- [ ] Code formatting and linting standards met
- [ ] Documentation reflects actual functionality
- [ ] No functional regressions introduced

## Risk Mitigation

### Backward Compatibility Removal
- **Risk**: Breaking existing workflows
- **Mitigation**: Comprehensive dependency mapping, staged removal with validation

### Large File Testing  
- **Risk**: Test timeouts or memory issues
- **Mitigation**: Categorized approach with appropriate timeouts, memory monitoring

### UI Testing Complexity
- **Risk**: Unreliable tabbed interface testing
- **Mitigation**: Component isolation, established NUI.nvim patterns

### TDD Implementation
- **Risk**: Tests not suitable for AI agent development
- **Mitigation**: Clear red/green/refactor cycles, automated validation points

## Conclusion

This comprehensive test refactoring plan transforms CC-TUI.nvim into a robust, well-tested codebase that supports confident AI agent-driven development. By leveraging real Claude Code CLI output and implementing TDD cycles, we ensure authentic testing scenarios while maintaining code quality and enabling continuous improvement.

The phased approach allows for safe removal of deprecated functionality while building comprehensive test coverage that validates all aspects of the tabbed interface architecture with real-world data scenarios.
