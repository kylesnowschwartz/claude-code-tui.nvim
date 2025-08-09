# Cc-Tui: First Big Win - Toggleable Dropdowns

## The Core Problem

Claude Code's terminal output cascades in an overwhelming wall of text, making it impossible to:

- Scan for relevant information quickly
- Navigate between different tool outputs
- Focus on specific sections without distraction

## The Solution: Collapsible Tool Output Tree

Transform Claude Code's linear output into an organized, collapsible tree structure:

```
▼ Claude Response [2024-01-09 14:23:15]
  ▼ Bash: npm install
    │ added 152 packages in 12.3s
    │ found 0 vulnerabilities
  ▶ Read: package.json
  ▼ Edit: src/main.js
    │ - const old = "value"
    │ + const new = "updated"
  ▶ Task: implementation-specialist
```

example: `visual-mockup.txt`

### Key Features

- **Toggle with `<Space>`**: Collapse/expand any section
- **Tool Frames**: Each tool gets a bordered frame with status
- **Vim Navigation**: Use `j/k` to move, `zo/zc` to fold
- **Visual Hierarchy**: Clear parent-child relationships for nested tools

### Implementation Focus

1. **JSON Parser**: Parse Claude Code's `--output-format stream-json` output
2. **Tree Component**: Use nui.nvim Tree with custom rendering
3. **Main Window**: Split pane displaying the collapsible tree

### Success Metric

**Reduce time to find specific tool output from 30+ seconds (scrolling) to <3 seconds (direct navigation)**

### Technical Requirements

- Parse JSONL format from Claude Code CLI
- Build hierarchical data structure from tool calls
- Render collapsible tree with vim-style keybindings
- Handle tool nesting (Task agents calling sub-tools)

This single feature solves the #1 user pain point: making Claude Code's output scannable and navigable within Neovim.
