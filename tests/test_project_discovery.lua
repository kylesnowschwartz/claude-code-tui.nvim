local Helpers = dofile("tests/helpers.lua")

-- Unit tests for project discovery service using red/green TDD approach

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

-- Tests for project name mapping functionality
T["get_project_name"] = MiniTest.new_set()

T["get_project_name"]["basic directory mapping"] = function()
    child.lua([[
        local ProjectDiscovery = require('cc-tui.services.project_discovery')

        -- Test basic path without special characters
        _G.result1 = ProjectDiscovery.get_project_name("/Users/kyle/Code/simple-project")

        -- Test path with multiple slashes
        _G.result2 = ProjectDiscovery.get_project_name("/home/user/dev/my-app")

        -- Test path with dots in directory names
        _G.result3 = ProjectDiscovery.get_project_name("/Users/kyle/Code/cc-tui.nvim")

        -- Test Windows-style paths
        _G.result4 = ProjectDiscovery.get_project_name("C:\\Users\\kyle\\Code\\project")
    ]])

    Helpers.expect.global(child, "_G.result1", "-Users-kyle-Code-simple-project")
    Helpers.expect.global(child, "_G.result2", "-home-user-dev-my-app")
    Helpers.expect.global(child, "_G.result3", "-Users-kyle-Code-cc-tui-nvim")
    Helpers.expect.global(child, "_G.result4", "C:\\Users\\kyle\\Code\\project")
end

T["get_project_name"]["handles edge cases"] = function()
    child.lua([[
        local ProjectDiscovery = require('cc-tui.services.project_discovery')

        -- Test empty path
        local success1, result1 = pcall(ProjectDiscovery.get_project_name, "")
        _G.empty_path_result = success1 and result1 or nil

        -- Test root path
        _G.root_result = ProjectDiscovery.get_project_name("/")

        -- Test path with consecutive dots and slashes
        _G.complex_result = ProjectDiscovery.get_project_name("/Users/kyle/.config/nvim/../.dotfiles")

        -- Test path with multiple dots in filename
        _G.dotfile_result = ProjectDiscovery.get_project_name("/Users/kyle/.config/app.config.json")
    ]])

    Helpers.expect.global(child, "_G.empty_path_result", "")
    Helpers.expect.global(child, "_G.root_result", "-")
    Helpers.expect.global(child, "_G.complex_result", "-Users-kyle--config-nvim-----dotfiles")
    Helpers.expect.global(child, "_G.dotfile_result", "-Users-kyle--config-app-config-json")
end

T["get_project_name"]["validates input"] = function()
    child.lua([[
        local ProjectDiscovery = require('cc-tui.services.project_discovery')

        -- Test nil input
        local success1 = pcall(ProjectDiscovery.get_project_name, nil)
        _G.nil_handled = not success1

        -- Test non-string input
        local success2 = pcall(ProjectDiscovery.get_project_name, 123)
        _G.number_handled = not success2

        -- Test table input
        local success3 = pcall(ProjectDiscovery.get_project_name, {})
        _G.table_handled = not success3
    ]])

    Helpers.expect.global(child, "_G.nil_handled", true)
    Helpers.expect.global(child, "_G.number_handled", true)
    Helpers.expect.global(child, "_G.table_handled", true)
end

-- Tests for project path generation
T["get_project_path"] = MiniTest.new_set()

T["get_project_path"]["generates correct paths"] = function()
    child.lua([[
        local ProjectDiscovery = require('cc-tui.services.project_discovery')
        local Config = require('cc-tui.config')

        -- Test with default configuration (production behavior)
        -- Temporarily override to test production paths regardless of testing mode
        local original_is_testing = Config.is_testing_mode
        Config.is_testing_mode = function() return false end

        _G.path1 = ProjectDiscovery.get_project_path("my-project")
        _G.path2 = ProjectDiscovery.get_project_path("-Users-kyle-Code-cc-tui-nvim")
        _G.home_path = vim.fn.expand("~")

        -- Restore original function
        Config.is_testing_mode = original_is_testing
    ]])

    local home_path = child.lua_get("_G.home_path")
    Helpers.expect.global(child, "_G.path1", home_path .. "/.claude/projects/my-project")
    Helpers.expect.global(child, "_G.path2", home_path .. "/.claude/projects/-Users-kyle-Code-cc-tui-nvim")
end

