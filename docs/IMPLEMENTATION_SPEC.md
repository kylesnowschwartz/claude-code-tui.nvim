# Cc-Tui Implementation Specification

## Goal: Collapsible Tool Output Tree for Claude Code

Transform Claude Code's streaming output into a navigable, collapsible tree structure within Neovim.

---

## Data Format: Claude Code Streaming JSON

### Command to Capture

```bash
claude -p "prompt" --output-format stream-json
```

### JSONL Structure (Line-Delimited JSON)

Each line is a complete JSON object with one of these types:

#### 1. System Messages

```json
{"type": "system", "subtype": "init", "session_id": "uuid", "tools": [...]}
{"type": "result", "subtype": "success", "session_id": "uuid", "total_cost_usd": 0.123}
```

#### 2. Assistant Messages

```json
{
  "type": "assistant",
  "message": {
    "id": "msg_xxx",
    "role": "assistant",
    "content": [
      {"type": "text", "text": "I'll help you..."},
      {"type": "tool_use", "id": "toolu_xxx", "name": "Read", "input": {...}}
    ]
  },
  "session_id": "uuid"
}
```

#### 3. User/Tool Results

```json
{
  "type": "user",
  "message": {
    "role": "user",
    "content": [
      {"tool_use_id": "toolu_xxx", "type": "tool_result", "content": [...]}
    ]
  },
  "session_id": "uuid"
}
```

### Key Observations

- Tool uses have unique IDs (`toolu_*`) that link to their results
- Messages can contain multiple content blocks
- Session ID tracks the conversation
- MCP tools are prefixed: `mcp__server__tool`

---

## UI Structure: Collapsible Tree

### Visual Layout

```
▼ Session: 16368255-989b-4b2d-af5c [14:23:15]
  ▼ Assistant: "I'll help you fix this issue..."
    ▼ Tool: Read [package.json]
      │ {
      │   "name": "my-project",
      │   "version": "1.0.0"
      │ }
    ▶ Tool: Bash [npm install]
    ▼ Tool: Edit [src/main.js]
      │ - const old = "value"
      │ + const new = "updated"
    ▼ Tool: Task [implementation-specialist]
      ▶ Sub-tool: Write [helper.js]
      ▶ Sub-tool: Edit [main.js]
  ▶ Assistant: "The changes have been completed..."
```

### Tree Node Types

1. **Session Node** - Root level, shows session ID and start time
2. **Message Node** - Assistant messages with text preview
3. **Tool Node** - Tool invocations with name and primary argument
4. **Result Node** - Tool output (collapsible child of Tool Node)

### Node States

- `▼` Expanded (showing children)
- `▶` Collapsed (hiding children)
- `│` Content line (non-interactive)

---

## Implementation Components

### 1. Stream Parser (`lua/cc-tui/parser/stream.lua`)

```lua
-- Parse JSONL stream into structured data
function M.parse_line(line)
  -- Parse single JSON line
  -- Return typed message object
end

function M.build_tree(messages)
  -- Link tool_use with tool_result via IDs
  -- Create hierarchical structure
  -- Handle nested tools (Task calling sub-tools)
end
```

### 2. Tree Component (`lua/cc-tui/ui/tree.lua`)

```lua
-- Use nui.nvim Tree for rendering
local Tree = require("nui.tree")

function M.create_tree(data)
  -- Convert parsed data to Tree nodes
  -- Set up expand/collapse handlers
  -- Apply syntax highlighting
end
```

### 3. Main Window (`lua/cc-tui/init.lua`)

```lua
-- Main plugin entry point
local Split = require("nui.split")

function M.setup(opts)
  -- Configure keybindings
  -- Set up autocmds for stream capture
end

function M.toggle()
  -- Show/hide the tree window
end
```

### 4. Keybindings

```lua
-- Vim-style navigation
{
  ["<Space>"] = "toggle_node",     -- Expand/collapse
  ["za"] = "toggle_node",          -- Vim fold toggle
  ["zM"] = "collapse_all",         -- Collapse entire tree
  ["zR"] = "expand_all",           -- Expand entire tree
  ["j"] = "next_node",              -- Move down
  ["k"] = "prev_node",              -- Move up
  ["<CR>"] = "copy_content",       -- Copy node content
  ["q"] = "close_window"           -- Close the tree
}
```

---

## File Structure

```
cc-tui.nvim/
├── lua/cc-tui/
│   ├── init.lua           -- Main plugin entry
│   ├── config.lua          -- Configuration defaults
│   ├── parser/
│   │   └── stream.lua      -- JSONL parser
│   ├── ui/
│   │   ├── tree.lua        -- Tree component
│   │   └── window.lua      -- Window management
│   └── utils/
│       └── highlights.lua  -- Syntax highlighting
├── plugin/
│   └── cc-tui.lua          -- Vim command registration
└── docs/
    ├── IMPLEMENTATION_SPEC.md  -- This file
    ├── FIRST_BIG_WIN.md        -- Product vision
    └── visual-mockup.txt       -- UI mockup
```

---

## Development Priorities

### Phase 1: Core Parser (Must Have)

- [ ] Parse JSONL stream format
- [ ] Link tool_use with tool_result
- [ ] Build hierarchical data structure

### Phase 2: Basic Tree Display (Must Have)

- [ ] Render tree with nui.nvim
- [ ] Implement expand/collapse
- [ ] Add vim keybindings

### Phase 3: Polish (Nice to Have)

- [ ] Syntax highlighting for code
- [ ] Copy content to clipboard
- [ ] Auto-expand errors
- [ ] Search within tree

---

## Success Criteria

1. Can parse real Claude Code `--output-format stream-json` output
2. Displays collapsible tree with tool hierarchy
3. Navigation time reduced from 30+ seconds to <3 seconds
4. Works with standard vim fold commands

---

## Notes

- Focus on official CLI behavior, not TypeScript SDK
- Handle both regular tools and MCP tools (`mcp__server__tool`)
- Tree should update incrementally as stream arrives
- Preserve fold state when new messages arrive
