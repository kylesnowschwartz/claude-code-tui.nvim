local Helpers = dofile("tests/helpers.lua")

local child = Helpers.new_child_neovim()

local T = MiniTest.new_set({
    hooks = {
        pre_case = function()
            child.restart({ "-u", "scripts/minimal_init.lua" })
        end,
        post_once = child.stop,
    },
})

-- Tests related to the `setup` method.
T["setup()"] = MiniTest.new_set()

T["setup()"]["sets exposed methods and default options value"] = function()
    child.lua([[require('cc-tui').setup()]])

    -- global object that holds your plugin information
    Helpers.expect.global_type(child, "_G.CcTui", "table")

    -- public methods
    Helpers.expect.global_type(child, "_G.CcTui.toggle", "function")
    Helpers.expect.global_type(child, "_G.CcTui.disable", "function")
    Helpers.expect.global_type(child, "_G.CcTui.enable", "function")

    -- config
    Helpers.expect.global_type(child, "_G.CcTui.config", "table")

    -- assert the value, and the type
    Helpers.expect.config(child, "debug", false)
    Helpers.expect.config_type(child, "debug", "boolean")
end

T["setup()"]["overrides default values"] = function()
    child.lua([[require('cc-tui').setup({
        -- write all the options with a value different than the default ones
        debug = true,
    })]])

    -- assert the value, and the type
    Helpers.expect.config(child, "debug", true)
    Helpers.expect.config_type(child, "debug", "boolean")
end

-- Test tool-aware result formatting
T["tool-aware formatting"] = MiniTest.new_set()

T["tool-aware formatting"]["formats Read tool results"] = function()
    child.lua([[
        require('cc-tui').setup()
        local TreeBuilder = require('cc-tui.models.tree_builder')

        -- Test Read tool with multi-line content (12 lines to trigger the +lines format)
        local result = TreeBuilder.create_tool_aware_result_node(
            "toolu_read1",
            "{\n  \"name\": \"my-project\",\n  \"version\": \"1.0.0\",\n  \"description\": \"A test project\",\n  \"scripts\": {\n    \"test\": \"jest\",\n    \"build\": \"webpack\",\n    \"dev\": \"webpack-dev-server\"\n  },\n  \"dependencies\": {},\n  \"devDependencies\": {}\n}",
            false,
            "Read"
        )
        _G.read_result_text = result.text

        -- Test short Read result
        local short_result = TreeBuilder.create_tool_aware_result_node(
            "toolu_read2",
            "short content",
            false,
            "Read"
        )
        _G.short_read_result_text = short_result.text
    ]])

    -- Multi-line Read should show line count
    local result_text = child.lua_get("_G.read_result_text")
    Helpers.expect.match(result_text, "%d+ lines %(expand to view%)")

    -- Short Read should show "File content"
    local short_result_text = child.lua_get("_G.short_read_result_text")
    Helpers.expect.equality(short_result_text, "File content")
end

T["tool-aware formatting"]["formats Bash tool results"] = function()
    child.lua([[
        local TreeBuilder = require('cc-tui.models.tree_builder')

        -- Test Bash with multi-line output
        local result = TreeBuilder.create_tool_aware_result_node(
            "toolu_bash1",
            "line 1\nline 2\nline 3\nline 4\nline 5\nline 6",
            false,
            "Bash"
        )
        _G.bash_result_text = result.text

        -- Test short Bash output
        local short_result = TreeBuilder.create_tool_aware_result_node(
            "toolu_bash2",
            "npm install completed",
            false,
            "Bash"
        )
        _G.short_bash_result_text = short_result.text
    ]])

    -- Multi-line Bash should show line count
    local result_text = child.lua_get("_G.bash_result_text")
    Helpers.expect.match(result_text, "Command output %(6 lines%)")

    -- Short Bash should show the content
    local short_result_text = child.lua_get("_G.short_bash_result_text")
    Helpers.expect.equality(short_result_text, "npm install completed")
end

T["tool-aware formatting"]["formats MCP tool results"] = function()
    child.lua([[
        local TreeBuilder = require('cc-tui.models.tree_builder')

        -- Test MCP with multi-line API response
        local result = TreeBuilder.create_tool_aware_result_node(
            "toolu_mcp1",
            "{\n  \"results\": [\n    {\"id\": 1}\n  ]\n}\nMore lines\nAnd more\nYet more\nKeep going\nMore content\nFinal line\nExtra line",
            false,
            "mcp__context7__get-docs"
        )
        _G.mcp_result_text = result.text

        -- Test short MCP result
        local short_result = TreeBuilder.create_tool_aware_result_node(
            "toolu_mcp2",
            "{\"status\": \"ok\"}",
            false,
            "mcp__playwright__click"
        )
        _G.short_mcp_result_text = short_result.text
    ]])

    -- Multi-line MCP should show line count
    local result_text = child.lua_get("_G.mcp_result_text")
    Helpers.expect.match(result_text, "API response %(12 lines%)")

    -- Short MCP should show "API result"
    local short_result_text = child.lua_get("_G.short_mcp_result_text")
    Helpers.expect.equality(short_result_text, "API result")
end

T["tool-aware formatting"]["formats error results"] = function()
    child.lua([[
        local TreeBuilder = require('cc-tui.models.tree_builder')

        local error_result = TreeBuilder.create_tool_aware_result_node(
            "toolu_error1",
            "Error: File not found",
            true,
            "Read"
        )
        _G.error_result_text = error_result.text
    ]])

    local result_text = child.lua_get("_G.error_result_text")
    Helpers.expect.equality(result_text, "❌ Error")
end

return T