T["get_project_path"]["validates input"] = function()
    child.lua([[
        local ProjectDiscovery = require('cc-tui.services.project_discovery')
        local Config = require('cc-tui.config')

        -- Test with default configuration (production behavior)
        local original_is_testing = Config.is_testing_mode
        Config.is_testing_mode = function() return false end

        -- Test nil project name
        local success1 = pcall(ProjectDiscovery.get_project_path, nil)
        _G.nil_handled = not success1

        -- Test empty string
        local success2 = pcall(ProjectDiscovery.get_project_path, "")
        _G.empty_handled = success2 -- Should work, but might not be useful
        _G.empty_result = ProjectDiscovery.get_project_path("")

        -- Restore original function
        Config.is_testing_mode = original_is_testing
    ]])

    Helpers.expect.global(child, "_G.nil_handled", true)
    Helpers.expect.global(child, "_G.empty_handled", true)
    Helpers.expect.match(child.lua_get("_G.empty_result"), "/.claude/projects/$")
end

-- Tests for project existence checking
T["project_exists"] = MiniTest.new_set()

T["project_exists"]["checks directory existence"] = function()
    child.lua([[
        local ProjectDiscovery = require('cc-tui.services.project_discovery')

        -- Test non-existent project
        _G.nonexistent = ProjectDiscovery.project_exists("definitely-does-not-exist-12345")

        -- Test with empty project name
        _G.empty_project = ProjectDiscovery.project_exists("")
        _G.empty_project_path = ProjectDiscovery.get_project_path("")
        _G.empty_project_exists = vim.fn.isdirectory(_G.empty_project_path) == 1

        -- Create a test directory to verify positive case
        local home = vim.fn.expand("~")
        local test_project_path = home .. "/.claude/projects/test-project-for-unit-tests"

        -- Ensure parent directory exists
        vim.fn.mkdir(home .. "/.claude/projects", "p")

        -- Create test project directory
        vim.fn.mkdir(test_project_path, "p")
        _G.created_test_dir = vim.fn.isdirectory(test_project_path) == 1

        -- Test existing project BEFORE cleanup
        _G.existing = ProjectDiscovery.project_exists("test-project-for-unit-tests")
        _G.test_path_exists = vim.fn.isdirectory(test_project_path) == 1

        -- Debug the project path calculation
        _G.debug_project_path = ProjectDiscovery.get_project_path("test-project-for-unit-tests")
        _G.debug_actual_path = test_project_path
        _G.debug_paths_match = (_G.debug_project_path == _G.debug_actual_path)

        -- Clean up test directory after tests
        vim.fn.delete(test_project_path, "rf")
    ]])

    Helpers.expect.global(child, "_G.nonexistent", false)
    local empty_project_path = child.lua_get("_G.empty_project_path")
    local empty_project_exists = child.lua_get("_G.empty_project_exists")
    -- Empty project name resolves to the .claude/projects directory itself, which exists
    -- So this should actually be true, not false
    Helpers.expect.global(child, "_G.empty_project", true)
    Helpers.expect.global(child, "_G.created_test_dir", true)
    Helpers.expect.global(child, "_G.existing", true)
    -- Also verify that the path was actually created correctly
    Helpers.expect.global(child, "_G.test_path_exists", true)
    -- Debug info
    local debug_project_path = child.lua_get("_G.debug_project_path")
    local debug_actual_path = child.lua_get("_G.debug_actual_path")
    local debug_paths_match = child.lua_get("_G.debug_paths_match")
    if not debug_paths_match then
        print("DEBUG: Project path mismatch")
        print("Expected:", debug_actual_path)
        print("Got:     ", debug_project_path)
    end
    Helpers.expect.global(child, "_G.debug_paths_match", true)
end

-- Tests for conversation listing
T["list_conversations"] = MiniTest.new_set()

T["list_conversations"]["handles non-existent project"] = function()
    child.lua([[
        local ProjectDiscovery = require('cc-tui.services.project_discovery')

        -- Test non-existent project
        _G.result = ProjectDiscovery.list_conversations("definitely-does-not-exist-12345")
        _G.result_type = type(_G.result)
        _G.result_length = #_G.result
    ]])

    Helpers.expect.global(child, "_G.result_type", "table")
    Helpers.expect.global(child, "_G.result_length", 0)
end

