---@brief [[
--- TDD Framework Helper for Red/Green/Refactor Cycles
--- Supports AI agent-driven development with clear test patterns
---@brief ]]

local M = {}

-- Export mini.test child for testing
M.child = require("mini.test").new_child_neovim()

-- Basic describe/it structure for compatibility with mini.test
function M.describe(name, test_fn)
    return { name = name, test_fn = test_fn }
end

function M.it(name, test_fn)
    return { name = name, test_fn = test_fn }
end

---@class TddCycleConfig
---@field description string Description of what's being tested
---@field category? string Real data category to use ("tiny", "small", "medium", "large", "huge")
---@field setup? function Pre-test setup function
---@field teardown? function Post-test cleanup function
---@field timeout? number Test timeout in milliseconds

---Create a TDD red/green/refactor cycle for AI agent development
---@param config TddCycleConfig Configuration for the test cycle
---@return table cycle TDD cycle helper with red(), green(), refactor() methods
function M.create_cycle(config)
    vim.validate({
        config = { config, "table" },
        ["config.description"] = { config.description, "string" },
        ["config.category"] = { config.category, "string", true },
        ["config.setup"] = { config.setup, "function", true },
        ["config.teardown"] = { config.teardown, "function", true },
        ["config.timeout"] = { config.timeout, "number", true },
    })

    local cycle = {
        config = config,
        state = {
            phase = "red", -- "red", "green", "refactor"
            test_data = nil,
            provider = nil,
            results = {},
        },
    }

    ---Execute RED phase - Write failing test that defines expected behavior
    ---@param test_fn function Test function that should initially fail
    ---@return boolean success Whether red phase executed correctly (should fail)
    function cycle.red(test_fn)
        vim.validate({
            test_fn = { test_fn, "function" },
        })

        cycle.state.phase = "red"

        -- Setup test data if category specified
        if config.category then
            local RealDataLoader = require("tests.helpers.real_data_loader")
            local provider_factory = RealDataLoader.create_categorized_provider(config.category)
            cycle.state.provider, cycle.state.test_data = provider_factory()
        end

        -- Run setup if provided
        if config.setup then
            config.setup(cycle.state)
        end

        -- Execute the test (should fail in RED phase)
        local success, result = pcall(test_fn, cycle.state)
        cycle.state.results.red = {
            success = success,
            result = result,
            expected_to_fail = true,
        }

        -- RED phase success means test failed as expected
        return not success
    end

    ---Execute GREEN phase - Implement minimal code to make test pass
    ---@param implementation_fn function Implementation function
    ---@param test_fn function Same test function from RED phase
    ---@return boolean success Whether green phase executed correctly (should pass)
    function cycle.green(implementation_fn, test_fn)
        vim.validate({
            implementation_fn = { implementation_fn, "function" },
            test_fn = { test_fn, "function" },
        })

        cycle.state.phase = "green"

        -- Execute implementation
        local impl_success, impl_result = pcall(implementation_fn, cycle.state)
        if not impl_success then
            cycle.state.results.green = {
                success = false,
                result = impl_result,
                phase = "implementation_failed",
            }
            return false
        end

        -- Run the same test (should now pass)
        local test_success, test_result = pcall(test_fn, cycle.state)
        cycle.state.results.green = {
            success = test_success,
            result = test_result,
            implementation_result = impl_result,
            expected_to_pass = true,
        }

        -- GREEN phase success means test passed
        return test_success
    end

    ---Execute REFACTOR phase - Improve implementation while maintaining green
    ---@param refactor_fn function Refactoring function
    ---@param test_fn function Same test function (should still pass)
    ---@return boolean success Whether refactor phase executed correctly
    function cycle.refactor(refactor_fn, test_fn)
        vim.validate({
            refactor_fn = { refactor_fn, "function" },
            test_fn = { test_fn, "function" },
        })

        cycle.state.phase = "refactor"

        -- Execute refactoring
        local refactor_success, refactor_result = pcall(refactor_fn, cycle.state)
        if not refactor_success then
            cycle.state.results.refactor = {
                success = false,
                result = refactor_result,
                phase = "refactor_failed",
            }
            return false
        end

        -- Verify test still passes after refactoring
        local test_success, test_result = pcall(test_fn, cycle.state)
        cycle.state.results.refactor = {
            success = test_success,
            result = test_result,
            refactor_result = refactor_result,
            expected_to_pass = true,
        }

        -- Run teardown if provided
        if config.teardown then
            pcall(config.teardown, cycle.state)
        end

        -- REFACTOR phase success means test still passes after improvement
        return test_success
    end

    ---Get cycle summary for debugging and reporting
    ---@return table summary Complete cycle execution summary
    function cycle.get_summary()
        return {
            description = config.description,
            category = config.category,
            phase = cycle.state.phase,
            results = cycle.state.results,
            test_data_info = cycle.state.test_data and {
                uuid = cycle.state.test_data.uuid,
                line_count = cycle.state.test_data.line_count,
                category = cycle.state.test_data.category,
            } or nil,
        }
    end

    return cycle
