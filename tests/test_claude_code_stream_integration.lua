---@brief [[
--- Tests for Claude Code JSONL stream integration with deterministic ContentClassifier
--- Validates parsing of real Claude Code --output-format stream-json data
--- Uses official Claude Code streaming JSON format from IMPLEMENTATION_SPEC.md
---@brief ]]

local Helpers = dofile("tests/helpers.lua")

-- Unit tests for Claude Code stream integration - RED phase (failing tests)
local T = MiniTest.new_set()

-- Import required modules (will create these)
local StreamIntegrator
local ContentClassifier

T["Claude Code Stream Integration Loading"] = MiniTest.new_set()

T["Claude Code Stream Integration Loading"]["loads StreamIntegrator without error"] = function()
    -- RED: This will fail initially since module doesn't exist yet
    local ok, integrator = pcall(require, "cc-tui.integration.claude_code_stream")
    MiniTest.expect.equality(ok, true)
    MiniTest.expect.equality(type(integrator), "table")
    StreamIntegrator = integrator
end

T["Claude Code Stream Integration Loading"]["loads ContentClassifier"] = function()
    local ok, classifier = pcall(require, "cc-tui.utils.content_classifier")
    MiniTest.expect.equality(ok, true)
    ContentClassifier = classifier
end

T["JSONL Parsing"] = MiniTest.new_set()

T["JSONL Parsing"]["parses system init message from Claude Code"] = function()
    -- RED: Real Claude Code system message format from IMPLEMENTATION_SPEC.md
    local jsonl_line =
        '{"type": "system", "subtype": "init", "session_id": "16368255-989b-4b2d-af5c", "tools": ["Read", "Write", "Bash"], "model": "claude-3-5-sonnet-20241022"}'

    local parsed = StreamIntegrator.parse_jsonl_line(jsonl_line)
    MiniTest.expect.equality(parsed.type, "system")
    MiniTest.expect.equality(parsed.subtype, "init")
    MiniTest.expect.equality(parsed.session_id, "16368255-989b-4b2d-af5c")
    MiniTest.expect.equality(type(parsed.tools), "table")
end

T["JSONL Parsing"]["parses assistant message with tool_use"] = function()
    -- RED: Real Claude Code assistant message with tool_use from IMPLEMENTATION_SPEC.md
    local jsonl_line =
        [[{"type": "assistant", "message": {"id": "msg_123", "role": "assistant", "content": [{"type": "text", "text": "I'll help you read the file."}, {"type": "tool_use", "id": "toolu_abc123", "name": "Read", "input": {"file_path": "/tmp/test.txt"}}]}, "session_id": "16368255-989b-4b2d-af5c"}]]

    local parsed = StreamIntegrator.parse_jsonl_line(jsonl_line)
    MiniTest.expect.equality(parsed.type, "assistant")
    MiniTest.expect.equality(parsed.message.id, "msg_123")
    MiniTest.expect.equality(type(parsed.message.content), "table")

    -- Find the tool_use content block
    local tool_use_block = nil
    for _, content in ipairs(parsed.message.content) do
        if content.type == "tool_use" then
            tool_use_block = content
            break
        end
    end

    MiniTest.expect.equality(tool_use_block.type, "tool_use")
    MiniTest.expect.equality(tool_use_block.name, "Read")
    MiniTest.expect.equality(tool_use_block.id, "toolu_abc123")
end

T["JSONL Parsing"]["parses user message with tool_result"] = function()
    -- RED: Real Claude Code tool result message from IMPLEMENTATION_SPEC.md
    local jsonl_line =
        [[{"type": "user", "message": {"role": "user", "content": [{"tool_use_id": "toolu_abc123", "type": "tool_result", "content": [{"type": "text", "text": "function hello() {\n  console.log('Hello World');\n}"}]}]}, "session_id": "16368255-989b-4b2d-af5c"}]]

    local parsed = StreamIntegrator.parse_jsonl_line(jsonl_line)
    MiniTest.expect.equality(parsed.type, "user")
    MiniTest.expect.equality(type(parsed.message.content), "table")

    -- Find the tool_result content block
    local tool_result_block = nil
    for _, content in ipairs(parsed.message.content) do
        if content.type == "tool_result" then
            tool_result_block = content
            break
        end
    end

    MiniTest.expect.equality(tool_result_block.type, "tool_result")
    MiniTest.expect.equality(tool_result_block.tool_use_id, "toolu_abc123")
end

T["Deterministic Classification Integration"] = MiniTest.new_set()

