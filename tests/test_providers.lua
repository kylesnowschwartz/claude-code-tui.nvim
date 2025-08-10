local Helpers = dofile("tests/helpers.lua")

-- See https://github.com/echasnovski/mini.nvim/blob/main/lua/mini/test.lua for more documentation

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

-- Tests for DataProvider interface
T["DataProvider"] = MiniTest.new_set()

T["DataProvider"]["base interface exists"] = function()
    child.lua([[
        local DataProvider = require('cc-tui.providers.base')
        _G.data_provider_type = type(DataProvider)
    ]])

    local provider_type = child.lua_get("_G.data_provider_type")
    Helpers.expect.equality(provider_type, "table")
end

T["DataProvider"]["has required methods"] = function()
    child.lua([[
        local DataProvider = require('cc-tui.providers.base')
        _G.has_start = type(DataProvider.start) == "function"
        _G.has_stop = type(DataProvider.stop) == "function"
        _G.has_register_callback = type(DataProvider.register_callback) == "function"
    ]])

    Helpers.expect.global(child, "_G.has_start", true)
    Helpers.expect.global(child, "_G.has_stop", true)
    Helpers.expect.global(child, "_G.has_register_callback", true)
end

T["DataProvider"]["register_callback validates input"] = function()
    child.lua([[
        local DataProvider = require('cc-tui.providers.base')
        local provider = DataProvider:new()

        -- Test invalid event name
        local success1 = pcall(provider.register_callback, provider, "invalid_event", function() end)
        _G.invalid_event_handled = not success1

        -- Test invalid callback type
        local success2 = pcall(provider.register_callback, provider, "on_data", "not_a_function")
        _G.invalid_callback_handled = not success2

        -- Test valid registration
        local success3 = pcall(provider.register_callback, provider, "on_data", function() end)
        _G.valid_registration = success3
    ]])

    Helpers.expect.global(child, "_G.invalid_event_handled", true)
    Helpers.expect.global(child, "_G.invalid_callback_handled", true)
    Helpers.expect.global(child, "_G.valid_registration", true)
end

T["DataProvider"]["callbacks can be registered and called"] = function()
    child.lua([[
        local DataProvider = require('cc-tui.providers.base')
        local provider = DataProvider:new()

        _G.callback_called = false
        _G.callback_data = nil

        provider:register_callback("on_data", function(data)
            _G.callback_called = true
            _G.callback_data = data
        end)

        -- Simulate triggering callback (this would be done internally by concrete providers)
        provider.callbacks.on_data("test data")
    ]])

    Helpers.expect.global(child, "_G.callback_called", true)
    Helpers.expect.global(child, "_G.callback_data", "test data")
end

T["DataProvider"]["start method is abstract"] = function()
    child.lua([[
        local DataProvider = require('cc-tui.providers.base')
        local provider = DataProvider:new()

        -- Base provider start should error (abstract method)
        local success = pcall(provider.start, provider)
        _G.start_is_abstract = not success
    ]])

    Helpers.expect.global(child, "_G.start_is_abstract", true)
end

T["DataProvider"]["stop method is abstract"] = function()
    child.lua([[
        local DataProvider = require('cc-tui.providers.base')
        local provider = DataProvider:new()

        -- Base provider stop should error (abstract method)
        local success = pcall(provider.stop, provider)
        _G.stop_is_abstract = not success
    ]])

    Helpers.expect.global(child, "_G.stop_is_abstract", true)
end

-- Tests for StaticProvider
T["StaticProvider"] = MiniTest.new_set()

T["StaticProvider"]["inherits from DataProvider"] = function()
    child.lua([[
        local StaticProvider = require('cc-tui.providers.static')
        local DataProvider = require('cc-tui.providers.base')

        local provider = StaticProvider:new()
        _G.has_start = type(provider.start) == "function"
        _G.has_stop = type(provider.stop) == "function"
        _G.has_register_callback = type(provider.register_callback) == "function"
    ]])

    Helpers.expect.global(child, "_G.has_start", true)
    Helpers.expect.global(child, "_G.has_stop", true)
    Helpers.expect.global(child, "_G.has_register_callback", true)
end

T["StaticProvider"]["can be created with default config"] = function()
    child.lua([[
        local StaticProvider = require('cc-tui.providers.static')
        local provider = StaticProvider:new()
        _G.provider_created = provider ~= nil
        _G.has_limit = type(provider.limit) == "number"
    ]])

    Helpers.expect.global(child, "_G.provider_created", true)
    Helpers.expect.global(child, "_G.has_limit", true)
end

T["StaticProvider"]["can be created with custom config"] = function()
    child.lua([[
        local StaticProvider = require('cc-tui.providers.static')
        local provider = StaticProvider:new({ limit = 250 })
        _G.custom_limit = provider.limit
    ]])

    Helpers.expect.global(child, "_G.custom_limit", 250)
end

T["StaticProvider"]["start triggers data callbacks"] = function()
    child.lua([[
        local StaticProvider = require('cc-tui.providers.static')
        local provider = StaticProvider:new({ limit = 3 }) -- Use small limit for test

        _G.callback_count = 0
        _G.received_lines = {}
        _G.start_called = false
        _G.complete_called = false

        provider:register_callback("on_start", function()
            _G.start_called = true
        end)

        provider:register_callback("on_data", function(line)
            _G.callback_count = _G.callback_count + 1
            table.insert(_G.received_lines, line)
        end)

        provider:register_callback("on_complete", function()
            _G.complete_called = true
        end)

        -- Mock the test data loading to return predictable data
        _G.mock_lines = {'{"type":"test","id":"1"}', '{"type":"test","id":"2"}', '{"type":"test","id":"3"}'}

        -- Override TestData.load_sample_lines for predictable testing
        local original_load = require('cc-tui.parser.test_data').load_sample_lines
        require('cc-tui.parser.test_data').load_sample_lines = function(limit)
            return _G.mock_lines
        end

        provider:start()

        -- Restore original function
        require('cc-tui.parser.test_data').load_sample_lines = original_load
    ]])

    Helpers.expect.global(child, "_G.start_called", true)
    Helpers.expect.global(child, "_G.complete_called", true)
    Helpers.expect.global(child, "_G.callback_count", 3)