T["list_conversations"]["returns conversation metadata"] = function()
    child.lua([[
        local ProjectDiscovery = require('cc-tui.services.project_discovery')

        -- Create test project with sample conversations
        local home = vim.fn.expand("~")
        local test_project_path = home .. "/.claude/projects/test-conversations-project"

        -- Ensure directory exists
        vim.fn.mkdir(test_project_path, "p")

        -- Create test conversation files
        local conv1_path = test_project_path .. "/conversation-2024-01-15T10-30-45.jsonl"
        local conv2_path = test_project_path .. "/conversation-2024-01-16T14-20-30.jsonl"
        local non_conv_path = test_project_path .. "/not-a-conversation.txt"

        -- Write test JSONL content
        local test_content1 = '{"type":"user","message":{"content":[{"type":"text","text":"Hello world test"}]}}'
        local test_content2 = '{"type":"assistant","message":{"content":[{"type":"text","text":"Hello response"}]}}'

        local file1 = io.open(conv1_path, "w")
        file1:write(test_content1 .. "\n")
        file1:write(test_content2 .. "\n")
        file1:close()

        local file2 = io.open(conv2_path, "w")
        file2:write(test_content1 .. "\n")
        file2:close()

        local file3 = io.open(non_conv_path, "w")
        file3:write("not a jsonl file\n")
        file3:close()

        -- Test conversation listing
        _G.conversations = ProjectDiscovery.list_conversations("test-conversations-project")
        _G.conv_count = #_G.conversations

        if #_G.conversations > 0 then
            _G.first_conv = _G.conversations[1]
            _G.has_filename = _G.first_conv.filename ~= nil
            _G.has_path = _G.first_conv.path ~= nil
            _G.has_timestamp = _G.first_conv.timestamp ~= nil
            _G.has_size = _G.first_conv.size ~= nil
            _G.has_modified = _G.first_conv.modified ~= nil
        end

        -- Clean up test directory
        vim.fn.delete(test_project_path, "rf")
    ]])

    Helpers.expect.global(child, "_G.conv_count", 2) -- Only JSONL files should be counted
    Helpers.expect.global(child, "_G.has_filename", true)
    Helpers.expect.global(child, "_G.has_path", true)
    Helpers.expect.global(child, "_G.has_timestamp", true)
    Helpers.expect.global(child, "_G.has_size", true)
    Helpers.expect.global(child, "_G.has_modified", true)
end

-- Tests for metadata extraction
T["extract_conversation_metadata"] = MiniTest.new_set()

T["extract_conversation_metadata"]["extracts title and message count"] = function()
    child.lua([[
        local ProjectDiscovery = require('cc-tui.services.project_discovery')

        -- Create temporary test file
        local temp_file = vim.fn.tempname() .. ".jsonl"

        local test_content = {
            '{"type":"user","message":{"content":[{"type":"text","text":"This is the first user message that should become the title"}]}}',
            '{"type":"assistant","message":{"content":[{"type":"text","text":"Assistant response"}]}}',
            '{"type":"user","message":{"content":[{"type":"text","text":"Second user message"}]}}',
        }

        local file = io.open(temp_file, "w")
        for _, line in ipairs(test_content) do
            file:write(line .. "\n")
        end
        file:close()

        -- Test metadata extraction
        _G.title, _G.message_count = ProjectDiscovery.extract_conversation_metadata_sync(temp_file)

        -- Clean up
        vim.fn.delete(temp_file)
    ]])

    Helpers.expect.global(child, "_G.message_count", 3)
    Helpers.expect.match(child.lua_get("_G.title"), "This is the first user message")
end

T["extract_conversation_metadata"]["handles real Claude CLI format"] = function()
    child.lua([[
        local ProjectDiscovery = require('cc-tui.services.project_discovery')

        -- Create temporary test file with real Claude CLI format (string content)
        local temp_file = vim.fn.tempname() .. ".jsonl"

        local claude_cli_content = {
            '{"type":"user","message":{"content":"What is the capital of France?"}}',
            '{"type":"assistant","message":{"content":"The capital of France is Paris."}}',
            '{"type":"user","message":{"content":"Tell me more about it."}}',
        }

        local file = io.open(temp_file, "w")
        for _, line in ipairs(claude_cli_content) do
            file:write(line .. "\n")
        end
        file:close()

        -- Test metadata extraction with Claude CLI format
        _G.claude_title, _G.claude_count = ProjectDiscovery.extract_conversation_metadata_sync(temp_file)

        -- Clean up
        vim.fn.delete(temp_file)
    ]])

    Helpers.expect.global(child, "_G.claude_count", 3)
    Helpers.expect.match(child.lua_get("_G.claude_title"), "What is the capital of France")
