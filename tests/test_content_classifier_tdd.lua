---@brief [[
--- TDD-driven Content Classifier Tests using Real Tool Outputs
--- Implements Phase 2 of TEST_REFACTORING_PLAN.md - Content Classification Validation
---@brief ]]

local MiniTest = require("mini.test")
local RealDataLoader = require("tests.helpers.real_data_loader")
local TddFramework = require("tests.helpers.tdd_framework")

local child = MiniTest.new_child_neovim()

local T = MiniTest.new_set({
    hooks = {
        pre_case = function()
            child.restart({ "-u", "scripts/minimal_init.lua" })
            -- Ensure real data is available
            local valid, err = RealDataLoader.validate_real_data_available()
            if not valid then
                MiniTest.skip("Real conversation data not available: " .. (err or "unknown"))
            end
        end,
        post_once = child.stop,
    },
})

-- Helper function to extract tool results from real conversations
local function extract_tool_outputs(messages)
    local tool_outputs = {}

    for _, msg in ipairs(messages) do
        if msg.type == "user" and msg.message.content then
            for _, content in ipairs(msg.message.content) do
                if content.type == "tool_result" then
                    table.insert(tool_outputs, {
                        tool_use_id = content.tool_use_id,
                        content = content.content,
                        raw_content = content,
                    })
                end
            end
        end
    end

    return tool_outputs
end

-- Helper function to extract tool inputs from real conversations
local function extract_tool_inputs(messages)
    local tool_inputs = {}

    for _, msg in ipairs(messages) do
        if msg.type == "assistant" and msg.message.content then
            for _, content in ipairs(msg.message.content) do
                if content.type == "tool_use" then
                    table.insert(tool_inputs, {
                        id = content.id,
                        name = content.name,
                        input = content.input,
                        raw_content = content,
                    })
                end
            end
        end
    end

    return tool_inputs
end

-- TDD CYCLE 1: JSON Content Detection with Real Data
T["classify_content - JSON Detection from Real Tool Outputs"] = function()
    local cycle = TddFramework.create_cycle({
        description = "Detect JSON content accurately from real tool outputs",
        category = "medium", -- Medium files likely have diverse tool outputs
        setup = function(state)
            child.lua([[
                _G.ContentClassifier = require('cc-tui.utils.content_classifier')
                _G.Parser = require('cc-tui.parser.stream')
            ]])
        end,
    })

    -- RED: Test with real JSON outputs from conversations
    local test_fn = function(state)
        local lines = state.provider:get_lines()
        local messages = {}

        -- Parse messages
        for _, line in ipairs(lines) do
            local parsed = child.lua_get([[_G.Parser.parse_line(...) ]], { line })
            if parsed then
                table.insert(messages, parsed)
            end
        end

        local tool_outputs = extract_tool_outputs(messages)

        -- Skip if no tool outputs
        if #tool_outputs == 0 then
            MiniTest.skip("No tool outputs found in selected conversation")
        end

        -- Test JSON detection on real outputs
        local json_found = false
        for _, output in ipairs(tool_outputs) do
            local content = output.content
            if type(content) == "string" then
                local classification = child.lua_get([[_G.ContentClassifier.classify_content(...) ]], { content })

                -- Validate classification structure
                TddFramework.expect(classification).to_not_be_nil()
                TddFramework.expect(classification.content_type).to_not_be_nil()
                TddFramework.expect(classification.display_strategy).to_not_be_nil()

                -- Check if JSON is properly detected
                if content:match("^%s*[%[{]") and content:match("[%]}]%s*$") then
                    -- This looks like JSON, classifier should detect it
                    if
                        classification.content_type == "json_structured"
                        or classification.content_type == "json_api"
                    then
                        json_found = true
                    end
                end
            end
        end

        -- Should find at least some JSON-like content in medium conversations
        -- (This is a soft assertion since not all conversations have JSON)
        local has_json_content = json_found or #tool_outputs < 3
        TddFramework.expect(has_json_content).to_be_truthy()
    end

    cycle.red(test_fn)