end

T["StaticProvider"]["stop method exists and works"] = function()
    child.lua([[
        local StaticProvider = require('cc-tui.providers.static')
        local provider = StaticProvider:new()

        -- Stop should work without error even if not started
        local success = pcall(provider.stop, provider)
        _G.stop_works = success
    ]])

    Helpers.expect.global(child, "_G.stop_works", true)
end

T["StaticProvider"]["handles empty data gracefully"] = function()
    child.lua([[
        local StaticProvider = require('cc-tui.providers.static')
        local provider = StaticProvider:new()

        _G.error_called = false
        _G.error_message = nil

        provider:register_callback("on_error", function(err)
            _G.error_called = true
            _G.error_message = err
        end)

        -- Mock empty data
        local original_load = require('cc-tui.parser.test_data').load_sample_lines
        require('cc-tui.parser.test_data').load_sample_lines = function(limit)
            return {} -- Empty data
        end

        provider:start()

        -- Restore original function
        require('cc-tui.parser.test_data').load_sample_lines = original_load
    ]])

    Helpers.expect.global(child, "_G.error_called", true)
end

-- Tests for StreamProvider (consolidated from test_stream_provider.lua)
T["StreamProvider"] = MiniTest.new_set()

T["StreamProvider"]["inherits from DataProvider"] = function()
    child.lua([[
        local StreamProvider = require('cc-tui.providers.stream')
        local DataProvider = require('cc-tui.providers.base')

        _G.stream_is_table = type(StreamProvider) == "table"
        _G.has_base_methods = (
            type(StreamProvider.register_callback) == "function" and
            type(StreamProvider.start) == "function" and
            type(StreamProvider.stop) == "function"
        )
    ]])

    Helpers.expect.global(child, "_G.stream_is_table", true)
    Helpers.expect.global(child, "_G.has_base_methods", true)
end

T["StreamProvider"]["can be created with command config"] = function()
    child.lua([[
        local StreamProvider = require('cc-tui.providers.stream')

        local provider = StreamProvider:new({
            command = "echo",
            args = {"hello", "world"}
        })

        _G.provider_created = provider ~= nil
        _G.has_config = provider.config ~= nil
        _G.correct_command = provider.config.command == "echo"
        _G.correct_args = vim.deep_equal(provider.config.args, {"hello", "world"})
    ]])

    Helpers.expect.global(child, "_G.provider_created", true)
    Helpers.expect.global(child, "_G.has_config", true)
    Helpers.expect.global(child, "_G.correct_command", true)
    Helpers.expect.global(child, "_G.correct_args", true)
end

T["StreamProvider"]["validates required config on creation"] = function()
    child.lua([[
        local StreamProvider = require('cc-tui.providers.stream')

        -- Test missing command
        local success1 = pcall(StreamProvider.new, StreamProvider, {})
        _G.missing_command_handled = not success1

        -- Test invalid command type
        local success2 = pcall(StreamProvider.new, StreamProvider, { command = 123 })
        _G.invalid_command_handled = not success2

        -- Test valid command
        local success3 = pcall(StreamProvider.new, StreamProvider, { command = "echo" })
        _G.valid_command_works = success3
    ]])

    Helpers.expect.global(child, "_G.missing_command_handled", true)
    Helpers.expect.global(child, "_G.invalid_command_handled", true)
    Helpers.expect.global(child, "_G.valid_command_works", true)
end

T["StreamProvider"]["start spawns subprocess and triggers callbacks"] = function()
    child.lua([[
        local StreamProvider = require('cc-tui.providers.stream')

        local provider = StreamProvider:new({
            command = "echo",
            args = {"test", "output"}
        })

        _G.data_received = {}
        _G.complete_called = false

        provider:register_callback("on_data", function(data)
            table.insert(_G.data_received, data)
        end)

        provider:register_callback("on_complete", function()
            _G.complete_called = true
        end)

        provider:start()

        -- Wait for command to complete
        vim.wait(1000, function()
            return _G.complete_called
        end)
    ]])

    Helpers.expect.global(child, "_G.complete_called", true)
    local data_received = child.lua_get("_G.data_received")
    Helpers.expect.truthy(#data_received > 0, "Should receive data from echo command")
end

-- Tests for ConversationProvider (consolidated from test_conversation_provider.lua)
T["ConversationProvider"] = MiniTest.new_set()

T["ConversationProvider"]["creates provider with file path"] = function()
    child.lua([[
        -- Initialize global state for tests
        _G.CcTui = _G.CcTui or {}
        _G.CcTui.config = _G.CcTui.config or {}

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

T["ConversationProvider"]["validates file path parameter"] = function()
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

T["ConversationProvider"]["handles non-existent file"] = function()
    child.lua([[
        -- Initialize global state for tests
        _G.CcTui = _G.CcTui or {}
        _G.CcTui.config = _G.CcTui.config or {}

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

T["ConversationProvider"]["caches parsed messages"] = function()
    child.lua([[
        -- Initialize global state for tests
        _G.CcTui = _G.CcTui or {}
        _G.CcTui.config = _G.CcTui.config or {}

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

T["ConversationProvider"]["get_metadata returns correct info"] = function()
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

return T
