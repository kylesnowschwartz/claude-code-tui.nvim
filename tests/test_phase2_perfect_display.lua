---@brief [[
--- Phase 2: Perfect Content Display Strategy Tests
--- Tests the enhanced ContentClassifier with full Claude Code stream context
--- Validates that every content display decision is deterministically perfect
--- RED phase - these tests will fail until we implement the enhanced classifier
---@brief ]]

local Helpers = dofile("tests/helpers.lua")

-- Unit tests for Phase 2: Perfect Content Display Strategy - RED phase (failing tests)
local T = MiniTest.new_set()

-- Import required modules
local ContentClassifier = require("cc-tui.utils.content_classifier")
local StreamIntegrator = require("cc-tui.integration.claude_code_stream")

T["Perfect Display Strategy Tests"] = MiniTest.new_set()

T["Perfect Display Strategy Tests"]["tool inputs always get JSON popup - even if tiny"] = function()
    -- RED: Tool inputs should ALWAYS get popup treatment, regardless of size
    local small_tool_input_jsonl =
        [[{"type": "assistant", "message": {"content": [{"type": "tool_use", "id": "toolu_001", "name": "Read", "input": {"file_path": "/test.txt"}}]}}]]

    local parsed = StreamIntegrator.parse_jsonl_line(small_tool_input_jsonl)
    local tool_use_block = parsed.message.content[1]
    local input_text = vim.fn.json_encode(tool_use_block.input)

    -- Use enhanced classifier with full stream context
    local stream_context = {
        tool_use_id = tool_use_block.id,
        tool_name = tool_use_block.name,
        message_type = "assistant",
        is_tool_input = true,
    }

    local result = ContentClassifier.classify_with_stream_context(tool_use_block, input_text, stream_context)

    -- Tool inputs should ALWAYS use popup, even if tiny
    MiniTest.expect.equality(result.type, ContentClassifier.ContentType.TOOL_INPUT)
    MiniTest.expect.equality(result.display_strategy, "json_popup_always") -- Always popup for tool inputs
    MiniTest.expect.equality(result.force_popup, true) -- Force popup regardless of size
    MiniTest.expect.equality(result.metadata.tool_name, "Read")
end

T["Perfect Display Strategy Tests"]["small file content shows inline, large shows popup"] = function()
    -- RED: File content display should depend on size AND syntax highlighting needs
    local small_file_jsonl =
        [[{"type": "user", "message": {"content": [{"type": "tool_result", "tool_use_id": "toolu_002", "content": [{"type": "text", "text": "api_key=secret123\ndebug=true\nport=3000"}]}]}}]]

    local parsed = StreamIntegrator.parse_jsonl_line(small_file_jsonl)
    local tool_result_block = parsed.message.content[1]
    local content_text = tool_result_block.content[1].text

    -- Mock tool context (would come from linking)
    local stream_context = {
        tool_use_id = "toolu_002",
        tool_name = "Read",
        message_type = "user",
        is_tool_result = true,
        original_input = { file_path = "/config.env" },
    }
    tool_result_block.tool_name = "Read"

    local result = ContentClassifier.classify_with_stream_context(tool_result_block, content_text, stream_context)

    -- Small file content (3 lines, 34 chars) should show inline
    MiniTest.expect.equality(result.type, ContentClassifier.ContentType.FILE_CONTENT)
    MiniTest.expect.equality(result.display_strategy, "inline_with_syntax") -- Inline but with syntax hints
    MiniTest.expect.equality(result.force_popup, false)
    MiniTest.expect.equality(result.metadata.line_count, 3)
    MiniTest.expect.equality(result.metadata.file_type, "env") -- Detected from .env extension
end