T["Deterministic Classification Integration"]["classifies tool_use with 100% accuracy"] = function()
    -- RED: Integration test - parse JSONL then classify deterministically
    local jsonl_line =
        [[{"type": "assistant", "message": {"content": [{"type": "tool_use", "id": "toolu_read_001", "name": "Read", "input": {"file_path": "/src/main.js"}}]}}]]

    local parsed = StreamIntegrator.parse_jsonl_line(jsonl_line)
    local tool_use_block = parsed.message.content[1]
    local content_text = vim.fn.json_encode(tool_use_block.input)

    local result = ContentClassifier.classify_from_structured_data(tool_use_block, content_text)

    MiniTest.expect.equality(result.type, ContentClassifier.ContentType.TOOL_INPUT)
    MiniTest.expect.equality(result.confidence, 1.0) -- 100% deterministic
    MiniTest.expect.equality(result.metadata.tool_name, "Read")
    MiniTest.expect.equality(result.metadata.structured_source, true)
end

T["Deterministic Classification Integration"]["classifies tool_result with context awareness"] = function()
    -- RED: Test tool result classification using structured data
    local jsonl_line =
        [[{"type": "user", "message": {"content": [{"type": "tool_result", "tool_use_id": "toolu_read_001", "content": [{"type": "text", "text": "export const API_URL = 'https://api.example.com';\nexport default API_URL;"}]}]}}]]

    local parsed = StreamIntegrator.parse_jsonl_line(jsonl_line)
    local tool_result_block = parsed.message.content[1]
    local content_text = tool_result_block.content[1].text

    -- Mock tool name context (would come from linking tool_use_id to original tool)
    tool_result_block.tool_name = "Read"

    local result = ContentClassifier.classify_from_structured_data(tool_result_block, content_text)

    MiniTest.expect.equality(result.type, ContentClassifier.ContentType.FILE_CONTENT)
    MiniTest.expect.equality(result.confidence, 1.0) -- 100% deterministic
    MiniTest.expect.equality(result.metadata.tool_name, "Read")
    MiniTest.expect.equality(result.display_strategy, "syntax_highlighted_popup")
end

T["MCP Tool Integration"] = MiniTest.new_set()

T["MCP Tool Integration"]["handles MCP tool_use deterministically"] = function()
    -- RED: Test MCP tool integration (mcp__server__tool format)
    local jsonl_line =
        [[{"type": "assistant", "message": {"content": [{"type": "tool_use", "id": "toolu_mcp_001", "name": "mcp__context7__get-library-docs", "input": {"library": "react", "topic": "hooks"}}]}}]]

    local parsed = StreamIntegrator.parse_jsonl_line(jsonl_line)
    local tool_use_block = parsed.message.content[1]
    local content_text = vim.fn.json_encode(tool_use_block.input)

    local result = ContentClassifier.classify_from_structured_data(tool_use_block, content_text)

    MiniTest.expect.equality(result.type, ContentClassifier.ContentType.TOOL_INPUT)
    MiniTest.expect.equality(result.confidence, 1.0)
    MiniTest.expect.equality(result.metadata.tool_name, "mcp__context7__get-library-docs")
end

T["MCP Tool Integration"]["classifies MCP JSON response as JSON_API_RESPONSE"] = function()
    -- RED: Test MCP JSON response classification (9181 char scenario from SEMANTIC_CONTENT_PLAN.md)
    local mcp_response =
        [[{"jsonrpc": "2.0", "id": 1, "result": {"content": [{"type": "text", "text": "# React Hooks Documentation\n\n## useState\n\nThe useState hook allows you to add state to functional components..."}]}}]]

    local jsonl_line = string.format(
        [[{"type": "user", "message": {"content": [{"type": "tool_result", "tool_use_id": "toolu_mcp_001", "content": [{"type": "text", "text": %q}]}]}}]],
        mcp_response
    )

    local parsed = StreamIntegrator.parse_jsonl_line(jsonl_line)
    local tool_result_block = parsed.message.content[1]
    local content_text = tool_result_block.content[1].text

    -- Mock MCP tool context
    tool_result_block.tool_name = "mcp__context7__get-library-docs"

    local result = ContentClassifier.classify_from_structured_data(tool_result_block, content_text)

    MiniTest.expect.equality(result.type, ContentClassifier.ContentType.JSON_API_RESPONSE)
    MiniTest.expect.equality(result.confidence, 1.0)
    MiniTest.expect.equality(result.metadata.api_source, "mcp__context7__get-library-docs")
    MiniTest.expect.equality(result.metadata.is_json, true)
    MiniTest.expect.equality(result.display_strategy, "json_popup_with_folding")
