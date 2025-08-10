---@brief [[
--- Tests for ContentClassifier unified content type detection
--- Validates the replacement of fragmented detection logic with unified classifier
---@brief ]]

local _ = dofile("tests/helpers.lua") -- Load helpers but unused in this test file

-- Unit tests for ContentClassifier - no child neovim process needed for pure logic
local T = MiniTest.new_set()

-- Import ContentClassifier (will be created)
local ContentClassifier

T["ContentClassifier Module Loading"] = MiniTest.new_set()

T["ContentClassifier Module Loading"]["loads without error"] = function()
    -- RED: This will fail initially since module doesn't exist yet
    local ok, classifier = pcall(require, "cc-tui.utils.content_classifier")
    MiniTest.expect.equality(ok, true)
    MiniTest.expect.equality(type(classifier), "table")
    ContentClassifier = classifier
end

T["ContentClassifier API"] = MiniTest.new_set()

T["ContentClassifier API"]["has classify method"] = function()
    -- RED: Will fail until we implement the API
    MiniTest.expect.equality(type(ContentClassifier.classify), "function")
end

T["ContentClassifier API"]["has content type constants"] = function()
    -- RED: Will fail until we implement the constants
    MiniTest.expect.equality(type(ContentClassifier.ContentType), "table")
    MiniTest.expect.equality(type(ContentClassifier.ContentType.TOOL_INPUT), "string")
    MiniTest.expect.equality(type(ContentClassifier.ContentType.JSON_API_RESPONSE), "string")
    MiniTest.expect.equality(type(ContentClassifier.ContentType.ERROR_OBJECT), "string")
    MiniTest.expect.equality(type(ContentClassifier.ContentType.FILE_CONTENT), "string")
    MiniTest.expect.equality(type(ContentClassifier.ContentType.COMMAND_OUTPUT), "string")
    MiniTest.expect.equality(type(ContentClassifier.ContentType.GENERIC_TEXT), "string")
end

T["JSON Content Detection"] = MiniTest.new_set()

T["JSON Content Detection"]["detects simple JSON objects"] = function()
    -- RED: Will fail until implementation exists
    local result = ContentClassifier.classify('{"key": "value"}')
    MiniTest.expect.equality(result.type, ContentClassifier.ContentType.JSON_API_RESPONSE)
    MiniTest.expect.equality(type(result.confidence), "number")
    MiniTest.expect.equality(type(result.metadata), "table")
end

T["JSON Content Detection"]["detects JSON arrays"] = function()
    -- RED: Will fail until implementation exists
    local result = ContentClassifier.classify('[{"item": 1}, {"item": 2}]')
    MiniTest.expect.equality(result.type, ContentClassifier.ContentType.JSON_API_RESPONSE)
end

T["JSON Content Detection"]["detects complex nested JSON"] = function()
    -- RED: Test with realistic Claude Code MCP response
    local complex_json = [[{
  "jsonrpc": "2.0",
  "result": {
    "content": [
      {
        "type": "text",
        "text": "Function documentation here"
      }
    ]
  },
  "id": 123
}]]
    local result = ContentClassifier.classify(complex_json)
    MiniTest.expect.equality(result.type, ContentClassifier.ContentType.JSON_API_RESPONSE)
    MiniTest.expect.equality(result.metadata.is_mcp_response, true)
end

T["JSON Content Detection"]["rejects non-JSON content"] = function()
    -- RED: Will fail until implementation exists
    local result = ContentClassifier.classify("This is plain text, not JSON")
    MiniTest.expect.no_equality(result.type, ContentClassifier.ContentType.JSON_API_RESPONSE)
end

T["Tool Context Classification"] = MiniTest.new_set()

T["Tool Context Classification"]["classifies tool inputs as TOOL_INPUT"] = function()
    -- RED: Will fail until context-aware classification is implemented
    local result = ContentClassifier.classify('{"file_path": "/tmp/test.txt"}', "Read", "input")
    MiniTest.expect.equality(result.type, ContentClassifier.ContentType.TOOL_INPUT)
    MiniTest.expect.equality(result.metadata.tool_name, "Read")
end

T["Tool Context Classification"]["classifies Read tool output as FILE_CONTENT"] = function()
    -- RED: Will fail until tool-aware classification is implemented
    local file_content = [[function hello()
    print("Hello World")
end]]
    local result = ContentClassifier.classify(file_content, "Read", "output")
    MiniTest.expect.equality(result.type, ContentClassifier.ContentType.FILE_CONTENT)
    MiniTest.expect.equality(result.metadata.tool_name, "Read")
end