T["Perfect Display Strategy Tests"]["large file content always gets popup with syntax highlighting"] = function()
    -- RED: Large file content should always get popup with proper syntax highlighting
    -- Use a simpler large file to avoid JSON escaping issues
    local large_file_jsonl =
        [[{"type": "user", "message": {"content": [{"type": "tool_result", "tool_use_id": "toolu_003", "content": [{"type": "text", "text": "import React, { useState } from 'react';\n\nconst UserProfile = ({ userId }) => {\n  const [user, setUser] = useState(null);\n  const [loading, setLoading] = useState(true);\n  const [error, setError] = useState(null);\n\n  // This is a large file with more than 5 lines\n  // It should trigger popup display with syntax highlighting\n  \n  return (\n    <div className=\"user-profile\">\n      <h1>{user?.name || 'Loading...'}</h1>\n      <p>{user?.email || 'No email'}</p>\n    </div>\n  );\n};\n\nexport default UserProfile;"}]}]}}]]

    local parsed = StreamIntegrator.parse_jsonl_line(large_file_jsonl)
    local tool_result_block = parsed.message.content[1]
    local content_text = tool_result_block.content[1].text

    local stream_context = {
        tool_use_id = "toolu_003",
        tool_name = "Read",
        message_type = "user",
        is_tool_result = true,
        original_input = { file_path = "/src/components/UserProfile.tsx" },
    }
    tool_result_block.tool_name = "Read"

    local result = ContentClassifier.classify_with_stream_context(tool_result_block, content_text, stream_context)

    -- Large file content should get popup with React/TypeScript syntax highlighting
    MiniTest.expect.equality(result.type, ContentClassifier.ContentType.FILE_CONTENT)
    MiniTest.expect.equality(result.display_strategy, "syntax_highlighted_popup")
    MiniTest.expect.equality(result.force_popup, true) -- Force popup due to size
    MiniTest.expect.equality(result.metadata.syntax_language, "typescript") -- Detected from .tsx
    MiniTest.expect.equality(result.metadata.line_count > 5, true)
end

T["Perfect Display Strategy Tests"]["bash output always gets terminal styling popup"] = function()
    -- RED: Bash output should ALWAYS get terminal popup, regardless of size
    local bash_jsonl =
        [[{"type": "user", "message": {"content": [{"type": "tool_result", "tool_use_id": "toolu_004", "content": [{"type": "text", "text": "test.txt\nscript.js\n"}]}]}}]]

    local parsed = StreamIntegrator.parse_jsonl_line(bash_jsonl)
    local tool_result_block = parsed.message.content[1]
    local content_text = tool_result_block.content[1].text

    local stream_context = {
        tool_use_id = "toolu_004",
        tool_name = "Bash",
        message_type = "user",
        is_tool_result = true,
        original_input = { command = "ls" },
    }
    tool_result_block.tool_name = "Bash"

    local result = ContentClassifier.classify_with_stream_context(tool_result_block, content_text, stream_context)

    -- Even small bash output should get terminal popup for consistency
    MiniTest.expect.equality(result.type, ContentClassifier.ContentType.COMMAND_OUTPUT)
    MiniTest.expect.equality(result.display_strategy, "terminal_style_popup")
    MiniTest.expect.equality(result.force_popup, true) -- Force popup for all bash output
    MiniTest.expect.equality(result.metadata.command, "ls")
    MiniTest.expect.equality(result.metadata.styling, "terminal")
end

T["Perfect Display Strategy Tests"]["JSON API responses get folding popup"] = function()
    -- RED: MCP/API JSON responses should get specialized JSON popup with folding
    local json_response =
        [[{"jsonrpc": "2.0", "id": 1, "result": {"content": [{"type": "text", "text": "# React Hooks\n\n## useState\n\nManages state in functional components..."}], "meta": {"total_docs": 47, "filtered": 12}}}]]

    local api_jsonl = string.format(
        [[{"type": "user", "message": {"content": [{"type": "tool_result", "tool_use_id": "toolu_005", "content": [{"type": "text", "text": %q}]}]}}]],
        json_response
    )

    local parsed = StreamIntegrator.parse_jsonl_line(api_jsonl)
    local tool_result_block = parsed.message.content[1]
    local content_text = tool_result_block.content[1].text

    local stream_context = {
        tool_use_id = "toolu_005",
        tool_name = "mcp__context7__get-library-docs",
        message_type = "user",
        is_tool_result = true,
        is_mcp_tool = true,
        original_input = { library = "react", topic = "hooks" },
    }
    tool_result_block.tool_name = "mcp__context7__get-library-docs"

    local result = ContentClassifier.classify_with_stream_context(tool_result_block, content_text, stream_context)

    -- JSON API responses should get specialized folding popup
    MiniTest.expect.equality(result.type, ContentClassifier.ContentType.JSON_API_RESPONSE)
    MiniTest.expect.equality(result.display_strategy, "json_popup_with_folding")
    MiniTest.expect.equality(result.force_popup, true)
    MiniTest.expect.equality(result.metadata.api_source, "mcp__context7__get-library-docs")
    MiniTest.expect.equality(result.metadata.has_nested_structure, true)