end

---Create expectation helper for clear test assertions
---@param actual any Actual value to test
---@return table expectation Expectation helper with assertion methods
function M.expect(actual)
    local expectation = {
        actual = actual,
    }

    ---Expect actual value to equal expected value
    ---@param expected any Expected value
    ---@return boolean success Whether expectation passed
    function expectation.to_equal(expected)
        if actual == expected then
            return true
        else
            error(string.format("Expected %s to equal %s", vim.inspect(actual), vim.inspect(expected)))
        end
    end

    ---Expect actual value to be truthy
    ---@return boolean success Whether expectation passed
    function expectation.to_be_truthy()
        if actual then
            return true
        else
            error(string.format("Expected %s to be truthy", vim.inspect(actual)))
        end
    end

    ---Expect actual value to be falsy
    ---@return boolean success Whether expectation passed
    function expectation.to_be_falsy()
        if not actual then
            return true
        else
            error(string.format("Expected %s to be falsy", vim.inspect(actual)))
        end
    end

    ---Expect actual to be nil
    ---@return boolean success Whether expectation passed
    function expectation.to_be_nil()
        if actual == nil then
            return true
        else
            error(string.format("Expected %s to be nil", vim.inspect(actual)))
        end
    end

    ---Expect actual to not be nil
    ---@return boolean success Whether expectation passed
    function expectation.to_not_be_nil()
        if actual ~= nil then
            return true
        else
            error("Expected value to not be nil")
        end
    end

    ---Expect actual table to contain expected value
    ---@param expected any Value to find in table
    ---@return boolean success Whether expectation passed
    function expectation.to_contain(expected)
        if type(actual) ~= "table" then
            error("to_contain can only be used with tables")
        end

        for _, value in pairs(actual) do
            if value == expected then
                return true
            end
        end

        error(string.format("Expected table %s to contain %s", vim.inspect(actual), vim.inspect(expected)))
    end

    ---Expect actual string to match pattern
    ---@param pattern string Lua pattern to match
    ---@return boolean success Whether expectation passed
    function expectation.to_match(pattern)
        if type(actual) ~= "string" then
            error("to_match can only be used with strings")
        end

        if actual:match(pattern) then
            return true
        else
            error(string.format("Expected '%s' to match pattern '%s'", actual, pattern))
        end
    end

    ---Expect function call to throw error
    ---@param error_pattern? string Optional error message pattern to match
    ---@return boolean success Whether expectation passed
    function expectation.to_throw(error_pattern)
        if type(actual) ~= "function" then
            error("to_throw can only be used with functions")
        end

        local success, result = pcall(actual)
        if success then
            error("Expected function to throw an error, but it succeeded")
        end

        if error_pattern and not result:match(error_pattern) then
            error(string.format("Expected error to match pattern '%s', got: %s", error_pattern, result))
        end

        return true
    end

    return expectation
end

---Performance measurement helper for stress testing
---@param fn function Function to measure
---@param iterations? number Number of iterations (default: 1)
---@return table performance Performance measurements
function M.measure_performance(fn, iterations)
    vim.validate({
        fn = { fn, "function" },
        iterations = { iterations, "number", true },
    })

    iterations = iterations or 1
    local results = {
        iterations = iterations,
        times = {},
        memory_before = 0,
        memory_after = 0,
        total_time = 0,
        average_time = 0,
        min_time = math.huge,
        max_time = 0,
    }

    -- Measure initial memory
    collectgarbage("collect")
    results.memory_before = collectgarbage("count") * 1024 -- Convert KB to bytes

    local start_total = vim.uv.hrtime()

    for i = 1, iterations do
        local start_iter = vim.uv.hrtime()
        fn()
        local end_iter = vim.uv.hrtime()

        local iter_time = (end_iter - start_iter) / 1e6 -- Convert nanoseconds to milliseconds
        table.insert(results.times, iter_time)

        results.min_time = math.min(results.min_time, iter_time)
        results.max_time = math.max(results.max_time, iter_time)
    end

    local end_total = vim.uv.hrtime()
    results.total_time = (end_total - start_total) / 1e6
    results.average_time = results.total_time / iterations

    -- Measure final memory
    collectgarbage("collect")
    results.memory_after = collectgarbage("count") * 1024 -- Convert KB to bytes
    results.memory_delta = results.memory_after - results.memory_before

    return results
end

return M