end

T["Tool Context Linking"] = MiniTest.new_set()

T["Tool Context Linking"]["links tool_use_id to tool_result for context"] = function()
    -- RED: Test the critical tool_use_id linking functionality
    local tool_use_jsonl =
        [[{"type": "assistant", "message": {"content": [{"type": "tool_use", "id": "toolu_bash_001", "name": "Bash", "input": {"command": "ls -la /tmp"}}]}}]]
    local tool_result_jsonl =
        [[{"type": "user", "message": {"content": [{"type": "tool_result", "tool_use_id": "toolu_bash_001", "content": [{"type": "text", "text": "total 16\n-rw-r--r-- 1 user staff 1024 Dec 25 10:30 test.txt"}]}]}}]]

    -- Parse both messages
    local tool_use_parsed = StreamIntegrator.parse_jsonl_line(tool_use_jsonl)
    local tool_result_parsed = StreamIntegrator.parse_jsonl_line(tool_result_jsonl)

    -- Link them together (this is the key integration functionality)
    local linked_context = StreamIntegrator.link_tool_use_to_result(tool_use_parsed, tool_result_parsed)

    MiniTest.expect.equality(linked_context.tool_use_id, "toolu_bash_001")
    MiniTest.expect.equality(linked_context.tool_name, "Bash")
    MiniTest.expect.equality(linked_context.input_content, '{"command": "ls -la /tmp"}')
    MiniTest.expect.equality(type(linked_context.result_content), "string")

    -- Now classify the result with full context
    local tool_result_block = tool_result_parsed.message.content[1]
    tool_result_block.tool_name = linked_context.tool_name

    local result = ContentClassifier.classify_from_structured_data(tool_result_block, linked_context.result_content)

    MiniTest.expect.equality(result.type, ContentClassifier.ContentType.COMMAND_OUTPUT)
    MiniTest.expect.equality(result.confidence, 1.0)
    MiniTest.expect.equality(result.metadata.tool_name, "Bash")
    MiniTest.expect.equality(result.display_strategy, "terminal_style_popup")
end

T["Real-time Stream Processing"] = MiniTest.new_set()

