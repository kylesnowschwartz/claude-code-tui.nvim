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

## Development Commands

### Setup and Installation
- `make setup` - Interactive setup script to replace placeholder names
- `USERNAME=user PLUGIN_NAME=name REPOSITORY_NAME=repo.nvim make setup` - Automated setup

### Core Development
- `make deps` - Install mini.nvim dependency for docs and tests
- `make lint` - Format code with StyLua and run luacheck
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

## Important Notes

- This is a template repository - all placeholder names (YourPluginName, your-plugin-name) need to be replaced
- The setup script automates the placeholder replacement process
- Tests must pass on multiple Neovim versions as defined in CI
- Documentation is auto-generated from code comments using mini.doc
- Plugin follows Neovim's standard plugin architecture patterns

- in order to install deps we need to `rm -rf deps/` then `make deps` or else new deps won't install
