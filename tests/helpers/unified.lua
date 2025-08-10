---@brief [[
--- Unified Test Helper Framework
--- Consolidates all test helper patterns into single, consistent interface
--- Combines MiniTest helpers, TDD framework, and real data loading
---@brief ]]

local M = {}

-- Re-export specialized helpers that work independently
M.real_data = require("tests.helpers.real_data_loader")
M.tdd = require("tests.helpers.tdd_framework")

-- Import MiniTest helpers directly without circular dependency
M.new_child_neovim = function()
    return MiniTest.new_child_neovim()
end

-- Create our own expect interface that works with MiniTest
M.expect = MiniTest.expect

---Create standardized test setup with common configuration
---@param config? table Optional configuration
---@return table child Child neovim process
---@return table T MiniTest test set
function M.create_test_setup(config)
    config = config or {}

    local child = M.new_child_neovim()

    local T = MiniTest.new_set({
        hooks = {
            pre_case = function()
                child.restart({ "-u", "scripts/minimal_init.lua" })

                -- Initialize common global state
                child.lua([[
                    _G.CcTui = _G.CcTui or {}
                    _G.CcTui.config = _G.CcTui.config or {}

                    -- Set up package path for tests
                    package.path = "./lua/?.lua;" .. package.path
                ]])

                -- Run custom pre_case if provided
                if config.pre_case then
                    config.pre_case(child)
                end
            end,
            post_once = function()
                -- Run custom post_once if provided
                if config.post_once then
                    config.post_once(child)
                end
                child.stop()
            end,
        },
    })

    return child, T
end

---Create standardized real data test setup
---@param category? string Real data category ("tiny", "small", "medium", "large", "huge")
---@return table child Child neovim process
---@return table config Test configuration with real data validation
function M.create_real_data_test_setup(category)
    local child, config = M.create_test_setup()

    -- Override pre_case to include real data validation
    local original_pre_case = config.hooks.pre_case
    config.hooks.pre_case = function()
        original_pre_case()

        -- Validate real data is available
        local valid, err = M.real_data.validate_real_data_available()
        if not valid then
            MiniTest.skip("Real conversation data not available: " .. (err or "unknown"))
        end

        -- Set up category-specific data if requested
        if category then
            local success, data_info = pcall(M.real_data.get_conversation_metadata)
            if not success then
                MiniTest.skip("Failed to load conversation metadata: " .. tostring(data_info))
            end

            -- Verify category exists
            local has_category = false
            for _, meta in ipairs(data_info) do
                if meta.category == category then
                    has_category = true
                    break
                end
            end

            if not has_category then
                MiniTest.skip("No conversations available for category: " .. category)
            end
        end
    end

    return child, config
end

---Create TDD test cycle with unified helpers
---@param description string Description of what's being tested
---@param category? string Real data category to use
---@return table cycle TDD cycle helper
function M.create_tdd_cycle(description, category)
    return M.tdd.create_cycle({
        description = description,
        category = category,
        setup = function(state)
            -- Common setup for TDD cycles
            if state.provider then
                -- Initialize provider callbacks for consistent testing
                state.collected_data = {}
                state.provider:register_callback("on_data", function(data)
                    table.insert(state.collected_data, data)
                end)
            end
        end,
        teardown = function(state)
            -- Common cleanup for TDD cycles
            if state.provider then
                pcall(state.provider.stop, state.provider)
            end
        end,
    })
end

---Standardized before_each helper that works with both MiniTest and TDD patterns
---@param setup_fn function Setup function to run before each test
---@return function before_each Pre-case hook function
function M.before_each(setup_fn)
    return function()
        M.tdd.child.restart({ "-u", "scripts/minimal_init.lua" })
        if setup_fn then
            setup_fn()
        end
    end
end

---Create consistent describe/it structure that works with MiniTest
---@param name string Test group name
---@param test_fn function Test function
---@return table test_group MiniTest-compatible test group
function M.describe(name, test_fn)
    local T = MiniTest.new_set()
    T[name] = MiniTest.new_set()

    -- Execute the test function in the context of the test set
    local old_it = _G.it
    local old_expect = _G.expect

    -- Provide it() and expect() in the test context
    _G.it = function(test_name, test_impl)
        T[name][test_name] = test_impl
    end
    _G.expect = M.expect

    -- Execute test definition
    test_fn()

    -- Restore globals
    _G.it = old_it
    _G.expect = old_expect

    return T
end

---Standardized assertions that work across all test patterns
M.assert = {
    equals = function(actual, expected, message)
        if actual ~= expected then
            error(message or string.format("Expected %s to equal %s", vim.inspect(actual), vim.inspect(expected)))
        end
    end,

    truthy = function(actual, message)
        if not actual then
            error(message or string.format("Expected %s to be truthy", vim.inspect(actual)))
        end
    end,

    falsy = function(actual, message)
        if actual then
            error(message or string.format("Expected %s to be falsy", vim.inspect(actual)))
        end
    end,

    nil_value = function(actual, message)
        if actual ~= nil then
            error(message or string.format("Expected %s to be nil", vim.inspect(actual)))
        end
    end,

    not_nil = function(actual, message)
        if actual == nil then
            error(message or "Expected value to not be nil")
        end
    end,

    contains = function(table_val, expected, message)
        if type(table_val) ~= "table" then
            error("contains assertion can only be used with tables")
        end

        for _, value in pairs(table_val) do
            if value == expected then
                return
            end
        end

        error(message or string.format("Expected table to contain %s", vim.inspect(expected)))
    end,

    matches = function(str, pattern, message)
        if type(str) ~= "string" then
            error("matches assertion can only be used with strings")
        end

        if not str:match(pattern) then
            error(message or string.format("Expected '%s' to match pattern '%s'", str, pattern))
        end
    end,

    throws = function(fn, error_pattern, message)
        if type(fn) ~= "function" then
            error("throws assertion can only be used with functions")
        end

        local success, result = pcall(fn)
        if success then
            error(message or "Expected function to throw an error, but it succeeded")
        end

        if error_pattern and not result:match(error_pattern) then
            error(message or string.format("Expected error to match pattern '%s', got: %s", error_pattern, result))
        end
    end,
}

---Performance testing helper with consistent interface
---@param description string Description of performance test
---@param fn function Function to measure
---@param config? table Performance test configuration
---@return table results Performance measurement results
function M.measure_performance(description, fn, config)
    config = config or {}
    local iterations = config.iterations or 1
    local threshold_ms = config.threshold_ms

    local results = M.tdd.measure_performance(fn, iterations)
    results.description = description

    -- Check threshold if provided
    if threshold_ms and results.average_time > threshold_ms then
        error(
            string.format(
                "Performance test '%s' exceeded threshold: %.2fms > %.2fms",
                description,
                results.average_time,
                threshold_ms
            )
        )
    end

    return results
end

---Skip test with consistent message format
---@param reason string Reason for skipping test
function M.skip(reason)
    MiniTest.skip(reason)
end

---Mark test as pending/todo with consistent format
---@param reason string Reason test is pending
function M.pending(reason)
    M.skip("TODO: " .. reason)
end

return M
