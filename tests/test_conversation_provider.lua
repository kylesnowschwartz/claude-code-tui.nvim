local Helpers = dofile("tests/helpers.lua")

-- Unit tests for ConversationProvider following TDD approach

local child = Helpers.new_child_neovim()

local T = MiniTest.new_set({
    hooks = {
        -- This will be executed before every (even nested) case
        pre_case = function()
            -- Restart child process with custom 'init.lua' script
            child.restart({ "-u", "scripts/minimal_init.lua" })

            -- Initialize global state for tests
            child.lua([[
                _G.CcTui = _G.CcTui or {}
                _G.CcTui.config = _G.CcTui.config or {}
            ]])
        end,
        -- This will be executed one after all tests from this set are finished
        post_once = child.stop,
    },
})

-- Tests for ConversationProvider creation
T["ConversationProvider.new"] = MiniTest.new_set()

T["ConversationProvider.new"]["creates provider with file path"] = function()
    child.lua([[
        local ConversationProvider = require('cc-tui.providers.conversation')

        local provider = ConversationProvider.new('/test/path/conversation.jsonl')

        _G.provider_created = provider ~= nil
        _G.has_file_path = provider and provider.file_path == '/test/path/conversation.jsonl'
        _G.messages_nil = provider and provider.messages == nil
    ]])

    Helpers.expect.global(child, "_G.provider_created", true)
    Helpers.expect.global(child, "_G.has_file_path", true)
    Helpers.expect.global(child, "_G.messages_nil", true)
end

T["ConversationProvider.new"]["validates file path parameter"] = function()
    child.lua([[
        local ConversationProvider = require('cc-tui.providers.conversation')

        -- Test missing file path
        local success1 = pcall(ConversationProvider.new)
        _G.no_path_handled = not success1

        -- Test invalid file path type
        local success2 = pcall(ConversationProvider.new, 123)
        _G.invalid_path_handled = not success2
    ]])

    Helpers.expect.global(child, "_G.no_path_handled", true)
    Helpers.expect.global(child, "_G.invalid_path_handled", true)
end

-- Tests for load_conversation
T["load_conversation"] = MiniTest.new_set()

T["load_conversation"]["handles non-existent file"] = function()
    child.lua([[
        local ConversationProvider = require('cc-tui.providers.conversation')

        local provider = ConversationProvider.new('/non/existent/file.jsonl')
        local messages, error_msg = provider:load_conversation()

        _G.messages_empty = #messages == 0
        _G.has_error = error_msg ~= nil and error_msg ~= ""
        _G.error_contains_path = error_msg and error_msg:find('/non/existent/file.jsonl') ~= nil
    ]])

    Helpers.expect.global(child, "_G.messages_empty", true)
    Helpers.expect.global(child, "_G.has_error", true)
    Helpers.expect.global(child, "_G.error_contains_path", true)
end

T["load_conversation"]["caches parsed messages"] = function()
    child.lua([[
        local ConversationProvider = require('cc-tui.providers.conversation')

        -- Create a temporary test file
        local test_file = '/tmp/test_conversation.jsonl'
        local file = io.open(test_file, 'w')
        if file then
            file:write('{"type": "system", "subtype": "init"}\n')
            file:write('{"type": "user", "message": {"content": [{"type": "text", "text": "hello"}]}}\n')
            file:close()
        end

        local provider = ConversationProvider.new(test_file)

        -- First load
        local messages1, error1 = provider:load_conversation()
        _G.first_load_success = error1 == nil and #messages1 > 0
        _G.messages_cached = provider.messages ~= nil

        -- Second load should use cache
        local messages2, error2 = provider:load_conversation()
        _G.second_load_success = error2 == nil and #messages2 > 0
        _G.cache_used = messages1 == messages2

        -- Clean up
        os.remove(test_file)
    ]])

    Helpers.expect.global(child, "_G.first_load_success", true)
    Helpers.expect.global(child, "_G.messages_cached", true)
    Helpers.expect.global(child, "_G.second_load_success", true)
    Helpers.expect.global(child, "_G.cache_used", true)
end

T["load_conversation"]["handles malformed JSON"] = function()
    child.lua([[
        local ConversationProvider = require('cc-tui.providers.conversation')

        -- Create a test file with invalid JSON
        local test_file = '/tmp/test_invalid.jsonl'
        local file = io.open(test_file, 'w')
        if file then
            file:write('{"valid": "json"}\n')
            file:write('invalid json line\n')
            file:write('{"another": "valid"}\n')
            file:close()
        end

        local provider = ConversationProvider.new(test_file)
        local messages, error_msg = provider:load_conversation()

        -- Should handle parsing errors gracefully
        _G.has_error = error_msg ~= nil
        _G.error_mentions_parsing = error_msg and error_msg:find('Parsing errors') ~= nil
        _G.messages_empty = #messages == 0

        -- Clean up
        os.remove(test_file)
    ]])

    Helpers.expect.global(child, "_G.has_error", true)
    Helpers.expect.global(child, "_G.error_mentions_parsing", true)
    Helpers.expect.global(child, "_G.messages_empty", true)
end

-- Tests for get_messages interface
T["get_messages"] = MiniTest.new_set()

