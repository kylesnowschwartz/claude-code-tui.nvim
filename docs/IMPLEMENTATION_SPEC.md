# Cc-Tui Implementation Specification

## Goal: Collapsible Tool Output Tree for Claude Code

Transform Claude Code's streaming output into a navigable, collapsible tree structure within Neovim.

---

## Data Format: Claude Code Conversation JSONL

### Source: Real Claude Code Conversation Files

Claude Code stores conversations as JSONL files in `~/.claude/projects/PROJECT_NAME/UUID.jsonl`. Each line contains a complete JSON object representing a message or event in the conversation.

### JSONL Structure (Line-Delimited JSON)

Each line is a complete JSON object with these top-level fields:

#### Common Message Fields

All messages contain:
- `parentUuid`: Links to previous message (null for first message)
- `isSidechain`: Boolean flag for conversation branching
- `userType`: "external" for user interactions
- `cwd`: Current working directory
- `sessionId`: UUID for conversation session
- `version`: Claude CLI version (e.g., "1.0.72")
- `gitBranch`: Current git branch
- `type`: "assistant" or "user"
- `message`: The actual message content
- `uuid`: Unique message identifier
- `timestamp`: ISO timestamp
- `requestId`: Request identifier (present on assistant messages)

#### 1. User Messages

User messages come in three variants:

**Direct Text Input:**
```json
{
  "parentUuid": "prev-uuid-here",
  "isSidechain": false,
  "userType": "external",
  "cwd": "/Users/kyle/Code/project",
  "sessionId": "16368255-989b-4b2d-af5c-123456789abc",
  "version": "1.0.72",
  "gitBranch": "main",
  "type": "user",
  "message": {
    "role": "user",
    "content": "Help me fix this bug in my code"
  },
  "uuid": "user-message-uuid",
  "timestamp": "2024-12-18T22:23:15.000Z"
}
```

**Tool Results:**
```json
{
  "parentUuid": "assistant-uuid-here",
  "isSidechain": false,
  "userType": "external",
  "cwd": "/Users/kyle/Code/project",
  "sessionId": "16368255-989b-4b2d-af5c-123456789abc",
  "version": "1.0.72",
  "gitBranch": "main",
  "type": "user",
  "message": {
    "role": "user",
    "content": [
      {
        "tool_use_id": "toolu_01ABC123DEF456",
        "type": "tool_result",
        "content": "File content here..."
      }
    ]
  },
  "uuid": "tool-result-uuid",
  "timestamp": "2024-12-18T22:23:16.000Z",
  "toolUseResult": true
}
```

**SimpleClaude Commands:**
```json
{
  "type": "user",
  "message": {
    "role": "user", 
    "content": "<command-args>\n  <command>search</command>\n  <query>function definition</query>\n</command-args>"
  },
  // ... other fields
}
```

#### 2. Assistant Messages

Assistant messages contain tool uses and responses:

```json
{
  "parentUuid": "user-uuid-here",
  "isSidechain": false,
  "userType": "external", 
  "cwd": "/Users/kyle/Code/project",
  "sessionId": "16368255-989b-4b2d-af5c-123456789abc",
  "version": "1.0.72",
  "gitBranch": "main",
  "type": "assistant",
  "message": {
    "id": "msg_01ABC123DEF456GHI",
    "role": "assistant",
    "model": "claude-sonnet-4-20250514",
    "content": [
      {
        "type": "text",
        "text": "I'll help you fix this issue. Let me first read the file."
      },
      {
        "type": "tool_use",
        "id": "toolu_01ABC123DEF456",
        "name": "Read",
        "input": {
          "file_path": "/Users/kyle/Code/project/src/main.js"
        }
      }
    ],
    "usage": {
      "input_tokens": 1234,
      "output_tokens": 567,
      "cache_creation_input_tokens": null,
      "cache_read_input_tokens": null
    },
    "stop_reason": "tool_use"
  },
  "uuid": "assistant-message-uuid",
  "timestamp": "2024-12-18T22:23:15.500Z",
  "requestId": "req_01XYZ789ABC123"
}
```

### Content Format Variations

#### User Content Types
1. **String Content**: Direct text as simple string
2. **Array Content**: Tool results with `tool_use_id` and `tool_result` structure
3. **Command Content**: XML-like SimpleClaude command format

