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

return T