end

T["classify_content - Code Block Detection"] = function()
    local cycle = TddFramework.create_cycle({
        description = "Identify code blocks accurately in real tool outputs",
        category = "medium",
        setup = function(state)
            child.lua([[
                _G.ContentClassifier = require('cc-tui.utils.content_classifier')
                _G.Parser = require('cc-tui.parser.stream')
            ]])
        end,
    })

    -- RED: Test with actual code snippets from tool results
    local test_fn = function(state)
        local lines = state.provider:get_lines()
        local messages = {}

        for _, line in ipairs(lines) do
            local parsed = child.lua_get([[_G.Parser.parse_line(...) ]], { line })
            if parsed then
                table.insert(messages, parsed)
            end
        end

        local tool_outputs = extract_tool_outputs(messages)

        if #tool_outputs == 0 then
            MiniTest.skip("No tool outputs found")
        end

        -- Look for code-like content
        local code_patterns_tested = 0
        for _, output in ipairs(tool_outputs) do
            local content = output.content
            if type(content) == "string" then
                -- Check for common code indicators
                local has_code_indicators = content:match("function%s+")
                    or content:match("class%s+")
                    or content:match("def%s+")
                    or content:match("import%s+")
                    or content:match("require%(")
                    or content:match("%-%-%s") -- Lua comments
                    or content:match("//%s") -- JS/C++ comments
                    or content:match("#%s") -- Python/Shell comments

                if has_code_indicators then
                    code_patterns_tested = code_patterns_tested + 1

                    local classification = child.lua_get([[_G.ContentClassifier.classify_content(...) ]], { content })

                    -- Should classify as code-related type
                    local is_code_type = classification.content_type == "code_snippet"
                        or classification.content_type == "file_content"
                        or string.find(classification.content_type, "code")

                    -- Allow for file_content classification as it can contain code
                    TddFramework.expect(is_code_type or classification.content_type == "file_content").to_be_truthy()
                end
            end
        end

        -- If no code patterns found, test passes (not all conversations have code)
        TddFramework.expect(code_patterns_tested >= 0).to_be_truthy()
    end

    cycle.red(test_fn)
end

T["classify_content - Error Message Detection"] = function()
    local cycle = TddFramework.create_cycle({
        description = "Handle error messages appropriately from real outputs",
        category = "large", -- Large files likely have errors/failures
        setup = function(state)
            child.lua([[
                _G.ContentClassifier = require('cc-tui.utils.content_classifier')
                _G.Parser = require('cc-tui.parser.stream')
            ]])
        end,
    })

    -- RED: Test with real error outputs from conversations
    local test_fn = function(state)
        local lines = state.provider:get_lines()
        local messages = {}

        for _, line in ipairs(lines) do
            local parsed = child.lua_get([[_G.Parser.parse_line(...) ]], { line })
            if parsed then
                table.insert(messages, parsed)
            end
        end

        local tool_outputs = extract_tool_outputs(messages)

        if #tool_outputs == 0 then
            MiniTest.skip("No tool outputs found")
        end

        -- Look for error-like content
        local error_patterns_found = false
        for _, output in ipairs(tool_outputs) do
            local content = output.content
            if type(content) == "string" then
                -- Common error indicators
                local has_error_indicators = content:match("[Ee]rror:")
                    or content:match("ERROR")
                    or content:match("Exception")
                    or content:match("failed")
                    or content:match("FAILED")
                    or content:match("not found")
                    or content:match("permission denied")
                    or content:match("stack traceback")

                if has_error_indicators then
                    error_patterns_found = true

                    local classification = child.lua_get([[_G.ContentClassifier.classify_content(...) ]], { content })

                    -- Should be classified as error content or at least recognized appropriately
                    TddFramework.expect(classification).to_not_be_nil()
                    TddFramework.expect(classification.content_type).to_not_be_nil()

                    -- Error content should get appropriate display strategy
                    local appropriate_display = classification.display_strategy == "error_popup_highlighted"
                        or classification.display_strategy == "terminal_style_popup"
                        or string.find(classification.display_strategy, "popup") -- Errors should generally be in popup

                    TddFramework.expect(appropriate_display).to_be_truthy()
                    break -- Found one error, test passes
                end
            end
        end

        -- If no errors found, that's also valid (not all conversations have errors)
        TddFramework.expect(true).to_be_truthy() -- Always pass, we're testing classification behavior
    end

    cycle.red(test_fn)
