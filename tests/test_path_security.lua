local Helpers = dofile("tests/helpers.lua")

-- Unit tests for path security validation

local child = Helpers.new_child_neovim()

local T = MiniTest.new_set({
    hooks = {
        -- This will be executed before every (even nested) case
        pre_case = function()
            -- Restart child process with custom 'init.lua' script
            child.restart({ "-u", "scripts/minimal_init.lua" })
        end,
        -- This will be executed one after all tests from this set are finished
        post_once = child.stop,
    },
})

-- Tests for path traversal protection
T["path_traversal_protection"] = MiniTest.new_set()

T["path_traversal_protection"]["blocks_parent_directory_traversal"] = function()
    child.lua([[
        local PathSecurity = require('cc-tui.util.path_security')

        -- Test various path traversal attempts
        local safe1, err1 = PathSecurity.is_safe_claude_path("../../../etc/passwd")
        local safe2, err2 = PathSecurity.is_safe_claude_path("..\\..\\windows\\system32\\config\\sam")
        local safe3, err3 = PathSecurity.is_safe_claude_path("project/../../../home/user/.ssh/id_rsa")

        _G.all_blocked = not safe1 and not safe2 and not safe3
        _G.has_errors = err1 ~= nil and err2 ~= nil and err3 ~= nil
    ]])

    Helpers.expect.global(child, "_G.all_blocked", true)
    Helpers.expect.global(child, "_G.has_errors", true)
end

T["path_traversal_protection"]["blocks_absolute_paths"] = function()
    child.lua([[
        local PathSecurity = require('cc-tui.util.path_security')

        -- Test absolute path attempts
        local safe1, err1 = PathSecurity.is_safe_claude_path("/etc/passwd")
        local safe2, err2 = PathSecurity.is_safe_claude_path("/home/user/.bash_history")
        local safe3, err3 = PathSecurity.is_safe_claude_path("C:\\Windows\\System32\\config\\sam")

        _G.all_blocked = not safe1 and not safe2 and not safe3
        _G.has_errors = err1 ~= nil and err2 ~= nil and err3 ~= nil
    ]])

    Helpers.expect.global(child, "_G.all_blocked", true)
    Helpers.expect.global(child, "_G.has_errors", true)
end

T["path_traversal_protection"]["requires_jsonl_extension"] = function()
    child.lua([[
        local PathSecurity = require('cc-tui.util.path_security')

        -- Test non-JSONL files
        local safe1, err1 = PathSecurity.is_safe_claude_path("conversation.txt")
        local safe2, err2 = PathSecurity.is_safe_claude_path("conversation.json")
        local safe3, err3 = PathSecurity.is_safe_claude_path("conversation")

        _G.all_blocked = not safe1 and not safe2 and not safe3
        _G.has_errors = err1 ~= nil and err2 ~= nil and err3 ~= nil
    ]])

    Helpers.expect.global(child, "_G.all_blocked", true)
    Helpers.expect.global(child, "_G.has_errors", true)
end

T["path_traversal_protection"]["allows_valid_jsonl_files"] = function()
    child.lua([[
        local PathSecurity = require('cc-tui.util.path_security')

        -- Test valid JSONL file names
        local safe1, err1 = PathSecurity.is_safe_claude_path("conversation-2024-01-15.jsonl")
        local safe2, err2 = PathSecurity.is_safe_claude_path("my-conversation.jsonl")
        local safe3, err3 = PathSecurity.is_safe_claude_path("test.jsonl")

        _G.all_allowed = safe1 and safe2 and safe3
        _G.no_errors = err1 == nil and err2 == nil and err3 == nil
    ]])

    Helpers.expect.global(child, "_G.all_allowed", true)
    Helpers.expect.global(child, "_G.no_errors", true)
end

-- Tests for secure file reading
T["secure_file_reading"] = MiniTest.new_set()

T["secure_file_reading"]["blocks_unsafe_paths"] = function()
    child.lua([[
        local PathSecurity = require('cc-tui.util.path_security')

        -- Try to read unsafe paths
        local lines1, err1 = PathSecurity.read_conversation_file_safe("../../../etc/passwd")
        local lines2, err2 = PathSecurity.read_conversation_file_safe("/etc/hosts")

        _G.both_blocked = #lines1 == 0 and #lines2 == 0
        _G.has_errors = err1 ~= nil and err2 ~= nil
    ]])

    Helpers.expect.global(child, "_G.both_blocked", true)
    Helpers.expect.global(child, "_G.has_errors", true)