#### Assistant Content Types
1. **Text Blocks**: `{"type": "text", "text": "..."}`
2. **Tool Use Blocks**: `{"type": "tool_use", "id": "toolu_xxx", "name": "ToolName", "input": {...}}`

### Tool Use Linking

Tool uses are linked to their results via IDs:
- Assistant message contains: `{"type": "tool_use", "id": "toolu_01ABC123DEF456", ...}`
- Following user message contains: `{"tool_use_id": "toolu_01ABC123DEF456", "type": "tool_result", ...}`
- User messages with tool results have `"toolUseResult": true` flag

### Parsing Requirements and Edge Cases

#### Critical Parsing Rules
1. **User Content Format Detection**:
   - `typeof(message.content) === 'string'` → Direct text input
   - `Array.isArray(message.content)` → Tool results or structured content
   - Check for `toolUseResult: true` flag to identify tool result messages

2. **Tool Use Linking**:
   - Assistant messages contain `tool_use` objects with unique `id` field
   - User messages contain `tool_result` objects with matching `tool_use_id` field
   - Link these via ID matching to build tool execution chains

3. **Conversation Threading**:
   - Use `parentUuid` to establish message order and relationships
   - First message in conversation has `parentUuid: null`
   - Build conversation tree from these parent-child relationships

4. **Metadata Extraction**:
   - Conversation title: First user message content (truncated for display)
   - Message count: Total messages in conversation
   - Context: Extract `cwd`, `gitBranch`, `version` from any message

#### Edge Cases to Handle

1. **SimpleClaude Commands**: XML-like content starting with `<command-args>`
2. **Empty Tool Results**: Some tool results may have empty or null content
3. **Large JSON Payloads**: Tool inputs/outputs can be very large JSON objects
4. **Unicode Content**: File contents may contain special characters
5. **Malformed JSON**: Handle parsing errors gracefully
6. **Missing Fields**: Some messages may lack optional fields like `gitBranch`
7. **Nested MCP Tools**: Tools calling other tools create deeper hierarchies

### Key Observations

- **No session-level initialization**: Conversations start directly with user/assistant messages
- **Rich metadata**: Every message includes git branch, working directory, CLI version
- **Conversation threading**: `parentUuid` creates message chains
- **Mixed content formats**: User content can be string OR array depending on context
- **MCP tools**: Prefixed with `mcp__server__tool` pattern
- **Tool result metadata**: Additional fields like `toolUseResult` flag for parsing
- **SimpleClaude integration**: Special XML-like command format for CLI shortcuts

---

## UI Structure: Collapsible Tree

### Visual Layout

```
▼ Session: 16368255-989b-4b2d-af5c [14:23:15]
  ▼ Assistant: "I'll help you fix this issue..."
    ▼ Tool: Read [package.json]
      ▼ Result: +25 lines (expand to view) ← Shows popup when toggled
    ▶ Tool: Bash [npm install] 
      ▶ Result: Command output (8 lines) ← Shows popup when toggled
    ▼ Tool: mcp__context7__get-library-docs
      ▼ Result: API response (169 lines) ← Shows popup when toggled
    ▼ Tool: Edit [src/main.js]
      ▼ Result: File content ← Small result, shows inline
        │ - const old = "value"
        │ + const new = "updated"
  ▶ Assistant: "The changes have been completed..."
```

### Content Display Rules

**CRITICAL**: Every expandable node MUST show actual content when toggled.

#### Small Content (≤5 lines, ≤200 chars)
- Displays inline as tree children
- Immediate visibility in tree structure
- No popup required

#### Large Content (>5 lines OR >200 chars OR JSON)
- Shows descriptive summary when collapsed: "API response (169 lines)"
- **When toggled**: Opens popup window with full content
- Popup features:
  - Syntax highlighting (JSON, code, shell output)
  - Scrollable interface
  - Quick close (q/Esc keys)
  - Proper window sizing

#### Content Categories
1. **JSON Data** → Always popup with json syntax highlighting
2. **File Content** → Popup with file-type syntax highlighting  
3. **Command Output** → Popup with shell highlighting
4. **API Responses** → Popup with appropriate formatting
5. **Text Messages** → Inline if small, popup if large

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

