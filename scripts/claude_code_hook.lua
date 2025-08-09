#!/usr/bin/env lua
---@brief [[
--- Claude Code Hook Script for cc-tui integration
--- This script demonstrates how to use cc-tui's StreamIntegrator with Claude Code hooks
---
--- To use this with Claude Code, add to your Claude Code settings:
--- {
---   "hooks": [
---     {
---       "command": ["lua", "/path/to/claude_code_hook.lua"],
---       "events": ["PostToolUse"]
---     }
---   ]
--- }
---@brief ]]

-- Add cc-tui to Lua path (adjust path as needed)
package.path = package.path .. ";/Users/kyle/Code/cc-tui-semantic-search/lua/?.lua"

local StreamIntegrator = require("cc-tui.integration.claude_code_stream")
local json = require("vim.fn").json_decode
local json_encode = require("vim.fn").json_encode

-- Parse command line arguments (Claude Code hook data comes via stdin)
local function read_stdin()
    local content = ""
    for line in io.lines() do
        content = content .. line
    end
    return content
end

-- Main hook processing function
local function process_claude_code_hook()
    -- Read hook data from stdin (JSON format from Claude Code)
    local stdin_content = read_stdin()
    if not stdin_content or stdin_content == "" then
        return { continue = true, reason = "No hook data provided" }
    end

    -- Parse hook data
    local success, hook_data = pcall(json, stdin_content)
    if not success then
        return { continue = true, reason = "Failed to parse hook data" }
    end

    -- Validate required fields
    if not hook_data.transcript_path or not hook_data.session_id then
        return { continue = true, reason = "Missing transcript_path or session_id" }
    end

    -- Process the transcript using cc-tui StreamIntegrator
    local processor = StreamIntegrator.create_stream_processor()
    local classification_count = 0

    -- Read and process the JSONL transcript
    local transcript_file = io.open(hook_data.transcript_path, "r")
    if transcript_file then
        for line in transcript_file:lines() do
            local result = processor:process_line(line)
            if result and result.classification then
                classification_count = classification_count + 1

                -- Example: Print classifications to stderr for debugging
                io.stderr:write(
                    string.format(
                        "[cc-tui] Classified %s: %s (%s)\n",
                        result.classification.type,
                        result.classification.metadata.tool_name or "unknown",
                        result.classification.display_strategy
                    )
                )
            end
        end
        transcript_file:close()
    end

    -- Get processing statistics
    local stats = processor:get_stats()

    -- Output statistics to stderr (won't affect Claude Code)
    io.stderr:write(
        string.format(
            "[cc-tui] Processed %d messages, %d classifications, %.2fms avg processing time\n",
            stats.total_messages,
            stats.total_classifications,
            stats.avg_processing_time_ms
        )
    )

    if stats.cache_hits > 0 then
        io.stderr:write(
            string.format(
                "[cc-tui] Cache hit rate: %.1f%% (%d hits, %d misses)\n",
                stats.cache_hit_rate * 100,
                stats.cache_hits,
                stats.cache_misses
            )
        )
    end

    -- Return success to Claude Code (JSON format expected by hooks)
    return {
        continue = true,
        reason = string.format("cc-tui processed %d classifications", classification_count),
    }
end

-- Execute the hook and return appropriate JSON response
local function main()
    local result = process_claude_code_hook()

    -- Output JSON response for Claude Code hooks system
    print(json_encode(result))

    -- Exit with appropriate code
    if result.continue then
        os.exit(0) -- Success
    else
        os.exit(2) -- Blocking error
    end
end

-- Run the hook
main()
