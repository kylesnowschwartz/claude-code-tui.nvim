# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

CC-TUI.nvim is a Neovim plugin that provides a tabbed interface for viewing Claude Code conversations in a collapsible tree structure. It parses Claude Code JSONL conversation files and displays tool calls, results, and conversation flow in an organized, navigable format within Neovim.

## Core Architecture

### Tabbed Interface Design (MCPHub-Inspired)
The plugin follows a unified tabbed interface pattern with four main tabs:
- **Current (C)**: Shows the active conversation as a collapsible tree
- **Browse (B)**: Lists and navigates between conversations
- **Logs (L)**: Displays debug and activity logs
- **Help (?)**: Shows keybindings and usage instructions

### Key Components
- **TabbedManager** (`lua/cc-tui/ui/tabbed_manager.lua`): Orchestrates the unified tabbed UI
- **Conversation Parser** (`lua/cc-tui/parser/stream.lua`): Parses Claude Code JSONL conversation files
- **Tree Builder** (`lua/cc-tui/models/tree_builder.lua`): Converts parsed data into collapsible tree structures
- **Data Loader** (`lua/cc-tui/core/data_loader.lua`): Handles conversation file discovery and loading
- **UI Views** (`lua/cc-tui/ui/views/`): Individual tab implementations (base, browse, current, logs, help)

### Data Flow
1. **Discovery**: Project discovery service finds conversation files in `~/.claude/projects/`
2. **Parsing**: JSONL parser processes conversation files and links tool calls to results
3. **Tree Building**: Parsed data is converted to collapsible tree nodes
4. **Rendering**: TabbedManager displays the tree with appropriate syntax highlighting and interactions

## Development Commands

### Essential Commands
```bash
make deps          # Install dependencies (mini.nvim, nui.nvim, nui-components.nvim)
make style-fix     # Auto-format code with StyLua and sort imports
make style-check   # Verify code style compliance (used in CI)
make test          # Run test suite using mini.test
make documentation # Generate Neovim documentation
```

### Development Workflow
```bash
make all           # Run documentation, lint, luals, and test
make test-ci       # Install deps then run tests (for CI)
make luals         # Download and run Lua Language Server analysis
```

### Plugin Testing Commands
After making changes:
1. `:CcTuiReload` - Reload plugin modules with debug enabled
2. `:CcTui` - Open tabbed interface

## Code Style Requirements

### Mandatory Standards
- **Documentation**: All functions require `@param` and `@return` LuaDoc annotations
- **Validation**: Public APIs must use `vim.validate()` for parameter checking
- **Method Calls**: Always use colon syntax: `state:method()` not `state.method()`
- **Error Handling**: UI operations require `pcall()` protection
- **Component Cleanup**: Store UI component references and unmount properly

### Formatting Configuration (stylua.toml)
- **Column Width**: 120 characters
- **Indentation**: 4 spaces
- **Quote Style**: Auto-prefer double quotes
- **Line Endings**: Unix style
- **Sort Requires**: Automatic import sorting enabled

### Quality Gates
Code must pass:
- `make style-check` without errors
- `make luals` static analysis
- `make test` test suite
- Complete type annotations and documentation

## UI Component Framework

### NUI.nvim Integration
The plugin leverages the nui.nvim component framework extensively:
- **Tabbed Interface**: Uses NuiLine with custom highlighting for tab bars
- **Tree Views**: Built on nui.nvim Tree components with expand/collapse functionality
- **Popups**: Content preview windows for large tool outputs
- **Splits**: Window management for different views

### MCPHub-Inspired Patterns
Following established patterns from MCPHub.nvim:
- Tab bar creation with `Text.create_tab_bar()` styling
- Interactive list views with cursor tracking
- Custom borders with titles and consistent styling
- Rich text rendering using NuiLine patterns

## Conversation Data Format

### Claude Code JSONL Structure
The plugin parses conversation files stored at `~/.claude/projects/PROJECT_NAME/UUID.jsonl`. Each line contains:

#### Message Types
- **User Messages**: Direct text input, tool results, or SimpleClaude commands
- **Assistant Messages**: Responses with tool calls and text content

#### Tool Linking
- Assistant messages contain `tool_use` objects with unique IDs (`toolu_*`)
- User messages contain `tool_result` objects with matching `tool_use_id` fields
- Parser links these via ID matching to build tool execution chains

#### Key Fields
- `parentUuid`: Links messages in conversation chain
- `sessionId`: Groups messages by conversation session
- `timestamp`: Message timing for chronological ordering
- `cwd`, `gitBranch`, `version`: Context metadata for display

## Important Implementation Notes

### Content Classification System
The plugin includes sophisticated content classification (`lua/cc-tui/utils/content_classifier.lua`) that:
- Detects JSON, code, error messages, and plain text
- Determines appropriate display strategies (inline, popup, rich formatting)
- Uses configurable thresholds for line counts and character limits
- Provides tool-aware context for better classification

### Security Considerations
- Path security validation prevents directory traversal attacks
- JSON parsing limits prevent memory exhaustion
- Input validation on all public APIs
- Secure file operations with proper error handling

### Testing Framework
Uses `mini.test` with:
- Test helper utilities in `tests/helpers.lua`
- Child Neovim process isolation
- Minimal init script at `scripts/minimal_init.lua`
- Coverage for parser, UI components, and integration scenarios

## Dependencies

### Runtime Dependencies
- **Neovim**: Minimum version 0.9.x (tested on 0.9.x, 0.10.x, nightly)
- **nui.nvim**: UI component framework
- **nui-components.nvim**: Advanced reactive UI components

### Development Dependencies
- **mini.nvim**: Testing and documentation generation
- **StyLua**: Lua code formatting
- **luacheck**: Lua linting
- **lua-language-server**: Static analysis

## Plugin Commands and Keybindings

### User Commands
- `:CcTui` - Open tabbed interface with Current/Browse/Logs/Help tabs
- `:CcTuiReload` - Reload plugin modules with debug enabled (development)

### Development Keybindings
- `<leader>Cct` - Toggle cc-tui interface
- `<leader>Ccr` - Reload plugin modules

### Tab Navigation
- `C` - Switch to Current tab (conversation tree)
- `B` - Switch to Browse tab (conversation list)
- `L` - Switch to Logs tab (debug output)
- `?` - Switch to Help tab (keybindings)

## Configuration

### Default Options
The plugin provides extensive configuration through `lua/cc-tui/config.lua`:
- Content classification thresholds (lines, characters, JSON size limits)
- Display strategy preferences (popup, inline, syntax highlighting)
- Debug logging controls
- Performance settings (timeouts, memory limits)

### Setup Example
```lua
require("cc-tui").setup({
    debug = false, -- Enable debug logging
    content = {
        thresholds = {
            popup_lines = 3,
            popup_chars = 100,
            -- ... other thresholds
        }
    }
})
```