end

T["secure_file_reading"]["handles_nonexistent_files"] = function()
    child.lua([[
        local PathSecurity = require('cc-tui.util.path_security')

        -- Try to read non-existent file with valid path format
        local lines, err = PathSecurity.read_conversation_file_safe("nonexistent.jsonl")

        _G.empty_result = #lines == 0
        _G.has_error = err ~= nil
        _G.error_mentions_readable = err and err:find("not readable") ~= nil
    ]])

    Helpers.expect.global(child, "_G.empty_result", true)
    Helpers.expect.global(child, "_G.has_error", true)
    Helpers.expect.global(child, "_G.error_mentions_readable", true)
end

-- Tests for ConversationProvider security integration
T["conversation_provider_security"] = MiniTest.new_set()

T["conversation_provider_security"]["rejects_unsafe_paths"] = function()
    child.lua([[
        -- Don't set _G.MiniTest to test production security behavior
        local ConversationProvider = require('cc-tui.providers.conversation')

        -- Try to create provider with unsafe path
        local success1 = pcall(ConversationProvider.new, "../../../etc/passwd")
        local success2 = pcall(ConversationProvider.new, "/etc/hosts")
        local success3 = pcall(ConversationProvider.new, "conversation.txt")

        _G.all_rejected = not success1 and not success2 and not success3
    ]])

    Helpers.expect.global(child, "_G.all_rejected", true)
end

T["conversation_provider_security"]["accepts_safe_paths"] = function()
    child.lua([[
        -- Set up MiniTest global to simulate test environment
        _G.MiniTest = true

        local ConversationProvider = require('cc-tui.providers.conversation')

        -- Create provider with safe path (even if file doesn't exist)
        local success, provider_or_error = pcall(ConversationProvider.new, "test-conversation.jsonl")

        _G.creation_success = success
        _G.has_provider = success and (provider_or_error ~= nil)
        _G.error_if_any = success and "none" or tostring(provider_or_error)
    ]])

    Helpers.expect.global(child, "_G.creation_success", true)
    Helpers.expect.global(child, "_G.has_provider", true)
end

-- Tests for ProjectDiscovery security integration
T["project_discovery_security"] = MiniTest.new_set()

T["project_discovery_security"]["extract_metadata_blocks_unsafe_paths"] = function()
    child.lua([[
        local ProjectDiscovery = require('cc-tui.services.project_discovery')

        -- Try to extract metadata from unsafe paths
        local title1, count1 = ProjectDiscovery.extract_conversation_metadata("../../../etc/passwd")
        local title2, count2 = ProjectDiscovery.extract_conversation_metadata("/etc/hosts")

        _G.safe_failure = title1 == nil and count1 == 0 and title2 == nil and count2 == 0
    ]])

    Helpers.expect.global(child, "_G.safe_failure", true)
end

-- Integration test for complete security workflow
T["security_integration"] = MiniTest.new_set()

T["security_integration"]["full_workflow_security_test"] = function()
    child.lua([[
        -- Don't set _G.MiniTest to test production security behavior
        local ProjectDiscovery = require('cc-tui.services.project_discovery')
        local ConversationProvider = require('cc-tui.providers.conversation')

        _G.workflow_success = true
        _G.security_errors = {}

        -- Test 1: Try dangerous project names
        local safe_project = "normal-project-name"
        local unsafe_project = "../../../etc"

        local exists1 = ProjectDiscovery.project_exists(safe_project)  -- Should work (false but no error)
        local exists2 = ProjectDiscovery.project_exists(unsafe_project)  -- Should fail safely

        _G.safe_project_check = exists1 == false  -- Non-existent but valid check
        _G.unsafe_project_blocked = exists2 == false  -- Should be blocked

        -- Test 2: Try to access dangerous paths through conversation provider
        local provider_success = pcall(function()
            ConversationProvider.new("../../../etc/passwd")
        end)

        _G.provider_blocked = not provider_success

        -- Test 3: Try metadata extraction on dangerous paths
        local title, count = ProjectDiscovery.extract_conversation_metadata("/etc/hosts")
        _G.metadata_blocked = title == nil and count == 0
    ]])

    Helpers.expect.global(child, "_G.workflow_success", true)
    Helpers.expect.global(child, "_G.safe_project_check", true)
    Helpers.expect.global(child, "_G.unsafe_project_blocked", true)
    Helpers.expect.global(child, "_G.provider_blocked", true)
    Helpers.expect.global(child, "_G.metadata_blocked", true)
end

return T
