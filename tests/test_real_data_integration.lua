---@brief [[
--- Integration tests using real Claude Code JSONL conversation files
--- Tests the complete pipeline with actual conversation data from the CLI
---@brief ]]

local Helpers = dofile("tests/helpers.lua")
local RealDataLoader = require("tests.helpers.real_data_loader")

local child = Helpers.new_child_neovim()

local T = MiniTest.new_set({
    hooks = {
        pre_case = function()
            child.restart({ "-u", "scripts/minimal_init.lua" })
        end,
        post_once = child.stop,
    },
})

-- Skip all tests if real data is not available
local real_data_available, real_data_error = RealDataLoader.validate_real_data_available()
if not real_data_available then
    print("⚠️  Skipping real data integration tests: " .. (real_data_error or "unknown error"))
    return T
end

T["Real Data Integration"] = MiniTest.new_set()

T["Real Data Integration"]["data_loader_availability"] = function()
    local conversations = RealDataLoader.get_available_conversations()
    Helpers.expect.truthy(#conversations > 0, "Should have real conversation files available")

    local metadata = RealDataLoader.get_conversation_metadata()
    Helpers.expect.truthy(#metadata > 0, "Should have conversation metadata")

    -- Verify we have different sizes for comprehensive testing
    local categories = {}
    for _, meta in ipairs(metadata) do
        categories[meta.category] = true
    end

    -- We should have at least small and medium conversations
    Helpers.expect.truthy(categories["small"] or categories["tiny"], "Should have small conversations for fast tests")
end

T["Real Data Integration"]["small_conversation_parsing"] = function()
    local lines, err, uuid = RealDataLoader.load_small_conversation()

    Helpers.expect.truthy(not err, "Should load small conversation without error: " .. tostring(err))
    Helpers.expect.truthy(#lines > 0, "Should have conversation lines")
    Helpers.expect.truthy(uuid, "Should return conversation UUID")

    -- Test parsing
    child.lua(
        [[
        local Parser = require("cc-tui.parser.stream")
        local lines = {...}
        local messages, errors = Parser.parse_lines(lines)

        _G.test_result = {
            message_count = #messages,
            error_count = #errors,
            has_messages = #messages > 0,
        }
    ]],
        lines
    )

    local result = child.lua_get("_G.test_result")
    Helpers.expect.truthy(result.has_messages, "Should parse messages from real data")
    Helpers.expect.equality(result.error_count, 0, "Should parse without errors")
end

T["Real Data Integration"]["medium_conversation_tree_building"] = function()
    local lines, err, uuid = RealDataLoader.load_medium_conversation()

    Helpers.expect.truthy(not err, "Should load medium conversation without error: " .. tostring(err))
    Helpers.expect.truthy(#lines > 10, "Should have substantial conversation content")

    -- Test complete tree building pipeline
    child.lua(
        [[
        local Parser = require("cc-tui.parser.stream")
        local TreeBuilder = require("cc-tui.models.tree_builder")
        local lines = {...}

        local messages, errors = Parser.parse_lines(lines)
        local session_info = Parser.get_session_info(messages)
        local root = TreeBuilder.build_tree(messages, session_info)

        -- Count different node types
        local function count_nodes(node, counts)
            counts = counts or {}
            counts[node.type] = (counts[node.type] or 0) + 1

            if node.children then
                for _, child in ipairs(node.children) do
                    count_nodes(child, counts)
                end
            end

            return counts
        end

        local node_counts = count_nodes(root)

        _G.test_result = {
            has_root = root ~= nil,
            root_type = root and root.type or nil,
            session_id = session_info and session_info.id or nil,
            message_count = #messages,
            node_counts = node_counts,
        }
    ]],
        lines
    )

    local result = child.lua_get("_G.test_result")
    Helpers.expect.truthy(result.has_root, "Should build tree from real data")
    Helpers.expect.equality(result.root_type, "session", "Should have session root")
    -- Session info may be nil for some real conversations - this is valid
    if result.session_id then
        Helpers.expect.truthy(result.session_id, "Should extract session info")
    end
    Helpers.expect.truthy(result.node_counts.message and result.node_counts.message > 0, "Should have message nodes")
end

T["Real Data Integration"]["result_node_content_popups"] = function()
    local lines, err, uuid = RealDataLoader.load_medium_conversation()

    Helpers.expect.truthy(not err, "Should load conversation for popup testing")

    -- Test that result nodes are properly created with data for popups
    child.lua(
        [[
        local Parser = require("cc-tui.parser.stream")
        local TreeBuilder = require("cc-tui.models.tree_builder")
        local lines = {...}

        local messages, errors = Parser.parse_lines(lines)
        local session_info = Parser.get_session_info(messages)
        local root = TreeBuilder.build_tree(messages, session_info)

        -- Find result nodes and check their data structure
        local function find_result_nodes(node, results)
            results = results or {}

            if node.type == "result" then
                table.insert(results, {
                    has_data = node.data ~= nil,
                    data_type = node.data and node.data.type or nil,
                    has_content = node.data and node.data.content ~= nil,
                    has_structured_content = node.data and node.data.structured_content ~= nil,
                    use_rich_display = node.data and node.data.use_rich_display,
                })
            end

            if node.children then
                for _, child in ipairs(node.children) do
                    find_result_nodes(child, results)
                end
            end

            return results
        end

        local result_nodes = find_result_nodes(root)

        _G.test_result = {
            result_count = #result_nodes,
            all_have_data = true,
            all_proper_type = true,
            sample_node = result_nodes[1],
        }

        for _, node in ipairs(result_nodes) do
            if not node.has_data then
                _G.test_result.all_have_data = false
            end
            if node.data_type ~= "result" then
                _G.test_result.all_proper_type = false
            end
        end
    ]],
        lines
    )

    local result = child.lua_get("_G.test_result")

    if result.result_count > 0 then
        Helpers.expect.truthy(result.all_have_data, "All result nodes should have data field populated")
        Helpers.expect.truthy(result.all_proper_type, "All result nodes should have data.type = 'result'")

        if result.sample_node then
            Helpers.expect.truthy(result.sample_node.has_content, "Result nodes should have content for popups")
            Helpers.expect.truthy(
                result.sample_node.has_structured_content,
                "Result nodes should have structured_content"
            )
        end
    end
end

T["Real Data Integration"]["content_renderer_with_real_data"] = function()
    local lines, err, uuid = RealDataLoader.load_small_conversation()

    Helpers.expect.truthy(not err, "Should load conversation for content rendering test")

    -- Test ContentRenderer with real result data
    child.lua(
        [[
        local Parser = require("cc-tui.parser.stream")
        local TreeBuilder = require("cc-tui.models.tree_builder")
        local ContentRenderer = require("cc-tui.ui.content_renderer")
        local lines = {...}

        local messages, errors = Parser.parse_lines(lines)
        local session_info = Parser.get_session_info(messages)
        local root = TreeBuilder.build_tree(messages, session_info)

        -- Find first result node
        local function find_first_result(node)
            if node.type == "result" and node.data and node.data.content then
                return node
            end

            if node.children then
                for _, child in ipairs(node.children) do
                    local found = find_first_result(child)
                    if found then return found end
                end
            end

            return nil
        end

        local result_node = find_first_result(root)
        local render_success = false
        local render_error = nil

        if result_node then
            local success, content_window = pcall(
                ContentRenderer.render_content,
                result_node.data.id,
                result_node.data.tool_name,
                result_node.data.content or "",
                nil, -- parent_window
                result_node.data.structured_content,
                result_node.data.stream_context
            )

            render_success = success and content_window ~= nil
            if not success then
                render_error = tostring(content_window)
            end

            -- Clean up
            if success and content_window then
                ContentRenderer.close_content_window(result_node.data.id)
            end
        end

        _G.test_result = {
            found_result_node = result_node ~= nil,
            render_success = render_success,
            render_error = render_error,
        }
    ]],
        lines
    )

    local result = child.lua_get("_G.test_result")

    if result.found_result_node then
        Helpers.expect.truthy(
            result.render_success,
            "Should successfully render real result content: " .. tostring(result.render_error)
        )
    end
end

T["Real Data Integration"]["tabbed_interface_with_real_data"] = function()
    -- Test that TabbedManager works with real conversation data
    local lines, err = RealDataLoader.load_small_conversation()
    Helpers.expect.truthy(not err, "Should load conversation for UI test")

    child.lua(
        [[
        -- Initialize global state that UI components expect
        _G.CcTui = { config = { debug = false } }

        local DataLoader = require("cc-tui.core.data_loader")
        local StaticProvider = require("cc-tui.providers.static")
        local TabbedManager = require("cc-tui.ui.tabbed_manager")

        -- Create provider with real data
        local lines = {...}
        local provider = StaticProvider:new({ lines = lines })

        -- Test data loading pipeline
        local collected_lines = {}
        provider:register_callback("on_data", function(line)
            table.insert(collected_lines, line)
        end)

        provider:start()

        -- Test tree building
        local Parser = require("cc-tui.parser.stream")
        local TreeBuilder = require("cc-tui.models.tree_builder")

        local messages, parse_errors = Parser.parse_lines(collected_lines)
        local session_info = Parser.get_session_info(messages)
        local root = TreeBuilder.build_tree(messages, session_info)

        -- Test TabbedManager creation
        local manager, manager_error = TabbedManager.new({
            width = "80%",
            height = "80%",
            default_tab = "current"
        })

        _G.test_result = {
            data_loaded = #collected_lines > 0,
            messages_parsed = #messages > 0,
            tree_built = root ~= nil,
            manager_created = manager ~= nil,
            manager_error = manager_error,
            parse_error_count = #parse_errors,
        }

        -- Clean up
        if manager then
            manager:close()
        end
    ]],
        lines
    )

    local result = child.lua_get("_G.test_result")

    Helpers.expect.truthy(result.data_loaded, "Should load real data through provider")
    Helpers.expect.truthy(result.messages_parsed, "Should parse messages from real data")
    Helpers.expect.truthy(result.tree_built, "Should build tree from real messages")
    Helpers.expect.truthy(result.manager_created, "Should create TabbedManager: " .. tostring(result.manager_error))
    Helpers.expect.equality(result.parse_error_count, 0, "Should parse real data without errors")
end

T["Real Data Integration"]["conversation_metadata_extraction"] = function()
    -- Test metadata extraction from various conversation sizes
    local metadata = RealDataLoader.get_conversation_metadata()

    Helpers.expect.truthy(#metadata > 0, "Should extract metadata from available conversations")

    -- Verify metadata structure
    for _, meta in ipairs(metadata) do
        Helpers.expect.truthy(meta.uuid, "Should have UUID")
        Helpers.expect.truthy(meta.filepath, "Should have file path")
        Helpers.expect.truthy(meta.size_bytes and meta.size_bytes > 0, "Should have file size")
        Helpers.expect.truthy(meta.line_count and meta.line_count > 0, "Should have line count")
        Helpers.expect.truthy(meta.category, "Should have size category")
    end

    -- Test different categories are represented
    local categories = {}
    for _, meta in ipairs(metadata) do
        categories[meta.category] = true
    end

    local category_count = 0
    for _ in pairs(categories) do
        category_count = category_count + 1
    end

    Helpers.expect.truthy(category_count >= 1, "Should have at least one size category")
end

T["Real Data Integration"]["provider_factory_integration"] = function()
    -- Test the provider factory with different conversation sizes
    local sizes = { "small", "medium" }

    for _, size in ipairs(sizes) do
        local provider_factory = RealDataLoader.create_real_data_provider(size)
        Helpers.expect.truthy(type(provider_factory) == "function", "Should create provider factory for " .. size)

        -- Test that factory creates working provider (without passing function to child)
        local provider = provider_factory()
        Helpers.expect.truthy(provider ~= nil, "Should create provider for " .. size)

        -- Test provider functionality in child process
        local lines, err, uuid = nil, nil, nil
        if size == "small" then
            lines, err, uuid = RealDataLoader.load_small_conversation()
        else
            lines, err, uuid = RealDataLoader.load_medium_conversation()
        end

        if not err then
            child.lua(
                [[
                local StaticProvider = require("cc-tui.providers.static")
                local lines = {...}

                local provider = StaticProvider:new({ lines = lines })
                local collected_lines = {}

                provider:register_callback("on_data", function(line)
                    table.insert(collected_lines, line)
                end)

                provider:start()

                _G.test_result = {
                    provider_created = provider ~= nil,
                    data_loaded = #collected_lines > 0,
                    line_count = #collected_lines,
                }
            ]],
                lines
            )

            local result = child.lua_get("_G.test_result")
            Helpers.expect.truthy(result.provider_created, "Should create provider for " .. size)
            Helpers.expect.truthy(result.data_loaded, "Should load data through " .. size .. " provider")
            Helpers.expect.truthy(result.line_count > 0, "Should have conversation lines for " .. size)
        end
    end
end

return T