T["Real-time Stream Processing"]["processes JSONL stream incrementally"] = function()
    -- RED: Test processing multiple JSONL lines as they arrive (like real Claude Code streaming)
    local jsonl_stream = {
        '{"type": "system", "subtype": "init", "session_id": "test-session"}',
        '{"type": "assistant", "message": {"content": [{"type": "tool_use", "id": "toolu_001", "name": "Read", "input": {"file_path": "/test"}}]}}',
        '{"type": "user", "message": {"content": [{"type": "tool_result", "tool_use_id": "toolu_001", "content": [{"type": "text", "text": "test content"}]}]}}',
        '{"type": "result", "subtype": "success", "total_cost_usd": 0.001}',
    }

    local processor = StreamIntegrator.create_stream_processor()
    local classifications = {}

    for _, line in ipairs(jsonl_stream) do
        local result = processor:process_line(line)
        if result and result.classification then
            table.insert(classifications, result.classification)
        end
    end

    -- Should have classified the tool_use and tool_result
    MiniTest.expect.equality(#classifications, 2)
    MiniTest.expect.equality(classifications[1].type, ContentClassifier.ContentType.TOOL_INPUT)
    MiniTest.expect.equality(classifications[2].type, ContentClassifier.ContentType.FILE_CONTENT)
end

T["Hook Integration"] = MiniTest.new_set()

T["Hook Integration"]["integrates with Claude Code hooks system"] = function()
    -- RED: Test integration with Claude Code hooks (transcript_path from hooks documentation)
    local mock_transcript_path = "/tmp/test_conversation.jsonl"
    local mock_session_id = "test-session-123"
    local mock_cwd = "/project/root"

    -- This would be called by a Claude Code hook
    local hook_result = StreamIntegrator.process_claude_code_hook({
        session_id = mock_session_id,
        transcript_path = mock_transcript_path,
        cwd = mock_cwd,
        hook_event_name = "PostToolUse",
    })

    MiniTest.expect.equality(hook_result.success, true)
    MiniTest.expect.equality(hook_result.session_id, mock_session_id)
    MiniTest.expect.equality(type(hook_result.classifications), "table")
end

T["Performance and Caching"] = MiniTest.new_set()

T["Performance and Caching"]["caches repeated classifications"] = function()
    -- Test that identical content gets cached for performance
    local processor = StreamIntegrator.create_stream_processor()

    -- Process the same tool_use multiple times
    local jsonl_line =
        [[{"type": "assistant", "message": {"content": [{"type": "tool_use", "id": "toolu_cache_test", "name": "Read", "input": {"file_path": "/same/file.txt"}}]}}]]

    -- First processing (cache miss)
    local result1 = processor:process_line(jsonl_line)
    local stats_after_first = processor:get_stats()

    -- Second processing (should be cache hit)
    local result2 = processor:process_line(jsonl_line)
    local stats_after_second = processor:get_stats()

    -- Verify both results are identical
    MiniTest.expect.equality(result1.classification.type, result2.classification.type)
    MiniTest.expect.equality(result1.classification.confidence, result2.classification.confidence)

    -- Verify caching statistics
    MiniTest.expect.equality(stats_after_first.cache_misses, 1)
    MiniTest.expect.equality(stats_after_first.cache_hits, 0)
    MiniTest.expect.equality(stats_after_second.cache_misses, 1) -- No increase
    MiniTest.expect.equality(stats_after_second.cache_hits, 1) -- Increased
    MiniTest.expect.equality(stats_after_second.cache_hit_rate > 0, true)
end

T["Performance and Caching"]["tracks performance statistics"] = function()
    -- Test performance tracking and statistics
    local processor = StreamIntegrator.create_stream_processor()

    -- Process several different messages
    local jsonl_lines = {
        '{"type": "system", "subtype": "init", "session_id": "perf-test"}',
        '{"type": "assistant", "message": {"content": [{"type": "tool_use", "id": "toolu_perf1", "name": "Bash", "input": {"command": "echo test"}}]}}',
        '{"type": "user", "message": {"content": [{"type": "tool_result", "tool_use_id": "toolu_perf1", "content": [{"type": "text", "text": "test"}]}]}}',
    }

    for _, line in ipairs(jsonl_lines) do
        processor:process_line(line)
    end

    local stats = processor:get_stats()

    -- Verify statistics are tracked
    MiniTest.expect.equality(stats.total_messages, 3)
    MiniTest.expect.equality(type(stats.processing_time_ms), "number")
    MiniTest.expect.equality(type(stats.avg_processing_time_ms), "number")
    MiniTest.expect.equality(stats.avg_processing_time_ms >= 0, true)
    MiniTest.expect.equality(type(stats.total_time_ms), "number")
    MiniTest.expect.equality(stats.total_time_ms > 0, true)
end

T["Performance and Caching"]["clears caches for memory management"] = function()
    -- Test cache clearing functionality
    local processor = StreamIntegrator.create_stream_processor()

    -- Add some cached classifications
    local jsonl_line =
        [[{"type": "assistant", "message": {"content": [{"type": "tool_use", "id": "toolu_clear_test", "name": "Read", "input": {"file_path": "/test.txt"}}]}}]]
    processor:process_line(jsonl_line)

    local stats_before_clear = processor:get_stats()
    MiniTest.expect.equality(stats_before_clear.cache_misses, 1)

    -- Clear caches
    processor:clear_caches()

    -- Process the same line again - should be cache miss again
    processor:process_line(jsonl_line)
    local stats_after_clear = processor:get_stats()

    -- Should have another cache miss since cache was cleared
    MiniTest.expect.equality(stats_after_clear.cache_misses, 2)
end

T["Integration with Existing Systems"] = MiniTest.new_set()

T["Integration with Existing Systems"]["integrates with tree_builder enhanced parameters"] = function()
    -- Test that tree_builder integration supports Claude Code stream context
    local tool_use_id = "toolu_integration_test"
    local content = {
        type = "tool_result",
        tool_use_id = tool_use_id,
        content = { { type = "text", text = "integration test content" } },
    }

    -- Mock create_text_node function
    local text_node_counter = 0
    local function create_text_node(text, parent_id, node_id)
        text_node_counter = text_node_counter + 1
        return {
            id = "text-" .. tostring(text_node_counter),
            text = text,
            parent_id = parent_id,
        }
    end

    -- Test the enhanced tree_builder function (now supports stream_context parameter)
    local tree_builder = require("cc-tui.models.tree_builder")
    local node = tree_builder.create_result_node_from_content(
        tool_use_id,
        content,
        create_text_node,
        "Read",
        { structured_source = true } -- stream_context parameter
    )

    MiniTest.expect.equality(node.id, "result-" .. tool_use_id)
    MiniTest.expect.equality(node.tool_use_id, tool_use_id)
end

return T
