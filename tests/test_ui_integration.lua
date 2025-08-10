---@brief [[
--- Phase 3: UI Integration Testing
--- Tests end-to-end workflows between TabbedManager, Browse, and Current views
--- Validates real user workflows with actual conversation data
---@brief ]]

local Helpers = dofile("tests/helpers.lua")

local child = Helpers.new_child_neovim()

local T = MiniTest.new_set({
    hooks = {
        pre_case = function()
            child.restart({ "-u", "scripts/minimal_init.lua" })
            child.lua([[
                -- Initialize global state for integration tests
                _G.CcTui = _G.CcTui or {}
                _G.CcTui.config = _G.CcTui.config or {}

                -- Set up package path for tests
                package.path = "./lua/?.lua;" .. package.path

                require('cc-tui').setup({})
            ]])
        end,
        post_once = child.stop,
    },
})

-- Phase 3.1: TabbedManager Integration Tests
T["TabbedManager Integration"] = MiniTest.new_set()

-- RED: This should fail initially as we need to implement conversation loading integration
T["TabbedManager Integration"]["RED: Browse to Current workflow transfers conversation path"] = function()
    child.lua([[
        local TabbedManager = require("cc-tui.ui.tabbed_manager")

        -- Create tabbed manager starting in Browse tab
        local manager = TabbedManager.new({ default_tab = "browse" })
        manager:show()
        _G.test_manager = manager

        -- Verify Browse tab is active
        _G.initial_tab = manager.current_tab

        -- Get Browse view and simulate conversation selection
        local browse_view = manager.views.browse
        if browse_view and #browse_view.conversations > 0 then
            -- Select first available conversation
            browse_view.current_index = 1
            local selected_conv = browse_view.conversations[1]
            _G.selected_path = selected_conv.path

            -- Simulate conversation selection (should switch to Current tab)
            browse_view:select_current()

            -- Verify tab switched and conversation path is set
            _G.switched_to_current = manager.current_tab == "current"
            _G.conversation_path_set = manager.current_conversation_path == selected_conv.path

            -- Verify Current view received the conversation
            local current_view = manager.views.current
            _G.current_view_has_path = current_view and current_view.conversation_path == selected_conv.path
        else
            _G.no_conversations = true
        end
    ]])

    local initial_tab = child.lua_get("_G.initial_tab")
    local switched_to_current = child.lua_get("_G.switched_to_current")
    local conversation_path_set = child.lua_get("_G.conversation_path_set")
    local current_view_has_path = child.lua_get("_G.current_view_has_path")
    local no_conversations = child.lua_get("_G.no_conversations")

    if no_conversations then
        MiniTest.skip("No conversations available for integration test")
        return
    end

    Helpers.expect.equality(initial_tab, "browse")

    -- RED: These should fail as integration isn't implemented yet
    if not switched_to_current then
        error("FAIL (expected): Browse selection should switch to Current tab - integration not implemented")
    end

    if not conversation_path_set then
        error("FAIL (expected): TabbedManager should track conversation path - integration not implemented")
    end

    if not current_view_has_path then
        error("FAIL (expected): Current view should receive selected conversation path - integration not implemented")
    end

    -- Clean up
    child.lua("if _G.test_manager then _G.test_manager:close() end")
end

-- RED: Tab navigation should preserve state
T["TabbedManager Integration"]["RED: Tab switching preserves conversation context"] = function()
    child.lua([[
        local TabbedManager = require("cc-tui.ui.tabbed_manager")

        local manager = TabbedManager.new({ default_tab = "browse" })
        manager:show()
        _G.test_manager = manager

        local browse_view = manager.views.browse
        if browse_view and #browse_view.conversations > 0 then
            -- Select a conversation and switch to Current
            browse_view.current_index = 1
            local selected_conv = browse_view.conversations[1]
            browse_view:select_current()

            _G.current_tab_active = manager.current_tab == "current"
            _G.conversation_loaded = manager.current_conversation_path == selected_conv.path

            -- Switch to Logs tab
            manager:switch_to_tab("logs")
            _G.logs_tab_active = manager.current_tab == "logs"
            _G.conversation_preserved_in_logs = manager.current_conversation_path == selected_conv.path

            -- Switch back to Current tab
            manager:switch_to_tab("current")
            _G.back_to_current = manager.current_tab == "current"
            _G.conversation_still_loaded = manager.current_conversation_path == selected_conv.path

            -- Verify Current view still shows the selected conversation
            local current_view = manager.views.current
            _G.current_view_preserved = current_view and current_view.conversation_path == selected_conv.path
        else
            _G.no_conversations = true
        end
    ]])

    local no_conversations = child.lua_get("_G.no_conversations")
    if no_conversations then
        MiniTest.skip("No conversations available for integration test")
        return
    end

    local current_tab_active = child.lua_get("_G.current_tab_active")
    local conversation_loaded = child.lua_get("_G.conversation_loaded")
    local logs_tab_active = child.lua_get("_G.logs_tab_active")
    local conversation_preserved_in_logs = child.lua_get("_G.conversation_preserved_in_logs")
    local back_to_current = child.lua_get("_G.back_to_current")
    local conversation_still_loaded = child.lua_get("_G.conversation_still_loaded")
    local current_view_preserved = child.lua_get("_G.current_view_preserved")

    -- RED: These should fail as conversation context preservation isn't implemented
    if not current_tab_active then
        error("FAIL (expected): Should switch to Current tab after conversation selection")
    end

    if not conversation_loaded then
        error("FAIL (expected): Should load selected conversation in TabbedManager context")
    end

    if not conversation_preserved_in_logs then
        error("FAIL (expected): Should preserve conversation context when switching to Logs tab")
    end

    if not conversation_still_loaded then
        error("FAIL (expected): Should maintain conversation context when returning to Current tab")
    end

    if not current_view_preserved then
        error("FAIL (expected): Current view should preserve conversation after tab navigation")
    end

    -- Clean up
    child.lua("if _G.test_manager then _G.test_manager:close() end")