end

T["Perfect Display Strategy Tests"]["error content gets error popup styling"] = function()
    -- RED: Error content should get specialized error popup
    local error_content = "Error: ENOENT: no such file or directory, open '/missing/file.txt'"
    local error_jsonl = string.format(
        [[{"type": "user", "message": {"content": [{"type": "tool_result", "tool_use_id": "toolu_006", "is_error": true, "content": [{"type": "text", "text": %q}]}]}}]],
        error_content
    )

    local parsed = StreamIntegrator.parse_jsonl_line(error_jsonl)
    local tool_result_block = parsed.message.content[1]
    local content_text = tool_result_block.content[1].text

    local stream_context = {
        tool_use_id = "toolu_006",
        tool_name = "Read",
        message_type = "user",
        is_tool_result = true,
        is_error = true,
        original_input = { file_path = "/missing/file.txt" },
    }
    tool_result_block.tool_name = "Read"
    tool_result_block.is_error = true

    local result = ContentClassifier.classify_with_stream_context(tool_result_block, content_text, stream_context)

    -- Error content should get specialized error popup
    MiniTest.expect.equality(result.type, ContentClassifier.ContentType.ERROR_CONTENT)
    MiniTest.expect.equality(result.display_strategy, "error_popup_highlighted")
    MiniTest.expect.equality(result.force_popup, true) -- Errors always popup
    MiniTest.expect.equality(result.metadata.error_type, "file_not_found")
    MiniTest.expect.equality(result.metadata.styling, "error_highlight")
end

T["Enhanced ContentClassifier API"] = MiniTest.new_set()

T["Enhanced ContentClassifier API"]["classify_with_stream_context provides full context"] = function()
    -- RED: Test the new enhanced API that takes full stream context
    local tool_use_block = {
        type = "tool_use",
        id = "toolu_api_test",
        name = "Write",
        input = { file_path = "/src/config.js", content = "const API_URL = 'https://api.com';" },
    }

    local input_text = vim.fn.json_encode(tool_use_block.input)

    local stream_context = {
        tool_use_id = "toolu_api_test",
        tool_name = "Write",
        message_type = "assistant",
        is_tool_input = true,
        session_id = "test-session",
        original_command = "claude code 'write a config file'",
    }

    -- This API doesn't exist yet - will fail
    local result = ContentClassifier.classify_with_stream_context(tool_use_block, input_text, stream_context)

    MiniTest.expect.equality(result.type, ContentClassifier.ContentType.TOOL_INPUT)
    MiniTest.expect.equality(result.confidence, 1.0) -- Still deterministic
    MiniTest.expect.equality(result.metadata.enhanced_context, true) -- Has stream context
    MiniTest.expect.equality(result.metadata.session_id, "test-session")
    MiniTest.expect.equality(result.display_strategy, "json_popup_always")
end

T["Enhanced ContentClassifier API"]["should_use_rich_display_with_context considers tool type"] = function()
    -- RED: Test enhanced rich display logic that considers tool context
    local content = "console.log('Hello World');"

    -- Same content, different tools should get different display strategies

    -- As file content from Read tool
    local file_context = {
        tool_name = "Read",
        is_tool_result = true,
        original_input = { file_path = "/src/hello.js" },
    }

    local file_decision = ContentClassifier.should_use_rich_display_with_context(content, file_context)
    MiniTest.expect.equality(file_decision.use_popup, false) -- Small file content can be inline
    MiniTest.expect.equality(file_decision.display_strategy, "inline_with_syntax")

    -- As command output from Bash tool
    local bash_context = {
        tool_name = "Bash",
        is_tool_result = true,
        original_input = { command = "cat hello.js" },
    }

    local bash_decision = ContentClassifier.should_use_rich_display_with_context(content, bash_context)
    MiniTest.expect.equality(bash_decision.use_popup, true) -- Bash output always popup
    MiniTest.expect.equality(bash_decision.display_strategy, "terminal_style_popup")
end

return T
