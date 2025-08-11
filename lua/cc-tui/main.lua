---@brief [[
--- Main module for CC-TUI (TABBED INTERFACE)
--- Coordinates tabbed interface following MCPHub UX patterns
---
--- ARCHITECTURE CHANGE: Unified tabbed interface replacing separate commands
--- - TabbedManager handles unified UI with C/B/L/? tabs
--- - Current tab shows conversation tree (replaces :CcTui)
--- - Browse tab shows conversation browser (unified interface)
--- - Logs tab shows debug/activity logs
--- - Help tab shows keybindings and usage instructions
---
--- Benefits: Unified UX, consistent navigation, better discoverability
---@brief ]]

local DataLoader = require("cc-tui.core.data_loader")
local Parser = require("cc-tui.parser.stream")
local StreamManager = require("cc-tui.core.stream_manager")
local TabbedManager = require("cc-tui.ui.tabbed_manager")
local TreeBuilder = require("cc-tui.models.tree_builder")
local log = require("cc-tui.utils.log")

---@class CcTui.Main
local M = {}

-- Default tab to open when no tab is specified
-- Set to "browse" for browse-first UI flow
local DEFAULT_TAB = "browse"

---@class CcTui.MainState
---@field messages CcTui.Message[] Parsed messages
---@field tree_data CcTui.BaseNode? Tree data structure
---@field tabbed_manager CcTui.UI.TabbedManager? Active tabbed manager instance

---Internal state for tabbed interface
---@type CcTui.MainState
local main_state = {
    messages = {},
    tree_data = nil,
    tabbed_manager = nil,
}

---Toggle the plugin by calling the `enable`/`disable` methods respectively.
---@param scope string Internal identifier for logging purposes
---@param default_tab? string Default tab to open (default: "browse")
---@private
function M.toggle(scope, default_tab)
    vim.validate({
        scope = { scope, "string" },
        default_tab = { default_tab, "string", true },
    })

    if main_state.tabbed_manager and main_state.tabbed_manager:is_active() then
        M.disable(scope)
    else
        M.enable(scope, default_tab)
    end
end

---Initialize the plugin, creates tabbed interface
---@param scope string Internal identifier for logging purposes
---@param default_tab? string Default tab to open (default: "browse")
---@private
function M.enable(scope, default_tab)
    vim.validate({
        scope = { scope, "string" },
        default_tab = { default_tab, "string", true },
    })

    default_tab = default_tab or DEFAULT_TAB

    -- Create tabbed manager
    local manager, err = TabbedManager.new({
        width = "80%",
        height = "80%",
        default_tab = default_tab,
        on_close = function()
            main_state.tabbed_manager = nil
            log.debug("main", "Tabbed manager closed")
        end,
    })

    if not manager then
        log.debug("main", "Failed to create tabbed manager: " .. (err or "unknown error"))
        vim.notify("CC-TUI: Failed to open interface", vim.log.levels.ERROR)
        return false
    end

    main_state.tabbed_manager = manager

    -- Show the tabbed interface
    manager:show()

    log.debug("main", string.format("CC-TUI enabled with tabbed interface, default tab: %s", default_tab))
    return true
end

---Disable the plugin, closes tabbed interface and resets state
---@param scope string Internal identifier for logging purposes
---@private
function M.disable(scope)
    vim.validate({
        scope = { scope, "string" },
    })

    -- Close tabbed manager
    if main_state.tabbed_manager then
        main_state.tabbed_manager:close()
        main_state.tabbed_manager = nil
    end

    -- Stop any active streaming
    StreamManager.stop_streaming()

    -- Clear local state
    main_state.messages = {}
    main_state.tree_data = nil

    log.debug("main", "CC-TUI disabled successfully")
end

---Refresh current display (refreshes active tab content)
---@return nil
function M.refresh()
    if not main_state.tabbed_manager or not main_state.tabbed_manager:is_active() then
        return
    end

    -- Refresh the current tab
    main_state.tabbed_manager:refresh_current_tab()

    log.debug("main", "Refreshed tabbed interface")
end

---Process a new JSONL line (for streaming support)
---@param line string JSONL line to process
---@return nil
function M.process_line(line)
    vim.validate({
        line = { line, "string" },
    })

    if not main_state.tabbed_manager or not main_state.tabbed_manager:is_active() then
        log.debug("main", "Cannot process line: tabbed interface not active")
        return
    end

    -- Parse the line
    local msg, err = Parser.parse_line(line)
    if not msg then
        log.debug("main", "Failed to parse line: " .. (err or "unknown error"))
        return
    end

    -- Add to messages
    table.insert(main_state.messages, msg)

    -- Rebuild tree and update UI
    local session_info = Parser.get_session_info(main_state.messages)
    local root = TreeBuilder.build_tree(main_state.messages, session_info)
    main_state.tree_data = root

    -- Update tabbed interface with new tree
    if main_state.tabbed_manager then
        main_state.tabbed_manager:refresh_current_tab()
    end
end

---Start streaming from Claude CLI
---@param config? table StreamProvider configuration {command, args, timeout}
---@return nil
function M.start_streaming(config)
    vim.validate({
        config = { config, "table", true },
    })

    local callbacks = {
        on_start = function()
            log.debug("main", "Streaming started")
        end,
        on_data = function(line)
            M.process_line(line)
        end,
        on_error = function(err)
            log.debug("main", "Streaming error: " .. err)
        end,
        on_complete = function()
            log.debug("main", "Streaming completed")
        end,
    }

    StreamManager.start_streaming(config, callbacks)
end

---Stop active streaming
---@return nil
function M.stop_streaming()
    StreamManager.stop_streaming()
end

---Load conversation from JSONL file
---@param conversation_path string Path to conversation JSONL file
---@return nil
function M.load_conversation(conversation_path)
    DataLoader.load_conversation(conversation_path, function(messages, root, _, path)
        -- Store messages and tree data
        main_state.messages = messages
        main_state.tree_data = root

        -- Update tabbed interface or enable plugin with new data
        if main_state.tabbed_manager and main_state.tabbed_manager:is_active() then
            -- Switch to current tab to show the loaded conversation
            main_state.tabbed_manager:switch_to_tab("current")
            main_state.tabbed_manager:refresh_current_tab()
        else
            -- Enable tabbed interface with current tab to show the loaded conversation
            M.enable("conversation_load", "current")
        end

        log.debug("main", string.format("Loaded conversation from %s", path or "unknown"))
    end)
end

---Get current state for debugging (backward compatibility with tabbed interface)
---@return table state State structure for debugging and tests
function M.get_state()
    local stream_state = StreamManager.get_state()

    -- Return state structure adapted for tabbed interface
    return {
        tabbed_manager = main_state.tabbed_manager,
        tree_data = main_state.tree_data,
        messages = main_state.messages,
        streaming_provider = stream_state.streaming_provider,
        is_active = main_state.tabbed_manager and main_state.tabbed_manager:is_active() or false,
        current_tab = main_state.tabbed_manager and main_state.tabbed_manager.current_tab or nil,
    }
end

return M