T["Tool Context Classification"]["classifies Bash tool output as COMMAND_OUTPUT"] = function()
    -- RED: Will fail until tool-aware classification is implemented
    local bash_output = [[total 16
-rw-r--r--  1 user  staff  1024 Dec 25 10:30 test.txt
-rw-r--r--  1 user  staff  2048 Dec 25 10:31 data.json]]
    local result = ContentClassifier.classify(bash_output, "Bash", "output")
    MiniTest.expect.equality(result.type, ContentClassifier.ContentType.COMMAND_OUTPUT)
    MiniTest.expect.equality(result.metadata.tool_name, "Bash")
end

T["Error Content Detection"] = MiniTest.new_set()

T["Error Content Detection"]["detects error patterns"] = function()
    -- RED: Will fail until error detection is implemented
    local error_content = "Error: File not found: /nonexistent/path.txt"
    local result = ContentClassifier.classify(error_content)
    MiniTest.expect.equality(result.type, ContentClassifier.ContentType.ERROR_OBJECT)
    MiniTest.expect.equality(result.metadata.error_type, "file_not_found")
end

T["Error Content Detection"]["detects JSON error responses"] = function()
    -- RED: Will fail until JSON error detection is implemented
    local json_error = '{"error": {"message": "Invalid request", "code": 400}}'
    local result = ContentClassifier.classify(json_error)
    MiniTest.expect.equality(result.type, ContentClassifier.ContentType.ERROR_OBJECT)
    MiniTest.expect.equality(result.metadata.is_json_error, true)
end

T["Consistency Validation"] = MiniTest.new_set()

T["Consistency Validation"]["same content produces same classification"] = function()
    -- RED: Will fail until implementation is deterministic
    local content = '{"test": "data", "nested": {"value": 123}}'

    local result1 = ContentClassifier.classify(content)
    local result2 = ContentClassifier.classify(content)
    local result3 = ContentClassifier.classify(content)

    -- Same content should ALWAYS produce same type
    MiniTest.expect.equality(result1.type, result2.type)
    MiniTest.expect.equality(result2.type, result3.type)
    MiniTest.expect.equality(result1.confidence, result2.confidence)
end

T["Consistency Validation"]["replaces all existing detection functions"] = function()
    -- GREEN: Phase 1 cleanup completed - ContentRenderer functions removed
    local test_json = '{"example": "json content"}'

    -- Test that our classifier works correctly
    local classifier_result = ContentClassifier.classify(test_json)

    -- Remaining old functions should agree with our classifier for JSON
    local parser_detects_json = ContentClassifier.is_json_content(test_json)
    local builder_uses_rich_display = ContentClassifier.should_use_rich_display(test_json, false)

    -- Phase 1 cleanup success: ContentRenderer.is_json_content removed
    -- Now only sophisticated ContentClassifier.is_json_content should be used

    -- If our classifier says it's JSON, the remaining old functions should agree
    local is_json_type = classifier_result.type == ContentClassifier.ContentType.JSON_API_RESPONSE
        or classifier_result.type == ContentClassifier.ContentType.TOOL_INPUT

    if is_json_type then
        MiniTest.expect.equality(parser_detects_json, true)
        MiniTest.expect.equality(builder_uses_rich_display, true) -- JSON should use rich display
    else
        -- For non-JSON, at least parser should NOT detect JSON
        MiniTest.expect.equality(parser_detects_json, false)
    end
end

T["Performance Requirements"] = MiniTest.new_set()

T["Performance Requirements"]["classifies content under 10ms"] = function()
    -- RED: Will fail until implementation is optimized
    local large_json = '{"data": ' .. string.rep('[{"item": "value"},', 1000) .. "{}]}"

    local start_time = vim.uv.hrtime()
    local result = ContentClassifier.classify(large_json)
    local end_time = vim.uv.hrtime()

    local duration_ms = (end_time - start_time) / 1000000 -- Convert to milliseconds

    MiniTest.expect.equality(type(result), "table")
    MiniTest.expect.equality(duration_ms < 10, true) -- Must be under 10ms
end

T["Deterministic Structured Classification"] = MiniTest.new_set()

T["Deterministic Structured Classification"]["has classify_from_structured_data method"] = function()
    MiniTest.expect.equality(type(ContentClassifier.classify_from_structured_data), "function")
end

