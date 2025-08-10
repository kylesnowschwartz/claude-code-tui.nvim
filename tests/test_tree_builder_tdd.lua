---@brief [[
--- TDD-driven Tree Builder Tests using Real Conversation Data
--- Implements Phase 2 of TEST_REFACTORING_PLAN.md - Tree Building Validation
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

-- Helper function to parse messages from provider
local function parse_messages_from_provider(provider)
    local lines = provider:get_lines()
    local messages = {}

    for _, line in ipairs(lines) do
        local parsed = child.lua_get([[require('cc-tui.parser.stream').parse_line(...) ]], { line })
        if parsed then
            table.insert(messages, parsed)
        end
    end

    return messages
end

-- TDD CYCLE 1: Basic Tree Construction
T["build_tree - Message Hierarchy Creation"] = function()
    local cycle = TddFramework.create_cycle({
        description = "Build conversation tree with proper message hierarchy",
        category = "small", -- Small files for consistent tree structure testing
        setup = function(state)
            child.lua([[
                _G.TreeBuilder = require('cc-tui.models.tree_builder')
                _G.Parser = require('cc-tui.parser.stream')
            ]])
        end,
    })

    -- RED: Define expected tree structure for conversations
    local test_fn = function(state)
        local messages = parse_messages_from_provider(state.provider)
        TddFramework.expect(#messages).to_not_equal(0)

        -- Get session info and build tree
        local session_info = child.lua_get([[_G.Parser.get_session_info(...) ]], { messages })
        local root = child.lua_get([[_G.TreeBuilder.build_tree(...) ]], { messages, session_info })

        -- Validate root node structure
        TddFramework.expect(root).to_not_be_nil()
        TddFramework.expect(root.type).to_equal("root")
        TddFramework.expect(root.children).to_not_be_nil()
        TddFramework.expect(type(root.children)).to_equal("table")

        -- Validate tree has message nodes
        local has_message_nodes = false
        if #root.children > 0 then
            for _, child_node in ipairs(root.children) do
                if child_node.type == "message" then
                    has_message_nodes = true
                    TddFramework.expect(child_node.data).to_not_be_nil()
                    TddFramework.expect(child_node.data.message).to_not_be_nil()
                    break
                end
            end
        end

        TddFramework.expect(has_message_nodes).to_be_truthy()
    end

    cycle.red(test_fn)
end

T["build_tree - Tool Call Nesting"] = function()
    local cycle = TddFramework.create_cycle({
        description = "Create proper tool call node organization",
        category = "medium", -- Medium files likely have tool calls
        setup = function(state)
            child.lua([[
                _G.TreeBuilder = require('cc-tui.models.tree_builder')
                _G.Parser = require('cc-tui.parser.stream')
            ]])
        end,
    })

    -- RED: Define expected tool call node organization
    local test_fn = function(state)
        local messages = parse_messages_from_provider(state.provider)

        -- Find messages with tool calls
        local has_tool_calls = false
        for _, msg in ipairs(messages) do
            if msg.type == "assistant" and msg.message.content then
                for _, content in ipairs(msg.message.content) do
                    if content.type == "tool_use" then
                        has_tool_calls = true
                        break
                    end
                end
                if has_tool_calls then
                    break
                end
            end
        end

        -- Skip if no tool calls in this conversation
        if not has_tool_calls then
            MiniTest.skip("No tool calls found in selected conversation")
        end

        -- Build tree
        local session_info = child.lua_get([[_G.Parser.get_session_info(...) ]], { messages })
        local root = child.lua_get([[_G.TreeBuilder.build_tree(...) ]], { messages, session_info })

        -- Search for tool nodes in tree
        local function find_tool_nodes(node, tool_nodes)
            tool_nodes = tool_nodes or {}
            if node.type == "tool" then
                table.insert(tool_nodes, node)
            end
            if node.children then
                for _, child_node in ipairs(node.children) do
                    find_tool_nodes(child_node, tool_nodes)
                end
            end
            return tool_nodes
        end

        local tool_nodes = find_tool_nodes(root)
        TddFramework.expect(#tool_nodes).to_not_equal(0)

        -- Validate tool node structure
        for _, tool_node in ipairs(tool_nodes) do
            TddFramework.expect(tool_node.data).to_not_be_nil()
            TddFramework.expect(tool_node.data.tool_name).to_not_be_nil()
            TddFramework.expect(tool_node.data.tool_id).to_not_be_nil()
        end
    end

    cycle.red(test_fn)
end

T["build_tree - Message Order Preservation"] = function()
    local cycle = TddFramework.create_cycle({
        description = "Preserve chronological message ordering in tree",
        category = "small",
        setup = function(state)
            child.lua([[
                _G.TreeBuilder = require('cc-tui.models.tree_builder')
                _G.Parser = require('cc-tui.parser.stream')
            ]])
        end,
    })

    -- RED: Define expected chronological ordering
    local test_fn = function(state)
        local messages = parse_messages_from_provider(state.provider)
        TddFramework.expect(#messages > 1).to_be_truthy() -- Need multiple messages

        -- Build tree
        local session_info = child.lua_get([[_G.Parser.get_session_info(...) ]], { messages })
        local root = child.lua_get([[_G.TreeBuilder.build_tree(...) ]], { messages, session_info })

        -- Collect message nodes in tree order
        local function collect_message_nodes(node, nodes)
            nodes = nodes or {}
            if node.type == "message" then
                table.insert(nodes, node)
            end
            if node.children then
                for _, child_node in ipairs(node.children) do
                    collect_message_nodes(child_node, nodes)
                end
            end
            return nodes
        end

        local tree_message_nodes = collect_message_nodes(root)
        TddFramework.expect(#tree_message_nodes).to_not_equal(0)

        -- Validate chronological order by checking timestamps or UUIDs
        -- Tree should maintain the same order as original messages
        for i, tree_node in ipairs(tree_message_nodes) do
            if i <= #messages and messages[i] then
                -- Tree node should correspond to original message
                TddFramework.expect(tree_node.data.uuid).to_equal(messages[i].uuid)
            end
        end
    end

    cycle.red(test_fn)
end

T["build_tree - Node Expand/Collapse Support"] = function()
    local cycle = TddFramework.create_cycle({
        description = "Support tree interaction expand/collapse operations",
        category = "tiny", -- Fast tests for UI interaction
        setup = function(state)
            child.lua([[
                _G.TreeBuilder = require('cc-tui.models.tree_builder')
                _G.Parser = require('cc-tui.parser.stream')
            ]])
        end,
    })

    -- RED: Define expected tree interaction behavior
    local test_fn = function(state)
        local messages = parse_messages_from_provider(state.provider)
        local session_info = child.lua_get([[_G.Parser.get_session_info(...) ]], { messages })
        local root = child.lua_get([[_G.TreeBuilder.build_tree(...) ]], { messages, session_info })

        -- Validate expandable node properties
        local function validate_node_interactivity(node)
            -- Every node should have expand/collapse state
            TddFramework.expect(node.expanded ~= nil).to_be_truthy()

            -- Nodes with children should be expandable
            if node.children and #node.children > 0 then
                -- Should have expand/collapse capability
                TddFramework.expect(type(node.expanded)).to_equal("boolean")
            end

            -- Check children recursively
            if node.children then
                for _, child_node in ipairs(node.children) do
                    validate_node_interactivity(child_node)
                end
            end
        end

        validate_node_interactivity(root)
    end

    cycle.red(test_fn)
end

T["build_tree - Complex Conversation Structure"] = function()
    local cycle = TddFramework.create_cycle({
        description = "Handle complex conversation with nested tool calls and results",
        category = "large", -- Large files likely have complex structures
        setup = function(state)
            child.lua([[
                _G.TreeBuilder = require('cc-tui.models.tree_builder')
                _G.Parser = require('cc-tui.parser.stream')
            ]])
        end,
    })

    -- RED: Define expected complex structure handling
    local test_fn = function(state)
        local messages = parse_messages_from_provider(state.provider)
        local session_info = child.lua_get([[_G.Parser.get_session_info(...) ]], { messages })
        local root = child.lua_get([[_G.TreeBuilder.build_tree(...) ]], { messages, session_info })

        -- Validate tree depth and complexity
        local function measure_tree_complexity(node, depth, stats)
            depth = depth or 0
            stats = stats
                or {
                    max_depth = 0,
                    total_nodes = 0,
                    node_types = {},
                    tool_call_pairs = 0,
                }

            stats.total_nodes = stats.total_nodes + 1
            stats.max_depth = math.max(stats.max_depth, depth)

            -- Count node types
            stats.node_types[node.type] = (stats.node_types[node.type] or 0) + 1

            -- Count tool call/result pairs
            if node.type == "tool" and node.data and node.data.has_result then
                stats.tool_call_pairs = stats.tool_call_pairs + 1
            end

            -- Recurse into children
            if node.children then
                for _, child_node in ipairs(node.children) do
                    measure_tree_complexity(child_node, depth + 1, stats)
                end
            end

            return stats
        end

        local stats = measure_tree_complexity(root)

        -- Validate complexity metrics
        TddFramework.expect(stats.total_nodes > 1).to_be_truthy()
        TddFramework.expect(stats.node_types.root).to_equal(1) -- Exactly one root
        TddFramework.expect(stats.node_types.message or 0).to_not_equal(0) -- Has messages

        -- Tree should not be too shallow or too deep
        TddFramework.expect(stats.max_depth > 0).to_be_truthy()
        TddFramework.expect(stats.max_depth < 50).to_be_truthy() -- Reasonable depth limit
    end

    cycle.red(test_fn)
end

-- REMOVED: Performance tests are premature optimization
-- Following "make it work, make it right, make it fast" principle
-- Performance testing will be added in future "Make It Fast" phase

-- ERROR HANDLING TESTS
T["build_tree - Empty Messages Handling"] = function()
    local cycle = TddFramework.create_cycle({
        description = "Handle edge cases like empty message arrays",
        category = "tiny",
        setup = function(state)
            child.lua([[
                _G.TreeBuilder = require('cc-tui.models.tree_builder')
                _G.Parser = require('cc-tui.parser.stream')
            ]])
        end,
    })

    -- RED: Define edge case handling behavior
    local test_fn = function(state)
        -- Test with empty messages
        local empty_messages = {}
        local session_info = { session_id = "test", message_count = 0 }

        local root = child.lua_get([[_G.TreeBuilder.build_tree(...) ]], { empty_messages, session_info })

        -- Should create valid empty tree
        TddFramework.expect(root).to_not_be_nil()
        TddFramework.expect(root.type).to_equal("root")
        TddFramework.expect(root.children).to_not_be_nil()
        TddFramework.expect(#root.children).to_equal(0) -- Empty tree
    end

    cycle.red(test_fn)
end

return T