### 1. Conversation Parser (`lua/cc-tui/parser/conversation.lua`)

```lua
-- Parse Claude Code conversation JSONL files
function M.parse_line(line)
  -- Parse single JSON line from conversation file
  -- Handle both string and array content formats for user messages
  -- Extract metadata: parentUuid, sessionId, timestamp, etc.
  -- Return structured message object with type detection
end

function M.parse_conversation_file(file_path)
  -- Read entire JSONL conversation file
  -- Parse each line and build message chain using parentUuid
  -- Extract conversation metadata for titles and navigation
  -- Return structured conversation data
end

function M.build_tool_tree(messages)
  -- Link tool_use with tool_result via IDs (toolu_*)
  -- Create hierarchical structure from message chain
  -- Handle mixed content formats (string vs array)
  -- Handle MCP tools with mcp__server__tool pattern
  -- Detect SimpleClaude commands with XML-like format
end

function M.extract_metadata(messages)
  -- Extract conversation title from first user message
  -- Count messages for navigation display
  -- Detect conversation context (cwd, gitBranch, version)
  -- Return metadata for UI display
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
│   ├── init.lua              -- Main plugin entry
│   ├── config.lua            -- Configuration defaults
│   ├── parser/
│   │   └── conversation.lua  -- JSONL conversation parser
│   ├── services/
│   │   └── project_discovery.lua  -- Find and parse conversation files
│   ├── ui/
│   │   ├── tree.lua          -- Tree component
│   │   ├── window.lua        -- Window management
│   │   └── browser.lua       -- Conversation browser
│   └── utils/
│       └── highlights.lua    -- Syntax highlighting
├── plugin/
│   └── cc-tui.lua            -- Vim command registration
└── docs/
    ├── IMPLEMENTATION_SPEC.md  -- This file
    ├── FIRST_BIG_WIN.md        -- Product vision
    └── visual-mockup.txt       -- UI mockup
```

---

## Development Priorities

### Phase 1: Conversation Parser (Must Have)

- [ ] Parse Claude Code JSONL conversation files from `~/.claude/projects/`
- [ ] Handle mixed user content formats (string vs array)
- [ ] Link tool_use with tool_result via IDs (toolu_*)
- [ ] Build hierarchical tool execution trees
- [ ] Extract conversation metadata (title, message count, context)
- [ ] Handle edge cases (SimpleClaude commands, malformed JSON, Unicode)

### Phase 2: Basic Tree Display (Must Have)

- [ ] Render conversation tree with nui.nvim
- [ ] Implement expand/collapse for tool results
- [ ] Add vim keybindings for navigation
- [ ] Display conversation metadata in tree nodes
- [ ] Show tool execution hierarchy properly

### Phase 3: Conversation Browser (High Priority)

- [ ] List available conversations from project directories
- [ ] Show conversation titles and message counts
- [ ] Navigate between different conversations
- [ ] Filter conversations by project or date

### Phase 4: Polish (Nice to Have)

- [ ] Syntax highlighting for code and JSON
- [ ] Copy content to clipboard
- [ ] Auto-expand errors and important results
- [ ] Search within conversations
- [ ] Export conversation summaries

---

## Success Criteria

1. Can parse real Claude Code conversation JSONL files from `~/.claude/projects/`
2. Correctly handles mixed user content formats (string vs array)
3. Successfully links tool uses to their results via ID matching
4. Displays collapsible tree with complete tool execution hierarchy
5. Navigation time reduced from 30+ seconds to <3 seconds
6. Works with standard vim fold commands and navigation
7. Prevents parsing bugs by handling all documented edge cases

---

## Notes

- **Data Source**: Parse stored conversation files, not live streaming
- **Format Accuracy**: Implementation must match real JSONL format exactly
- **Edge Case Handling**: Critical for preventing parser bugs and crashes  
- **Tool Hierarchy**: Handle both regular tools and MCP tools (`mcp__server__tool`)
- **Content Variation**: Support SimpleClaude commands, direct text, and tool results
- **Metadata Rich**: Leverage conversation context (cwd, branch, version) for better UX
- **Threading**: Use `parentUuid` chains to maintain conversation flow
- **Robustness**: Handle malformed JSON, missing fields, and Unicode content gracefully
