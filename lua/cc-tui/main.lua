---@brief [[
--- Main module for CC-TUI
--- Manages the plugin's core functionality and UI state
---@brief ]]

local Parser = require("cc-tui.parser.stream")
local Popup = require("nui.popup")
local StaticProvider = require("cc-tui.providers.static")
local StreamProvider = require("cc-tui.providers.stream")
local Tree = require("cc-tui.ui.tree")
local TreeBuilder = require("cc-tui.models.tree_builder")
local log = require("cc-tui.util.log")
local state = require("cc-tui.state")

---@class CcTui.Main
local M = {}

---@class CcTui.MainState
---@field popup NuiPopup? Main popup window
---@field tree NuiTree? Active tree component
---@field tree_data CcTui.BaseNode? Tree data structure
---@field messages CcTui.Message[] Parsed messages
---@field streaming_provider CcTui.StreamProvider? Active streaming provider

---Internal state
---@type CcTui.MainState
local main_state = {
    popup = nil,
    tree = nil,
    tree_data = nil,
    messages = {},
    streaming_provider = nil,
}

---Toggle the plugin by calling the `enable`/`disable` methods respectively.
---@param scope string Internal identifier for logging purposes
---@private
function M.toggle(scope)
    vim.validate({
        scope = { scope, "string" },
    })

    if state:get_enabled() then
        log.debug(scope, "cc-tui is now disabled!")
        return M.disable(scope)
    end

    log.debug(scope, "cc-tui is now enabled!")
    M.enable(scope)
end

---Load and parse test data using StaticProvider
---@return CcTui.BaseNode? root Root node or nil
---@return string? error Error message if failed
local function load_test_data()
    local provider = StaticProvider:new({ limit = 500 })
    local lines = {}
    local error_message = nil

    -- Set up callbacks to collect data
    provider:register_callback("on_data", function(line)
        table.insert(lines, line)
    end)

    provider:register_callback("on_error", function(err)
        error_message = err
    end)

    -- Start provider (synchronous for StaticProvider)
    provider:start()

    -- Check for errors
    if error_message then
        return nil, error_message
    end

    if #lines == 0 then
        return nil, "Failed to load test data"
    end

    -- Parse lines
    local messages, errors = Parser.parse_lines(lines)
    if #errors > 0 then
        log.debug("main", string.format("Parse errors: %s", table.concat(errors, ", ")))
    end

    -- Store messages
    main_state.messages = messages

    -- Get session info
    local session_info = Parser.get_session_info(messages)

    -- Build tree
    local root = TreeBuilder.build_tree(messages, session_info)

    return root, nil
end

---Initialize the plugin, sets event listeners and internal state
---@param scope string Internal identifier for logging purposes
---@private
function M.enable(scope)
    vim.validate({
        scope = { scope, "string" },
    })

    if state:get_enabled() then
        log.debug(scope, "cc-tui is already enabled")
        return
    end

    state:set_enabled()

    -- Load test data
    local root, err = load_test_data()
    if not root then
        log.debug("main", "Failed to load test data: " .. (err or "unknown error"))
        vim.notify("CC-TUI: Failed to load test data", vim.log.levels.ERROR)
        state:set_disabled()
        return
    end

    main_state.tree_data = root

    -- Setup highlights
    Tree.setup_highlights()

    -- Create main popup window
    local session_info = Parser.get_session_info(main_state.messages)
    local title = session_info and session_info.model and (" CC-TUI [" .. session_info.model .. "] ") or " CC-TUI "

    main_state.popup = Popup({
        relative = "editor",
        position = "50%",
        size = {
            width = "90%",
            height = "90%",
        },
        enter = true,
        focusable = true,
        border = {
            style = "rounded",
            text = {
                top = title,
                top_align = "center",
            },
        },
        buf_options = {
            modifiable = false,
            readonly = true,
            filetype = "cc-tui",
        },
        win_options = {
            cursorline = true,
            number = false,
            relativenumber = false,
            signcolumn = "no",
            wrap = true,
            linebreak = true,
            breakindent = true,
            breakindentopt = "shift:2",
        },
    })

    -- Mount the popup
    main_state.popup:mount()

    -- Create tree with the popup's buffer
    main_state.tree = Tree.create_tree(root, {
        icons = {
            expanded = "▼",
            collapsed = "▶",
            empty = " ",
        },
    }, main_state.popup.bufnr)

    -- Render tree in popup buffer
    main_state.tree:render()

    -- Setup tree keybindings using Tree module (integrates with hybrid content rendering)
    local tree_config = {
        keymaps = {
            toggle = { "<Tab>", "<CR>" },
            close = { "q", "<Esc>" },
            expand_all = "E",
            collapse_all = "C",
            focus_next = { "j", "<Down>" },
            focus_prev = { "k", "<Up>" },
            copy_text = "y",
            close_content = "x",
            close_all_content = "X",
            search = "/",
            help = "?",
        },
        icons = {
            expanded = "▼",
            collapsed = "▶",
            empty = " ",
        },
        colors = {
            session = "CcTuiSession",
            message = "CcTuiMessage",
            tool = "CcTuiTool",
            result = "CcTuiResult",
            text = "CcTuiText",
            error = "CcTuiError",
        },
    }

    Tree.setup_keybindings(main_state.tree, main_state.popup.bufnr, tree_config)

    -- Add close window handler
    vim.keymap.set("n", "q", function()
        M.disable("keymap_close")
    end, {
        buffer = main_state.popup.bufnr,
        desc = "Close CC-TUI window",
        nowait = true,
    })

    vim.keymap.set("n", "<Esc>", function()
        M.disable("keymap_close")
    end, {
        buffer = main_state.popup.bufnr,
        desc = "Close CC-TUI window",
        nowait = true,
    })

    -- Store popup reference in state for compatibility
    state:set_ui_component(main_state.popup)

    -- Save state
    state:save()

    log.debug("main", "CC-TUI enabled successfully")