end

-- Phase 3.2: Data Loading Integration Tests
T["Data Loading Integration"] = MiniTest.new_set()

-- RED: Test conversation loading with large files
T["Data Loading Integration"]["RED: Loads large conversation files efficiently"] = function()
    -- Create a test file in /tmp which is allowed by path security
    local test_file = "/tmp/large_test_conversation.jsonl"
    local file = io.open(test_file, "w")
    if not file then
        MiniTest.skip("Cannot create test file in /tmp")
        return
    end

    -- Write a substantial amount of test data
    for i = 1, 1000 do
        local message = {
            type = "user",
            message = {
                content = {
                    {
                        type = "text",
                        text = "Test message "
                            .. i
                            .. " with substantial content that makes this file larger for performance testing purposes.",
                    },
                },
            },
            sessionId = "test-session-" .. math.floor(i / 10),
            parentUuid = "parent-" .. i,
            timestamp = os.time() + i,
        }
        file:write(vim.json.encode(message) .. "\n")
    end
    file:close()

    -- Get file size for testing
    local stat = vim.uv.fs_stat(test_file)
    if not stat or stat.size < 50000 then -- At least 50KB
        os.remove(test_file)
        MiniTest.skip("Test file too small for performance testing")
        return
    end

    local largest_file = { filepath = test_file, size_bytes = stat.size }

    child.lua(string.format(
        [[
        local TabbedManager = require("cc-tui.ui.tabbed_manager")
        local ConversationProvider = require("cc-tui.providers.conversation")

        -- Test direct conversation loading
        local provider = ConversationProvider.new("%s")
        local start_time = vim.loop.hrtime()
        local messages, error_msg = provider:load_conversation()
        local end_time = vim.loop.hrtime()

        _G.load_time_ms = (end_time - start_time) / 1000000
        _G.load_success = error_msg == nil
        _G.message_count = #messages
        _G.file_size = %d

        -- Test integration with TabbedManager
        local manager = TabbedManager.new({ default_tab = "current" })
        manager:show()

        -- Simulate loading the large file in Current view
        local current_view = manager.views.current
        if current_view and current_view.load_specific_conversation then
            local integration_start = vim.loop.hrtime()
            local success = pcall(current_view.load_specific_conversation, current_view, "%s")
            local integration_end = vim.loop.hrtime()

            _G.integration_time_ms = (integration_end - integration_start) / 1000000
            _G.integration_success = success
            _G.view_conversation_path = current_view.conversation_path
        else
            _G.integration_missing = true
        end

        manager:close()
    ]],
        largest_file.filepath,
        largest_file.size_bytes,
        largest_file.filepath
    ))

    local load_success = child.lua_get("_G.load_success")
    local message_count = child.lua_get("_G.message_count")
    local load_time_ms = child.lua_get("_G.load_time_ms")
    local file_size = child.lua_get("_G.file_size")
    local integration_missing = child.lua_get("_G.integration_missing")
    local integration_success = child.lua_get("_G.integration_success")
    local integration_time_ms = child.lua_get("_G.integration_time_ms")

    Helpers.expect.truthy(load_success, "Should successfully load large conversation file")
    Helpers.expect.truthy(message_count > 0, "Should parse messages from large file")

    -- Performance expectations (reasonable thresholds for large files)
    if load_time_ms > 5000 then -- 5 second threshold
        error(string.format("Large file loading too slow: %.2fms for %d bytes", load_time_ms, file_size))
    end

    -- RED: Integration functionality should fail as it's not implemented yet
    if integration_missing then
        error("FAIL (expected): Current view missing load_specific_conversation method - integration not implemented")
    end

    if not integration_success then
        error(
            "FAIL (expected): Current view should successfully load specific conversation - integration not implemented"
        )
    end

    if not integration_time_ms or integration_time_ms > 10000 then -- 10 second threshold for UI integration
        error("FAIL (expected): UI integration loading too slow or failed - optimization needed")
    end

    -- Clean up test file
    os.remove(test_file)
