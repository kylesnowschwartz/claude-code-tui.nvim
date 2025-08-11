# CC-TUI Enhancements from Claude Code Statusline API

## Overview
The Claude Code statusline API documentation reveals internal conversation tracking mechanisms that can significantly improve cc-tui's conversation discovery and display capabilities.

## Key API Discoveries

### 1. Direct Current Conversation Path
The statusline API provides `transcript_path` - the exact path to the current conversation file:
- Eliminates guessing which conversation is active
- No need to scan for most recently modified files
- Direct link to the active conversation JSONL file
- Can definitively highlight/mark current conversation in Browse view

### 2. Session ID Correlation
The `session_id` field in statusline JSON matches `sessionId` in JSONL files:
- Enables precise filtering of messages by session
- Can track conversation continuations across multiple files
- Identifies related conversation chains
- Allows grouping of related sessions

### 3. Metadata Field Consistency
Fields like `cwd`, `model.id`, and `gitBranch` appear in both statusline and JSONL:
- Provides patterns for better metadata extraction
- Can display model information in conversation tree headers
- Shows git context for each conversation
- Working directory tracking for project context

## Proposed Enhancements

### Enhancement 1: Current Conversation Detection Service
Create a new service to read Claude Code's active state:

```lua
-- New file: lua/cc-tui/services/claude_state.lua
-- Purpose: Interface with Claude Code's state management
-- Key functions:
--   - getCurrentConversation() - returns path to active JSONL
--   - getCurrentSession() - returns active session_id
--   - getModelInfo() - returns current model details
--   - isConversationActive(path) - checks if conversation is current
```

**Implementation approach:**
- Look for Claude Code state files in `~/.claude/` directory
- Parse state files to extract `transcript_path` and `session_id`
- Cache state with file watcher for updates
- Fallback to timestamp-based detection if state files unavailable

### Enhancement 2: Browse View Current Conversation Marking
Improve the Browse tab to highlight the active conversation:

**Visual indicators:**
- `●` indicator for currently active conversation
- Different highlight group for current vs historical
- Auto-select current conversation when opening Browse tab
- Sort with current conversation always at top (optional)

**Implementation:**
- Modify `lua/cc-tui/ui/views/browse.lua` to check current state
- Add highlight group `CcTuiCurrentConversation`
- Update list rendering to apply indicators
- Add keybinding to jump to current (e.g., `gc` for "go to current")

### Enhancement 3: Enhanced Metadata Display
Add statusline-inspired metadata throughout the UI:

**Conversation Tree Header:**
```
═══ Claude Code - Opus 4.1 | main | ~/Code/cc-tui.nvim ═══
Session: 10122a00-5972-40f9-bb6d-41a4ba8178db
```

**Browse List Entry Format:**
```
● [Current] 2025-08-11 14:23 - Opus - "Statusline API exploration"
  2025-08-11 09:15 - Sonnet - "Fix tree rendering issue"  
  2025-08-10 22:47 - Opus - "Add test coverage"
```

**Implementation:**
- Extend metadata extraction in `lua/cc-tui/services/metadata_extractor.lua`
- Update formatters to include model and git info
- Add model name mapping (e.g., "claude-opus-4-1" → "Opus")

### Enhancement 4: Live Conversation Following
If Claude Code exposes real-time state:

**Features:**
- Auto-refresh when conversation changes
- Follow active conversation in real-time
- "LIVE" indicator for active sessions
- Auto-scroll to latest messages

**Implementation approach:**
- File watcher on conversation JSONL files
- Poll for size changes to detect new messages
- Debounced refresh (300ms like statusline)
- Optional auto-follow mode toggle

### Enhancement 5: Session Continuity Tracking
Leverage session IDs to show conversation relationships:

**Features:**
- Group conversations by session
- Show session continuation indicators
- Track conversation "threads" across multiple files
- Display session duration and message counts

**Visual representation:**
```
Session: abc-123 (3 conversations, 2h 15m)
├─ conv1.jsonl - "Initial implementation"
├─ conv2.jsonl - "Bug fixes" (continuation)
└─ conv3.jsonl - "Performance optimization" (continuation)
```

## Implementation Priority

1. **High Priority:** Current conversation detection (Enhancement 1)
   - Immediate UX improvement
   - Foundation for other features
   
2. **High Priority:** Browse view marking (Enhancement 2)
   - Clear visual feedback
   - Minimal implementation effort

3. **Medium Priority:** Enhanced metadata (Enhancement 3)
   - Rich context information
   - Improves conversation management

4. **Low Priority:** Live following (Enhancement 4)
   - Advanced feature
   - Requires more complex implementation

5. **Low Priority:** Session continuity (Enhancement 5)
   - Nice-to-have for power users
   - Requires significant UI changes

## Technical Considerations

### State File Discovery
Need to investigate where Claude Code stores its state:
- Check `~/.claude/` for state files
- Look for files containing `transcript_path`
- May need to reverse-engineer from statusline script execution

### Backward Compatibility
- Maintain fallback to timestamp-based detection
- Gracefully handle missing state files
- Support older Claude Code versions without statusline API

### Performance
- Cache state file reads
- Debounce file watchers
- Lazy-load metadata for large conversation lists

## Next Steps

1. Investigate Claude Code's state file location and format
2. Implement getCurrentConversation() detection
3. Add current conversation marking to Browse view
4. Extend metadata extraction for new fields
5. Consider live update mechanisms

## References
- Claude Code statusline documentation: https://docs.anthropic.com/en/docs/claude-code/statusline
- Statusline JSON structure provides: session_id, transcript_path, model info, cwd, gitBranch
- JSONL files contain matching sessionId fields for correlation