end

---Disable the plugin, clear highlight groups and autocmds, closes windows and resets state
---@param scope string Internal identifier for logging purposes
---@private
function M.disable(scope)
    vim.validate({
        scope = { scope, "string" },
    })

    if not state:get_enabled() then
        log.debug(scope, "cc-tui is already disabled")
        return
    end

    -- Close popup
    if main_state.popup then
        main_state.popup:unmount()
        main_state.popup = nil
    end

    -- Clean up content windows
    Tree.cleanup_content_windows()

    -- Clear tree and data
    main_state.tree = nil
    main_state.tree_data = nil
    main_state.messages = {}

    state:set_disabled()

    -- Save state
    state:save()

    log.debug("main", "CC-TUI disabled")

    return true, nil
end

---Refresh the tree with new data
---@return nil
function M.refresh()
    if not state:get_enabled() then
        log.debug("main", "Cannot refresh: plugin disabled")
        return
    end

    log.debug("main", "Refreshing tree...")

    -- Reload test data
    local root, err = load_test_data()
    if not root then
        log.debug("main", "Failed to reload test data: " .. (err or "unknown error"))
        vim.notify("CC-TUI: Failed to reload test data", vim.log.levels.ERROR)
        return
    end

    main_state.tree_data = root

    -- Update tree
    if main_state.tree then
        Tree.update_tree(main_state.tree, root, {
            icons = {
                expanded = "▼",
                collapsed = "▶",
                empty = " ",
            },
            colors = {
                session = "CcTuiSession",
                message = "CcTuiMessage",
                tool = "CcTuiTool",
                result = "CcTuiResult",
                text = "CcTuiText",
                error = "CcTuiError",
            },
        })
    end

    log.debug("main", "Tree refreshed")
    vim.notify("CC-TUI: Tree refreshed", vim.log.levels.INFO)
end

---Process a new JSONL line (for streaming support)
---@param line string JSONL line to process
---@return nil
function M.process_line(line)
    vim.validate({
        line = { line, "string" },
    })

    if not state:get_enabled() then
        log.debug("main", "Cannot process line: plugin disabled")
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

    -- Rebuild tree
    local session_info = Parser.get_session_info(main_state.messages)
    local root = TreeBuilder.build_tree(main_state.messages, session_info)
    main_state.tree_data = root

    -- Update tree display
    if main_state.tree then
        Tree.update_tree(main_state.tree, root, {
            icons = {
                expanded = "▼",
                collapsed = "▶",
                empty = " ",
            },
            colors = {
                session = "CcTuiSession",
                message = "CcTuiMessage",
                tool = "CcTuiTool",
                result = "CcTuiResult",
                text = "CcTuiText",
                error = "CcTuiError",
            },
        })
    end

    log.debug("main", string.format("Processed message type: %s", msg.type))
end

---Start streaming from Claude CLI
---@param config? table StreamProvider configuration {command, args, timeout}
---@return nil
function M.start_streaming(config)
    vim.validate({
        config = { config, "table", true },
    })

    -- Stop any existing streaming
    M.stop_streaming()

    -- Default configuration for Claude CLI
    local stream_config = vim.tbl_deep_extend("force", {
        command = "claude-code",
        args = { "--output-format", "stream-json" },
        timeout = 60000, -- 60 seconds
    }, config or {})

    -- Create streaming provider
    local provider = StreamProvider:new(stream_config)

    -- Set up callbacks for live updates
    provider:register_callback("on_start", function()
        log.debug("main", "Streaming started")
    end)

    provider:register_callback("on_data", function(line)
        -- Use vim.schedule for thread-safe UI updates
        vim.schedule(function()
            M.process_line(line)
        end)
    end)

    provider:register_callback("on_error", function(err)
        vim.schedule(function()
            log.debug("main", "Streaming error: " .. err)
            vim.notify("CC-TUI Streaming Error: " .. err, vim.log.levels.ERROR)
        end)
    end)

    provider:register_callback("on_complete", function()
        vim.schedule(function()
            log.debug("main", "Streaming completed")
            vim.notify("CC-TUI: Streaming completed", vim.log.levels.INFO)
            main_state.streaming_provider = nil
        end)
    end)

    -- Store provider and start streaming
    main_state.streaming_provider = provider
    provider:start()

    log.debug("main", string.format("Started streaming with command: %s", stream_config.command))
end

---Stop active streaming
---@return nil
function M.stop_streaming()
    if main_state.streaming_provider then
        log.debug("main", "Stopping active streaming")
        main_state.streaming_provider:stop()
        main_state.streaming_provider = nil
        vim.notify("CC-TUI: Streaming stopped", vim.log.levels.INFO)
    end
end

---Get current state for debugging
---@return CcTui.MainState state
function M.get_state()
    return main_state
end

return M
