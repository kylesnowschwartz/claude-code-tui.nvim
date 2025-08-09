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

return T