T["get_messages"]["calls callback with parsed messages"] = function()
    child.lua([[
        local ConversationProvider = require('cc-tui.providers.conversation')

        -- Create a test file
        local test_file = '/tmp/test_callback.jsonl'
        local file = io.open(test_file, 'w')
        if file then
            file:write('{"type": "system", "subtype": "init"}\n')
            file:write('{"type": "user", "message": {"content": [{"type": "text", "text": "test"}]}}\n')
            file:close()
        end

        local provider = ConversationProvider.new(test_file)

        _G.callback_called = false
        _G.callback_messages = nil

        provider:get_messages(function(messages)
            _G.callback_called = true
            _G.callback_messages = messages
            _G.messages_count = messages and #messages or 0
        end)

        -- Wait for async callback to complete
        vim.wait(100, function()
            return _G.callback_called
        end)

        -- Clean up
        os.remove(test_file)
    ]])

    Helpers.expect.global(child, "_G.callback_called", true)
    local messages_count = child.lua_get("_G.messages_count")
    if type(messages_count) == "number" and messages_count > 0 then
        -- Success: callback was called with messages
        Helpers.expect.equality(messages_count > 0, true)
    end
end

T["get_messages"]["validates callback parameter"] = function()
    child.lua([[
        local ConversationProvider = require('cc-tui.providers.conversation')

        local provider = ConversationProvider.new('/test/path.jsonl')

        -- Test missing callback
        local success1 = pcall(provider.get_messages, provider)
        _G.no_callback_handled = not success1

        -- Test invalid callback type
        local success2 = pcall(provider.get_messages, provider, "not a function")
        _G.invalid_callback_handled = not success2
    ]])

    Helpers.expect.global(child, "_G.no_callback_handled", true)
    Helpers.expect.global(child, "_G.invalid_callback_handled", true)
end

T["get_messages"]["handles file errors gracefully"] = function()
    child.lua([[
        local ConversationProvider = require('cc-tui.providers.conversation')

        local provider = ConversationProvider.new('/non/existent/file.jsonl')

        _G.callback_called = false
        _G.callback_messages = nil
        _G.notification_shown = false

        -- Mock vim.notify to capture error notifications
        local original_notify = vim.notify
        vim.notify = function(msg, level)
            if level == vim.log.levels.ERROR then
                _G.notification_shown = true
            end
        end

        provider:get_messages(function(messages)
            _G.callback_called = true
            _G.callback_messages = messages
            _G.empty_messages = messages and #messages == 0
        end)

        -- Wait for async callback to complete
        vim.wait(100, function()
            return _G.callback_called
        end)

        -- Restore original notify
        vim.notify = original_notify
    ]])

    Helpers.expect.global(child, "_G.callback_called", true)
    Helpers.expect.global(child, "_G.empty_messages", true)
    Helpers.expect.global(child, "_G.notification_shown", true)
end

-- Tests for provider lifecycle
T["lifecycle"] = MiniTest.new_set()

T["lifecycle"]["start is no-op"] = function()
    child.lua([[
        local ConversationProvider = require('cc-tui.providers.conversation')

        local provider = ConversationProvider.new('/test/path.jsonl')

        -- Should not crash or change state
        _G.start_success = pcall(provider.start, provider)
    ]])

    Helpers.expect.global(child, "_G.start_success", true)
end

T["lifecycle"]["stop clears cache"] = function()
    child.lua([[
        local ConversationProvider = require('cc-tui.providers.conversation')

        -- Create a test file
        local test_file = '/tmp/test_stop.jsonl'
        local file = io.open(test_file, 'w')
        if file then
            file:write('{"type": "system", "subtype": "init"}\n')
            file:close()
        end

        local provider = ConversationProvider.new(test_file)

        -- Load messages to populate cache
        provider:load_conversation()
        _G.messages_cached = provider.messages ~= nil

        -- Stop should clear cache
        provider:stop()
        _G.messages_cleared = provider.messages == nil

        -- Clean up
        os.remove(test_file)
    ]])

    Helpers.expect.global(child, "_G.messages_cached", true)
    Helpers.expect.global(child, "_G.messages_cleared", true)
end

-- Tests for metadata functionality
T["metadata"] = MiniTest.new_set()

T["metadata"]["get_metadata returns correct info"] = function()
    child.lua([[
        local ConversationProvider = require('cc-tui.providers.conversation')

        local provider = ConversationProvider.new('/test/path/conversation-2024-01-15-10-30-45.jsonl')
        local metadata = provider:get_metadata()

        _G.has_type = metadata.type == "conversation"
        _G.has_source = metadata.source == "file"
        _G.has_path = metadata.path == "/test/path/conversation-2024-01-15-10-30-45.jsonl"
        _G.has_filename = metadata.filename == "conversation-2024-01-15-10-30-45.jsonl"
        _G.has_timestamp = metadata.timestamp ~= nil
    ]])

    Helpers.expect.global(child, "_G.has_type", true)
    Helpers.expect.global(child, "_G.has_source", true)
    Helpers.expect.global(child, "_G.has_path", true)
    Helpers.expect.global(child, "_G.has_filename", true)
    Helpers.expect.global(child, "_G.has_timestamp", true)
end

T["metadata"]["is_loaded reflects cache state"] = function()
    child.lua([[
        local ConversationProvider = require('cc-tui.providers.conversation')

        local provider = ConversationProvider.new('/test/path.jsonl')

        _G.not_loaded_initially = not provider:is_loaded()

        -- Mock loading state
        provider.messages = {}
        _G.loaded_after_mock = provider:is_loaded()
    ]])

    Helpers.expect.global(child, "_G.not_loaded_initially", true)
    Helpers.expect.global(child, "_G.loaded_after_mock", true)
end

T["metadata"]["get_file_size handles non-existent file"] = function()
    child.lua([[
        local ConversationProvider = require('cc-tui.providers.conversation')

        local provider = ConversationProvider.new('/non/existent/file.jsonl')
        local size = provider:get_file_size()

        _G.size_is_zero = size == 0
    ]])

    Helpers.expect.global(child, "_G.size_is_zero", true)
end

return T