end

T["extract_conversation_metadata"]["handles empty and invalid files"] = function()
    child.lua([[
        local ProjectDiscovery = require('cc-tui.services.project_discovery')

        -- Test non-existent file
        _G.title1, _G.count1 = ProjectDiscovery.extract_conversation_metadata_sync("/non/existent/file.jsonl")

        -- Test empty file
        local empty_file = vim.fn.tempname() .. ".jsonl"
        local file = io.open(empty_file, "w")
        file:close()

        _G.title2, _G.count2 = ProjectDiscovery.extract_conversation_metadata_sync(empty_file)

        -- Clean up
        vim.fn.delete(empty_file)
    ]])

    Helpers.expect.global(child, "_G.title1", vim.NIL) -- nil in Lua becomes vim.NIL in child process
    Helpers.expect.global(child, "_G.count1", 0)
    Helpers.expect.global(child, "_G.title2", vim.NIL)
    Helpers.expect.global(child, "_G.count2", 0)
end

-- Tests for conversation display formatting
T["format_conversation_display"] = MiniTest.new_set()

T["format_conversation_display"]["formats display text correctly"] = function()
    child.lua([[
        local ProjectDiscovery = require('cc-tui.services.project_discovery')

        -- Test conversation with full metadata
        local conversation = {
            title = "Test conversation title",
            message_count = 15,
            timestamp = "2024-01-15T10:30:45",
            size = 2048,
        }

        _G.formatted1 = ProjectDiscovery.format_conversation_display(conversation)

        -- Test conversation with large file size
        local large_conversation = {
            title = "Large conversation",
            message_count = 100,
            timestamp = "2024-01-16T14:20:30",
            size = 1024 * 1024 * 2.5, -- 2.5MB
        }

        _G.formatted2 = ProjectDiscovery.format_conversation_display(large_conversation)

        -- Test conversation with missing optional data
        local minimal_conversation = {
            size = 512,
        }

        _G.formatted3 = ProjectDiscovery.format_conversation_display(minimal_conversation)
    ]])

    local formatted1 = child.lua_get("_G.formatted1")
    local formatted2 = child.lua_get("_G.formatted2")
    local formatted3 = child.lua_get("_G.formatted3")

    Helpers.expect.match(formatted1, "Test conversation title %(15 msgs%)")
    Helpers.expect.match(formatted1, "01/15 10:30")
    Helpers.expect.match(formatted1, "2%.0KB")

    Helpers.expect.match(formatted2, "2%.5MB")
    Helpers.expect.match(formatted2, "%(100 msgs%)")

    Helpers.expect.match(formatted3, "Loading%.%.%.")
    Helpers.expect.match(formatted3, "512B")
end

-- Integration test for the actual cc-tui.nvim project
T["integration"] = MiniTest.new_set()

T["integration"]["maps current project correctly"] = function()
    child.lua([[
        local ProjectDiscovery = require('cc-tui.services.project_discovery')

        -- Test with the actual cc-tui.nvim project path from the test environment
        local test_cwd = "/Users/kyle/Code/cc-tui.nvim"
        _G.mapped_name = ProjectDiscovery.get_project_name(test_cwd)

        -- Test with production configuration
        local Config = require('cc-tui.config')
        local original_is_testing = Config.is_testing_mode
        Config.is_testing_mode = function() return false end

        _G.project_path = ProjectDiscovery.get_project_path(_G.mapped_name)

        -- Restore original function
        Config.is_testing_mode = original_is_testing

        -- Test if the mapped project would exist (this might fail if Claude CLI hasn't been used)
        _G.would_exist = ProjectDiscovery.project_exists(_G.mapped_name)
    ]])

    Helpers.expect.global(child, "_G.mapped_name", "-Users-kyle-Code-cc-tui-nvim")
    local project_path = child.lua_get("_G.project_path")
    Helpers.expect.match(project_path, "%.claude/projects/.*Users.*kyle.*Code.*cc.*tui.*nvim")

    -- Note: would_exist might be false if no Claude CLI conversations exist for this project
    -- This is expected and not a test failure
end

return T