T["Deterministic Structured Classification"]["classifies tool_use as TOOL_INPUT with 100% confidence"] = function()
    local structured_data = {
        type = "tool_use",
        name = "Read",
        id = "toolu_123",
        input = { file_path = "/tmp/test.txt" },
    }
    local content = '{"file_path": "/tmp/test.txt"}'

    local result = ContentClassifier.classify_from_structured_data(structured_data, content)

    MiniTest.expect.equality(result.type, ContentClassifier.ContentType.TOOL_INPUT)
    MiniTest.expect.equality(result.confidence, 1.0) -- 100% confident
    MiniTest.expect.equality(result.metadata.structured_source, true)
    MiniTest.expect.equality(result.metadata.tool_name, "Read")
    MiniTest.expect.equality(result.metadata.tool_id, "toolu_123")
    MiniTest.expect.equality(result.display_strategy, "json_popup_always")
end

T["Deterministic Structured Classification"]["classifies tool_result for Read as FILE_CONTENT"] = function()
    local structured_data = {
        type = "tool_result",
        tool_use_id = "toolu_123",
        content = { { type = "text", text = "function hello() print('Hello') end" } },
    }
    local content = "function hello() print('Hello') end"

    -- Mock tool name (would normally be passed from context)
    structured_data.tool_name = "Read"

    local result = ContentClassifier.classify_from_structured_data(structured_data, content)

    MiniTest.expect.equality(result.type, ContentClassifier.ContentType.FILE_CONTENT)
    MiniTest.expect.equality(result.confidence, 1.0) -- 100% confident
    MiniTest.expect.equality(result.metadata.structured_source, true)
    MiniTest.expect.equality(result.metadata.tool_name, "Read")
    MiniTest.expect.equality(result.display_strategy, "syntax_highlighted_popup")
end

T["Deterministic Structured Classification"]["classifies tool_result for Bash as COMMAND_OUTPUT"] = function()
    local structured_data = {
        type = "tool_result",
        tool_use_id = "toolu_456",
        content = { { type = "text", text = "total 16\n-rw-r--r-- 1 user staff 1024 Dec 25 10:30 test.txt" } },
    }
    local content = "total 16\n-rw-r--r-- 1 user staff 1024 Dec 25 10:30 test.txt"

    -- Mock tool name
    structured_data.tool_name = "Bash"

    local result = ContentClassifier.classify_from_structured_data(structured_data, content)

    MiniTest.expect.equality(result.type, ContentClassifier.ContentType.COMMAND_OUTPUT)
    MiniTest.expect.equality(result.confidence, 1.0)
    MiniTest.expect.equality(result.metadata.tool_name, "Bash")
    MiniTest.expect.equality(result.display_strategy, "terminal_style_popup")
end

T["Deterministic Structured Classification"]["classifies MCP tool JSON result as JSON_API_RESPONSE"] = function()
    local structured_data = {
        type = "tool_result",
        tool_use_id = "toolu_789",
        content = { { type = "text", text = '{"jsonrpc": "2.0", "result": {"content": "API response"}}' } },
    }
    local content = '{"jsonrpc": "2.0", "result": {"content": "API response"}}'

    -- Mock MCP tool name
    structured_data.tool_name = "mcp__context7__get-docs"

    local result = ContentClassifier.classify_from_structured_data(structured_data, content)

    MiniTest.expect.equality(result.type, ContentClassifier.ContentType.JSON_API_RESPONSE)
    MiniTest.expect.equality(result.confidence, 1.0)
    MiniTest.expect.equality(result.metadata.api_source, "mcp__context7__get-docs")
    MiniTest.expect.equality(result.metadata.is_json, true)
    MiniTest.expect.equality(result.display_strategy, "json_popup_with_folding")
end

T["Deterministic Structured Classification"]["deterministic classification is consistent"] = function()
    local structured_data = {
        type = "tool_use",
        name = "Edit",
        id = "toolu_edit_001",
        input = { file_path = "/src/main.js", old_string = "old", new_string = "new" },
    }
    local content = '{"file_path": "/src/main.js", "old_string": "old", "new_string": "new"}'

    -- Run multiple times - should always be identical
    local result1 = ContentClassifier.classify_from_structured_data(structured_data, content)
    local result2 = ContentClassifier.classify_from_structured_data(structured_data, content)
    local result3 = ContentClassifier.classify_from_structured_data(structured_data, content)

    -- ALL results should be identical (deterministic)
    MiniTest.expect.equality(result1.type, result2.type)
    MiniTest.expect.equality(result2.type, result3.type)
    MiniTest.expect.equality(result1.confidence, result2.confidence)
    MiniTest.expect.equality(result2.confidence, result3.confidence)
    MiniTest.expect.equality(result1.display_strategy, result2.display_strategy)
    MiniTest.expect.equality(result2.display_strategy, result3.display_strategy)

    -- All should be 100% confident
    MiniTest.expect.equality(result1.confidence, 1.0)
    MiniTest.expect.equality(result2.confidence, 1.0)
    MiniTest.expect.equality(result3.confidence, 1.0)
end

return T
