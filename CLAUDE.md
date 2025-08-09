# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Neovim plugin boilerplate template designed to provide a complete development setup for creating Neovim plugins. The project is still in its template state with placeholder names that need to be replaced when creating actual plugins.

## Architecture

### Core Structure
- `lua/your-plugin-name/init.lua` - Main plugin entry point with public API (toggle, enable, disable, setup)
- `lua/your-plugin-name/config.lua` - Configuration management with defaults and validation
- `lua/your-plugin-name/main.lua` - Core functionality implementation
- `lua/your-plugin-name/state.lua` - Plugin state management with global persistence
- `lua/your-plugin-name/util/log.lua` - Logging utilities
- `plugin/your-plugin-name.lua` - Neovim plugin registration file

### Plugin Pattern
The template follows a standard Neovim plugin architecture:
1. **Global State**: Uses `_G.YourPluginName` for global state management
2. **Configuration**: Merges user options with defaults using `vim.tbl_deep_extend`
3. **State Management**: Maintains enabled/disabled state with persistence
4. **Logging**: Debug logging system with scope-based messages

## Code Style Requirements for AI Agents

*MANDATORY for all AI agents working on this codebase*

### **Essential Reading**
1. **📋 Read `STYLE_GUIDE.md` FIRST** - Contains complete patterns and examples
2. **🔍 Check existing files** for established patterns before coding
3. **⚙️ Understand tooling** - Use `make style-fix` and `make style-check`

### **Non-Negotiable Requirements**
- ✅ **Documentation**: Every function needs `@param` and `@return` annotations
- ✅ **Validation**: Every public API must use `vim.validate()`
- ✅ **Error Handling**: Every UI operation needs `pcall()` protection
- ✅ **Method Calls**: Always use colon syntax: `state:method()` not `state.method(state)`
- ✅ **Component Cleanup**: Store references and unmount properly

### **Workflow Commands**
```bash
make style-fix     # Auto-format and sort imports (run before/after coding)
make style-check   # Verify compliance (must pass before submitting)
```

### **Quality Gate**
Code will be rejected if:
- Missing type annotations or documentation
- Style checks fail
- UI components lack proper error handling
- Inconsistent patterns with existing codebase

**📚 For complete patterns, examples, and anti-patterns, see `STYLE_GUIDE.md`**

## Development Commands

### Setup and Installation
- `make setup` - Interactive setup script to replace placeholder names
- `USERNAME=user PLUGIN_NAME=name REPOSITORY_NAME=repo.nvim make setup` - Automated setup

### Core Development
- `make deps` - Install mini.nvim dependency for docs and tests
- `make style-fix` - **Auto-fix style issues (run before committing)**
- `make style-check` - **Check style without fixing (for CI)**
- `make lint` - Format code with StyLua and run luacheck (legacy - use style-* instead)
- `make test` - Run tests using mini.test  
- `make documentation` - Generate Neovim documentation using mini.doc
- `make all` - Run documentation, lint, luals, and test

### Testing
- `make test-ci` - Install deps then run tests (for CI)
- `make test-nightly` - Test on Neovim nightly (requires bob)
- `make test-0.8.3` - Test on Neovim 0.8.3 (requires bob)

### Code Analysis
- `make luals` - Download and run Lua Language Server static analysis
- `make luals-ci` - Run static analysis (expects lua-language-server in PATH)

## Code Style

### StyLua Configuration (stylua.toml)
- Indent: 4 spaces
- Column width: 100
- Quote style: Auto-prefer double quotes
- Call parentheses: Required

### Testing Framework
Uses `mini.test` with:
- Test helper utilities in `tests/helpers.lua`
- Child Neovim process isolation for each test
- Minimal init script at `scripts/minimal_init.lua`

## Dependencies

### Runtime Dependencies
- Neovim (version constraints in CI: 0.9.x, 0.10.x, nightly)

### Development Dependencies
- [mini.nvim](https://github.com/echasnovski/mini.nvim) - For testing and documentation generation
- [StyLua](https://github.com/JohnnyMorganz/StyLua) - Lua code formatting
- [bob](https://github.com/MordechaiHadad/bob) - Neovim version manager (optional, for versioned testing)

## Related Libraries

### Available in Working Directories
- **nui.nvim** (`/Users/kyle/Code/nui.nvim/`) - UI Component Library for Neovim with components like Popup, Split, Input, Menu, Tree, Table, Text, Line
- **nui-components.nvim** (`/Users/kyle/Code/nui-components.nvim/`) - Advanced UI library built on nui.nvim with reactive components, state management (RxJS-style observables), and form validation

These libraries are useful for creating rich TUI interfaces in Neovim plugins and provide a solid foundation for UI development.

## UI Component Implementation Guidelines

### When Implementing UI Components
Always use the nui.nvim component framework instead of raw Neovim buffer/window APIs. The plugin should leverage these existing UI libraries for all interface elements.

### Basic UI Component Pattern
1. **Import NUI Components**: Use `require()` to import needed components (Split, Popup, Input, etc.)
2. **Store Component References**: Track component instances in plugin state for proper lifecycle management
3. **Mount/Unmount Lifecycle**: Use component `:mount()` and `:unmount()` methods in enable/disable functions
4. **Event Handling**: Set up component event handlers for user interactions

### Component Selection Guidelines
- **Split**: Use for main buffer windows, sidebars, or panel-style interfaces
- **Popup**: Use for dialogs, modals, or floating information displays
- **Input**: Use for text input forms and prompts
- **Menu**: Use for selection lists and option menus
- **Tree**: Use for hierarchical data display
- **Table**: Use for tabular data presentation

### Documentation References
Consult the comprehensive NUI documentation for implementation details and examples:

- **Component Documentation**: `/Users/kyle/Code/nui.nvim/lua/nui/{component}/README.md`
  - `split/README.md` - Window splitting (sidebars, panels)
  - `popup/README.md` - Floating windows and modals  
  - `input/README.md` - Text input fields
  - `menu/README.md` - Selection menus
  - `tree/README.md` - Hierarchical data display
  - `table/README.md` - Tabular data presentation

- **Additional Resources**: 
  - [NUI.nvim Wiki](https://github.com/MunifTanjim/nui.nvim/wiki) for guides and tips
  - Each component README includes comprehensive options and examples
  - All components follow the same mount/unmount lifecycle pattern

## Important Notes

- This is a template repository - all placeholder names (YourPluginName, your-plugin-name) need to be replaced
- The setup script automates the placeholder replacement process
- Tests must pass on multiple Neovim versions as defined in CI
- Documentation is auto-generated from code comments using mini.doc
- Plugin follows Neovim's standard plugin architecture patterns

- in order to install deps we need to `rm -rf deps/` then `make deps` or else new deps won't install

- The root cause of our repeated API issues was insufficient API documentation consultation. The pattern was
  consistently implementing methods that don't exist in nui.nvim instead of checking the actual documented API
  first.
