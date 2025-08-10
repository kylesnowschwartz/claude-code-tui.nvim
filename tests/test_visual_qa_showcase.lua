---@brief [[
--- Visual QA Showcase for Phase 2: Perfect Content Display Strategy
--- This test demonstrates the deterministic display decisions for different content types
--- Run this to see Phase 2 in action - every content type gets perfect display treatment
---@brief ]]

local Helpers = dofile("tests/helpers.lua")
local T = MiniTest.new_set()

-- Import required modules
local ContentClassifier = require("cc-tui.utils.content_classifier")
local StreamIntegrator = require("cc-tui.integration.claude_code_stream")

T["Visual QA Showcase"] = MiniTest.new_set()

T["Visual QA Showcase"]["demonstrates perfect display strategy showcase"] = function()
    print("\n🎯 PHASE 2 VISUAL QA SHOWCASE: Perfect Content Display Strategy")
    print("=" .. string.rep("=", 70))

    -- Test scenario 1: Small file content (should be inline)
    print("\n📄 SCENARIO 1: Small file content")
    local small_config_jsonl =
        [[{"type": "user", "message": {"content": [{"type": "tool_result", "tool_use_id": "toolu_config", "content": [{"type": "text", "text": "api_key=secret123\ndebug=true\nport=3000"}]}]}}]]
    local config_parsed = StreamIntegrator.parse_jsonl_line(small_config_jsonl)
    local config_content = config_parsed.message.content[1]
    local config_text = config_content.content[1].text

    local config_context = {
        tool_use_id = "toolu_config",
        tool_name = "Read",
        message_type = "user",
        is_tool_result = true,
        original_input = { file_path = "/config/app.env" },
    }
    config_content.tool_name = "Read"

    local config_result = ContentClassifier.classify_with_stream_context(config_content, config_text, config_context)
    print("   📁 File: /config/app.env (3 lines, 34 chars)")
    print(
        "   🎨 Display: "
            .. config_result.display_strategy
            .. " (force_popup: "
            .. tostring(config_result.force_popup)
            .. ")"
    )
    print(
        "   🏷️  Type: "
            .. config_result.type
            .. " | Syntax: "
            .. (config_result.metadata.syntax_language or "none")
    )

    MiniTest.expect.equality(config_result.display_strategy, "inline_with_syntax")
    MiniTest.expect.equality(config_result.force_popup, false)

    -- Test scenario 2: Large file content (should be popup with syntax)
    print("\n📄 SCENARIO 2: Large file content")
    local large_tsx_jsonl =
        [[{"type": "user", "message": {"content": [{"type": "tool_result", "tool_use_id": "toolu_component", "content": [{"type": "text", "text": "import React, { useState } from 'react';\n\nconst UserProfile = ({ userId }) => {\n  const [user, setUser] = useState(null);\n  const [loading, setLoading] = useState(true);\n  const [error, setError] = useState(null);\n\n  return (\n    <div className=\"user-profile\">\n      <h1>{user?.name}</h1>\n      <p>{user?.email}</p>\n    </div>\n  );\n};\n\nexport default UserProfile;"}]}]}}]]
    local tsx_parsed = StreamIntegrator.parse_jsonl_line(large_tsx_jsonl)
    local tsx_content = tsx_parsed.message.content[1]
    local tsx_text = tsx_content.content[1].text

    local tsx_context = {
        tool_use_id = "toolu_component",
        tool_name = "Read",
        message_type = "user",
        is_tool_result = true,
        original_input = { file_path = "/src/components/UserProfile.tsx" },
    }
    tsx_content.tool_name = "Read"

    local tsx_result = ContentClassifier.classify_with_stream_context(tsx_content, tsx_text, tsx_context)
    print("   📁 File: /src/components/UserProfile.tsx (" .. tsx_result.metadata.line_count .. " lines)")
    print(
        "   🎨 Display: "
            .. tsx_result.display_strategy
            .. " (force_popup: "
            .. tostring(tsx_result.force_popup)
            .. ")"
    )
    print("   🏷️  Type: " .. tsx_result.type .. " | Syntax: " .. tsx_result.metadata.syntax_language)

    MiniTest.expect.equality(tsx_result.display_strategy, "syntax_highlighted_popup")
    MiniTest.expect.equality(tsx_result.force_popup, true)
    MiniTest.expect.equality(tsx_result.metadata.syntax_language, "typescript")

    -- Test scenario 3: Tool input (always popup, regardless of size)
    print("\n🔧 SCENARIO 3: Tool input (always popup)")
    local tool_input_jsonl =
        [[{"type": "assistant", "message": {"content": [{"type": "tool_use", "id": "toolu_small_input", "name": "Write", "input": {"file_path": "/test.txt", "content": "hello"}}]}}]]
    local input_parsed = StreamIntegrator.parse_jsonl_line(tool_input_jsonl)
    local input_content = input_parsed.message.content[1]
    local input_text = vim.fn.json_encode(input_content.input)

    local input_context = {
        tool_use_id = "toolu_small_input",
        tool_name = "Write",
        message_type = "assistant",
        is_tool_input = true,
        original_input = input_content.input,
    }

    local input_result = ContentClassifier.classify_with_stream_context(input_content, input_text, input_context)
    print("   🔨 Tool: Write (input: " .. #input_text .. " chars)")
    print(
        "   🎨 Display: "
            .. input_result.display_strategy
            .. " (force_popup: "
            .. tostring(input_result.force_popup)
            .. ")"
    )
    print("   🏷️  Type: " .. input_result.type .. " | Rule: Always popup for tool inputs")

    MiniTest.expect.equality(input_result.display_strategy, "json_popup_always")
    MiniTest.expect.equality(input_result.force_popup, true)

    -- Test scenario 4: Bash output (always popup with terminal styling)
    print("\n💻 SCENARIO 4: Bash output (terminal styling)")
    local bash_jsonl =
        [[{"type": "user", "message": {"content": [{"type": "tool_result", "tool_use_id": "toolu_bash", "content": [{"type": "text", "text": "total 16\n-rw-r--r-- 1 user staff 1024 Dec 25 10:30 test.txt"}]}]}}]]
    local bash_parsed = StreamIntegrator.parse_jsonl_line(bash_jsonl)
    local bash_content = bash_parsed.message.content[1]
    local bash_text = bash_content.content[1].text

    local bash_context = {
        tool_use_id = "toolu_bash",
        tool_name = "Bash",
        message_type = "user",
        is_tool_result = true,
        original_input = { command = "ls -la /tmp" },
    }
    bash_content.tool_name = "Bash"

    local bash_result = ContentClassifier.classify_with_stream_context(bash_content, bash_text, bash_context)
    print("   💻 Command: ls -la /tmp (2 lines)")
    print(
        "   🎨 Display: "
            .. bash_result.display_strategy
            .. " (force_popup: "
            .. tostring(bash_result.force_popup)
            .. ")"
    )
    print("   🏷️  Type: " .. bash_result.type .. " | Styling: " .. bash_result.metadata.styling)
    print("   📊 Rule: Bash output always gets terminal popup (even if small)")

    MiniTest.expect.equality(bash_result.display_strategy, "terminal_style_popup")
    MiniTest.expect.equality(bash_result.force_popup, true)
    MiniTest.expect.equality(bash_result.metadata.styling, "terminal")

    -- Test scenario 5: MCP API response (JSON folding popup)
    print("\n🌐 SCENARIO 5: MCP API response (JSON folding)")
    local mcp_response =
        [[{"jsonrpc": "2.0", "result": {"content": [{"text": "React hooks documentation..."}], "meta": {"total": 42}}}]]
    local mcp_jsonl = string.format(
        [[{"type": "user", "message": {"content": [{"type": "tool_result", "tool_use_id": "toolu_mcp", "content": [{"type": "text", "text": %q}]}]}}]],
        mcp_response
    )
    local mcp_parsed = StreamIntegrator.parse_jsonl_line(mcp_jsonl)
    local mcp_content = mcp_parsed.message.content[1]
    local mcp_text = mcp_content.content[1].text

    local mcp_context = {
        tool_use_id = "toolu_mcp",
        tool_name = "mcp__context7__get-library-docs",
        message_type = "user",
        is_tool_result = true,
        is_mcp_tool = true,
        original_input = { library = "react", topic = "hooks" },
    }
    mcp_content.tool_name = "mcp__context7__get-library-docs"

    local mcp_result = ContentClassifier.classify_with_stream_context(mcp_content, mcp_text, mcp_context)
    print("   🔌 MCP Tool: mcp__context7__get-library-docs")
    print(
        "   🎨 Display: "
            .. mcp_result.display_strategy
            .. " (force_popup: "
            .. tostring(mcp_result.force_popup)
            .. ")"
    )
    print("   🏷️  Type: " .. mcp_result.type .. " | API: " .. mcp_result.metadata.api_source)

    MiniTest.expect.equality(mcp_result.display_strategy, "json_popup_with_folding")
    MiniTest.expect.equality(mcp_result.force_popup, true)
    MiniTest.expect.equality(mcp_result.metadata.is_mcp_tool, true)

    -- Test scenario 6: Error content (error popup styling)
    print("\n❌ SCENARIO 6: Error content (error styling)")
    local error_jsonl =
        [[{"type": "user", "message": {"content": [{"type": "tool_result", "tool_use_id": "toolu_error", "is_error": true, "content": [{"type": "text", "text": "Error: ENOENT: no such file or directory, open '/missing/file.txt'"}]}]}}]]
    local error_parsed = StreamIntegrator.parse_jsonl_line(error_jsonl)
    local error_content = error_parsed.message.content[1]
    local error_text = error_content.content[1].text

    local error_context = {
        tool_use_id = "toolu_error",
        tool_name = "Read",
        message_type = "user",
        is_tool_result = true,
        is_error = true,
        original_input = { file_path = "/missing/file.txt" },
    }
    error_content.tool_name = "Read"
    error_content.is_error = true

    local error_result = ContentClassifier.classify_with_stream_context(error_content, error_text, error_context)
    print("   ⚠️  Error: File not found")
    print(
        "   🎨 Display: "
            .. error_result.display_strategy
            .. " (force_popup: "
            .. tostring(error_result.force_popup)
            .. ")"
    )
    print("   🏷️  Type: " .. error_result.type .. " | Error Type: " .. error_result.metadata.error_type)

    MiniTest.expect.equality(error_result.display_strategy, "error_popup_highlighted")
    MiniTest.expect.equality(error_result.force_popup, true)
    MiniTest.expect.equality(error_result.metadata.error_type, "file_not_found")

    print("\n🎉 SUCCESS: Phase 2 Perfect Content Display Strategy Complete!")
    print("   ✅ Tool inputs: Always JSON popup (even tiny ones)")
    print("   ✅ File content: Smart size + syntax decisions")
    print("   ✅ Bash output: Always terminal styling popup")
    print("   ✅ MCP results: JSON folding popup")
    print("   ✅ Errors: Always error styling popup")
    print("   ✅ All decisions are deterministic using Claude Code structured data!")
    print("=" .. string.rep("=", 70))
end

T["Visual QA Showcase"]["creates sample Claude Code JSONL for testing"] = function()
    -- Create a sample JSONL file that demonstrates all the content types
    local sample_jsonl_lines = {
        '{"type": "system", "subtype": "init", "session_id": "phase2-demo", "tools": ["Read", "Write", "Bash", "mcp__context7__get-library-docs"], "model": "claude-3-5-sonnet-20241022"}',
        '{"type": "assistant", "message": {"id": "msg_demo", "role": "assistant", "content": [{"type": "text", "text": "I\'ll demonstrate Phase 2 perfect content classification..."}, {"type": "tool_use", "id": "toolu_read_small", "name": "Read", "input": {"file_path": "/config/app.env"}}]}, "session_id": "phase2-demo"}',
        '{"type": "user", "message": {"role": "user", "content": [{"tool_use_id": "toolu_read_small", "type": "tool_result", "content": [{"type": "text", "text": "api_key=secret123\\ndebug=true\\nport=3000"}]}]}, "session_id": "phase2-demo"}',
        '{"type": "assistant", "message": {"id": "msg_demo2", "role": "assistant", "content": [{"type": "tool_use", "id": "toolu_read_large", "name": "Read", "input": {"file_path": "/src/components/UserProfile.tsx"}}]}, "session_id": "phase2-demo"}',
        '{"type": "user", "message": {"role": "user", "content": [{"tool_use_id": "toolu_read_large", "type": "tool_result", "content": [{"type": "text", "text": "import React from \'react\';\\n\\nconst UserProfile = () => {\\n  return <div>Profile</div>;\\n};\\n\\nexport default UserProfile;"}]}]}, "session_id": "phase2-demo"}',
        '{"type": "assistant", "message": {"id": "msg_demo3", "role": "assistant", "content": [{"type": "tool_use", "id": "toolu_bash", "name": "Bash", "input": {"command": "ls -la /tmp"}}]}, "session_id": "phase2-demo"}',
        '{"type": "user", "message": {"role": "user", "content": [{"tool_use_id": "toolu_bash", "type": "tool_result", "content": [{"type": "text", "text": "total 16\\n-rw-r--r-- 1 user staff 1024 test.txt"}]}]}, "session_id": "phase2-demo"}',
        '{"type": "result", "subtype": "success", "session_id": "phase2-demo", "total_cost_usd": 0.001, "duration_ms": 2500, "num_turns": 3}',
    }

    -- Write to a sample file for manual testing
    local sample_file = "/tmp/phase2_demo.jsonl"
    local file = io.open(sample_file, "w")
    if file then
        for _, line in ipairs(sample_jsonl_lines) do
            file:write(line .. "\n")
        end
        file:close()
        print("\n📁 Sample JSONL created at: " .. sample_file)
        print("   Use this file to test Phase 2 with real Claude Code streaming data!")
    end

    -- Verify we can parse all lines
    local line_count = 0
    local parsed_count = 0
    for _, line in ipairs(sample_jsonl_lines) do
        line_count = line_count + 1
        local parsed = StreamIntegrator.parse_jsonl_line(line)
        if parsed then
            parsed_count = parsed_count + 1
        end
    end

    MiniTest.expect.equality(line_count, parsed_count)
    print("   ✅ All " .. line_count .. " JSONL lines parse successfully!")
end

return T