end

-- Phase 3.3: End-to-End Workflow Tests
T["End-to-End Workflows"] = MiniTest.new_set()

-- RED: Complete user workflow from Browse to Current with real data
T["End-to-End Workflows"]["RED: Complete Browse to Current workflow with real conversation"] = function()
    local real_data_loader = require("tests.helpers.real_data_loader")

    -- Validate real data is available
    local valid, err = real_data_loader.validate_real_data_available()
    if not valid then
        MiniTest.skip("Real conversation data not available: " .. (err or "unknown"))
        return
    end

    child.lua([[
        local TabbedManager = require("cc-tui.ui.tabbed_manager")

        -- Start the complete workflow
        local manager = TabbedManager.new({ default_tab = "browse" })
        manager:show()
        _G.test_manager = manager

        _G.workflow_steps = {}

        -- Step 1: Verify Browse tab shows conversations
        table.insert(_G.workflow_steps, {
            step = "browse_tab_active",
            success = manager.current_tab == "browse"
        })

        local browse_view = manager.views.browse
        local has_conversations = browse_view and #browse_view.conversations > 0

        table.insert(_G.workflow_steps, {
            step = "conversations_available",
            success = has_conversations
        })

        if has_conversations then
            -- Step 2: Select a conversation
            browse_view.current_index = 1
            local selected_conv = browse_view.conversations[1]
            _G.selected_conversation = {
                path = selected_conv.path,
                title = selected_conv.title or "Unknown"
            }

            -- Step 3: Trigger selection (should switch to Current tab and load conversation)
            browse_view:select_current()

            table.insert(_G.workflow_steps, {
                step = "switched_to_current",
                success = manager.current_tab == "current"
            })

            table.insert(_G.workflow_steps, {
                step = "manager_has_conversation_path",
                success = manager.current_conversation_path == selected_conv.path
            })

            -- Step 4: Verify Current view displays the selected conversation
            local current_view = manager.views.current
            if current_view then
                table.insert(_G.workflow_steps, {
                    step = "current_view_exists",
                    success = true
                })

                table.insert(_G.workflow_steps, {
                    step = "current_view_has_conversation_path",
                    success = current_view.conversation_path == selected_conv.path
                })

                table.insert(_G.workflow_steps, {
                    step = "current_view_has_data",
                    success = current_view.tree_data ~= nil
                })

                table.insert(_G.workflow_steps, {
                    step = "current_view_shows_real_data",
                    success = current_view.messages and #current_view.messages > 0
                })
            else
                table.insert(_G.workflow_steps, {
                    step = "current_view_exists",
                    success = false
                })
            end

            -- Step 5: Test return to Browse tab preserves selection
            manager:switch_to_tab("browse")

            table.insert(_G.workflow_steps, {
                step = "returned_to_browse",
                success = manager.current_tab == "browse"
            })

            table.insert(_G.workflow_steps, {
                step = "browse_selection_preserved",
                success = browse_view.current_index == 1
            })
        else
            _G.no_conversations_available = true
        end
    ]])

    local no_conversations = child.lua_get("_G.no_conversations_available")
    if no_conversations then
        MiniTest.skip("No conversations available for end-to-end workflow test")
        return
    end

    local workflow_steps = child.lua_get("_G.workflow_steps")
    local selected_conversation = child.lua_get("_G.selected_conversation")

    -- Verify each step of the workflow
    local failed_steps = {}
    for _, step in ipairs(workflow_steps) do
        if not step.success then
            table.insert(failed_steps, step.step)
        end
    end

    -- Report workflow results (RED: Many should fail as integration isn't implemented)
    if #failed_steps > 0 then
        local error_msg = "FAIL (expected): End-to-end workflow failed at steps: "
            .. table.concat(failed_steps, ", ")
            .. "\nSelected conversation: "
            .. (selected_conversation and selected_conversation.path or "none")
            .. "\nThis is expected - integration features not yet implemented"
        error(error_msg)
    end

    -- Clean up
    child.lua("if _G.test_manager then _G.test_manager:close() end")
end

return T