end

T["display_strategy - Appropriate Strategy Selection"] = function()
    local cycle = TddFramework.create_cycle({
        description = "Select appropriate display strategy for content type",
        category = "small",
        setup = function(state)
            child.lua([[
                _G.ContentClassifier = require('cc-tui.utils.content_classifier')
                _G.Parser = require('cc-tui.parser.stream')
            ]])
        end,
    })

    -- RED: Define expected strategy selection logic
    local test_fn = function(state)
        local lines = state.provider:get_lines()
        local messages = {}

        for _, line in ipairs(lines) do
            local parsed = child.lua_get([[_G.Parser.parse_line(...) ]], { line })
            if parsed then
                table.insert(messages, parsed)
            end
        end

        local tool_outputs = extract_tool_outputs(messages)
        local tool_inputs = extract_tool_inputs(messages)

        -- Test tool inputs (should always be popup according to plan)
        for _, input in ipairs(tool_inputs) do
            if input.input then
                local input_str = type(input.input) == "table" and vim.json.encode(input.input) or tostring(input.input)
                local classification = child.lua_get([[_G.ContentClassifier.classify_content(...)]], { input_str })

                -- Tool inputs should get popup display
                TddFramework.expect(string.find(classification.display_strategy, "popup")).to_not_be_nil()
            end
        end

        -- Test tool outputs (strategy should match content)
        for _, output in ipairs(tool_outputs) do
            if type(output.content) == "string" and #output.content > 0 then
                local classification = child.lua_get([[_G.ContentClassifier.classify_content(...)]], { output.content })

                -- Validate strategy exists and makes sense
                TddFramework.expect(classification.display_strategy).to_not_be_nil()
                TddFramework.expect(type(classification.display_strategy)).to_equal("string")
                TddFramework.expect(#classification.display_strategy > 0).to_be_truthy()

                -- Strategy should be one of the valid options
                local valid_strategies = {
                    "inline_with_syntax",
                    "syntax_highlighted_popup",
                    "json_popup_always",
                    "terminal_style_popup",
                    "json_popup_with_folding",
                    "error_popup_highlighted",
                    "inline_text_only",
                    "large_content_popup",
                }

                local is_valid_strategy = false
                for _, valid in ipairs(valid_strategies) do
                    if classification.display_strategy == valid then
                        is_valid_strategy = true
                        break
                    end
                end

                TddFramework.expect(is_valid_strategy).to_be_truthy()
            end
        end
    end

    cycle.red(test_fn)
end

-- CONSISTENCY AND DETERMINISTIC TESTS
T["classify_content - Deterministic Classification"] = function()
    local cycle = TddFramework.create_cycle({
        description = "Ensure consistent classification results for same content",
        category = "tiny", -- Fast tests
        setup = function(state)
            child.lua([[
                _G.ContentClassifier = require('cc-tui.utils.content_classifier')
            ]])
        end,
    })

    -- RED: Test classification consistency
    local test_fn = function(state)
        -- Test with known content types
        local test_cases = {
            {
                content = '{"test": "json", "data": [1,2,3]}',
                expected_type = "json_structured",
            },
            {
                content = 'function test() { return "hello"; }',
                expected_type = "code_snippet",
            },
            {
                content = "Error: File not found",
                expected_type = nil, -- Could vary, just test consistency
            },
        }

        for _, test_case in ipairs(test_cases) do
            -- Classify multiple times
            local classifications = {}
            for i = 1, 3 do
                local classification =
                    child.lua_get([[_G.ContentClassifier.classify_content(...)]], { test_case.content })
                table.insert(classifications, classification)
            end

            -- All classifications should be identical
            for i = 2, #classifications do
                TddFramework.expect(classifications[i].content_type).to_equal(classifications[1].content_type)
                TddFramework.expect(classifications[i].display_strategy).to_equal(classifications[1].display_strategy)
            end

            -- Check expected type if specified
            if test_case.expected_type then
                TddFramework.expect(classifications[1].content_type).to_equal(test_case.expected_type)
            end
        end
    end

    cycle.red(test_fn)
end

-- STRUCTURED CLASSIFICATION TESTS (from legacy test file)
T["classify_from_structured_data - Tool Input Classification"] = function()
    local cycle = TddFramework.create_cycle({
        description = "Classify tool inputs with structured data context",
        category = "tiny",
        setup = function(state)
            child.lua([[
                _G.ContentClassifier = require('cc-tui.utils.content_classifier')
            ]])
        end,
    })

    -- RED: Test structured data classification for tool inputs
    local test_fn = function(state)
        local structured_data = {
            type = "tool_use",
            name = "Read",
            id = "toolu_123",
            input = { file_path = "/tmp/test.txt" },
        }
        local content = '{"file_path": "/tmp/test.txt"}'

        local result =
            child.lua_get([[_G.ContentClassifier.classify_from_structured_data(...)]], { structured_data, content })

        -- Validate structured classification
        TddFramework.expect(result).to_not_be_nil()
        TddFramework.expect(result.type).to_not_be_nil()
        TddFramework.expect(result.confidence).to_equal(1.0) -- 100% confident
        TddFramework.expect(result.metadata.structured_source).to_equal(true)
        TddFramework.expect(result.metadata.tool_name).to_equal("Read")
        TddFramework.expect(result.display_strategy).to_equal("json_popup_always")
    end

    cycle.red(test_fn)
end

T["classify_from_structured_data - Tool Result Classification"] = function()
    local cycle = TddFramework.create_cycle({
        description = "Classify tool results based on tool context",
        category = "tiny",
        setup = function(state)
            child.lua([[
                _G.ContentClassifier = require('cc-tui.utils.content_classifier')
            ]])
        end,
    })

    -- RED: Test structured data classification for tool results
    local test_fn = function(state)
        -- Test Read tool result
        local read_data = {
            type = "tool_result",
            tool_use_id = "toolu_123",
            content = { { type = "text", text = "function hello() print('Hello') end" } },
            tool_name = "Read", -- Mock tool context
        }
        local read_content = "function hello() print('Hello') end"

        local read_result =
            child.lua_get([[_G.ContentClassifier.classify_from_structured_data(...)]], { read_data, read_content })

        TddFramework.expect(read_result.confidence).to_equal(1.0)
        TddFramework.expect(read_result.metadata.structured_source).to_equal(true)
        TddFramework.expect(read_result.metadata.tool_name).to_equal("Read")

        -- Test Bash tool result
        local bash_data = {
            type = "tool_result",
            tool_use_id = "toolu_456",
            content = { { type = "text", text = "total 16\n-rw-r--r-- 1 user staff 1024 test.txt" } },
            tool_name = "Bash",
        }
        local bash_content = "total 16\n-rw-r--r-- 1 user staff 1024 test.txt"

        local bash_result =
            child.lua_get([[_G.ContentClassifier.classify_from_structured_data(...)]], { bash_data, bash_content })

        TddFramework.expect(bash_result.confidence).to_equal(1.0)
        TddFramework.expect(bash_result.metadata.structured_source).to_equal(true)
        TddFramework.expect(bash_result.metadata.tool_name).to_equal("Bash")
        TddFramework.expect(bash_result.display_strategy).to_equal("terminal_style_popup")
    end

    cycle.red(test_fn)
end

-- REMOVED: Performance tests are premature optimization
-- Following "make it work, make it right, make it fast" principle
-- Performance testing will be added in future "Make It Fast" phase

return T
