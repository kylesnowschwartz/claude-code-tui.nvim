---@brief [[
--- Tree builder for constructing hierarchical structure from messages
--- Converts parsed Claude Code messages into a tree of nodes
---@brief ]]

local Node = require("cc-tui.models.node")

---@class CcTui.Models.TreeBuilder
local M = {}

---Build tree structure from parsed messages
---@param messages CcTui.Message[] List of parsed messages
---@param session_info? table Session information
---@return CcTui.SessionNode root Root session node with complete tree
function M.build_tree(messages, session_info)
    vim.validate({
        messages = { messages, "table" },
        session_info = { session_info, "table", true },
    })

    -- Create root session node
    local session_id = (session_info and session_info.id) or "unknown"
    local root = Node.create_session_node(session_id, session_info)

    -- Global counter for unique text node IDs
    local text_node_counter = 0

    -- Helper function to create unique text nodes
    local function create_unique_text_node(text, parent_id)
        text_node_counter = text_node_counter + 1
        return Node.create_text_node(text, parent_id, text_node_counter)
    end

    -- Build index of tool results
    local tool_results = {}

    -- First pass: collect all tool results
    for _, msg in ipairs(messages) do
        if msg.type == "user" and msg.message and msg.message.content then
            for _, content in ipairs(msg.message.content) do
                if content.type == "tool_result" and content.tool_use_id then
                    tool_results[content.tool_use_id] = {
                        message = msg,
                        content = content,
                    }
                end
            end
        end
    end

    -- Track processed message IDs to avoid duplicates
    local processed_messages = {}

    -- Second pass: build tree structure
    for i, msg in ipairs(messages) do
        if msg.type == "assistant" then
            local msg_id = (msg.message and msg.message.id) or ("msg-index-" .. tostring(i))

            -- Skip if we've already processed this message
            if not processed_messages[msg_id] then
                processed_messages[msg_id] = true

                local message_node = M.create_message_node_from_message(msg, create_unique_text_node)
                if message_node then
                    -- Add tool nodes as children
                    if msg.message and msg.message.content then
                        for _, content in ipairs(msg.message.content) do
                            if content.type == "tool_use" then
                                local tool_node = Node.create_tool_node(content.id, content.name, content.input)

                                -- Add result as child of tool if it exists
                                local result_data = tool_results[content.id]
                                if result_data then
                                    local result_node = M.create_result_node_from_content(
                                        content.id,
                                        result_data.content,
                                        create_unique_text_node
                                    )
                                    if result_node then
                                        table.insert(tool_node.children, result_node)
                                        tool_node.has_result = true
                                    end
                                end

                                table.insert(message_node.children, tool_node)
                            end
                        end
                    end

                    table.insert(root.children, message_node)
                end
            end
        elseif msg.type == "system" and msg.subtype == "init" then
            -- Update root node with init information
            root.model = msg.model
            root.cwd = msg.cwd
        elseif msg.type == "result" then
            -- Add result summary to root
            local result_text = string.format(
                "Session Complete: %s | Cost: $%.4f | Duration: %dms | Turns: %d",
                msg.subtype or "unknown",
                msg.total_cost_usd or 0,
                msg.duration_ms or 0,
                msg.num_turns or 0
            )
            local result_node = create_unique_text_node(result_text, root.id)
            table.insert(root.children, result_node)
        end
    end

    return root
end

---Create message node from parsed message
---@param message CcTui.Message Parsed message
---@param create_text_node function Function to create unique text nodes
---@return CcTui.MessageNode? node Message node or nil
function M.create_message_node_from_message(message, create_text_node)
    vim.validate({
        message = { message, "table" },
    })

    if not message.message then
        return nil
    end

    -- Use message ID or generate deterministic fallback
    local msg_id = message.message.id
    if not msg_id then
        -- Create deterministic ID based on content hash or timestamp
        local content_text = ""
        if message.message.content and #message.message.content > 0 then
            local first_content = message.message.content[1]
            if first_content.type == "text" and first_content.text then
                content_text = first_content.text:sub(1, 50) -- First 50 chars for uniqueness
            end
        end
        msg_id = "msg-" .. tostring(vim.fn.sha256(content_text .. (message.timestamp or "")):sub(1, 12))
    end

    local role = message.message.role or "assistant"

    -- Extract text preview (ensure single line)
    local preview = ""
    if message.message.content then
        for _, content in ipairs(message.message.content) do
            if content.type == "text" and content.text then
                -- Take only the first line and truncate if needed
                local first_line = content.text:match("^[^\n]*")
                preview = first_line or ""
                break
            end
        end
    end

    local node = Node.create_message_node(msg_id, role, preview)

    -- Add text content as children (if no tools)
    local has_tools = false
    if message.message.content then
        for _, content in ipairs(message.message.content) do
            if content.type == "tool_use" then
                has_tools = true
                break
            end
        end

        if not has_tools then
            for _, content in ipairs(message.message.content) do
                if content.type == "text" and content.text then
                    -- Split text into lines for display
                    for line in content.text:gmatch("[^\n]+") do
                        local text_node = create_text_node(line, node.id)
                        table.insert(node.children, text_node)
                    end
                end
            end
        end
    end

    return node
end

---Create result node from tool result content
---@param tool_use_id string Tool use identifier
---@param content table Tool result content
---@param create_text_node function Function to create unique text nodes
---@return CcTui.ResultNode? node Result node or nil
function M.create_result_node_from_content(tool_use_id, content, create_text_node)
    vim.validate({
        tool_use_id = { tool_use_id, "string" },
        content = { content, "table" },
    })

    -- Extract text from content (ensure single line for node text)
    local result_text = ""
    local is_error = false

    if type(content.content) == "table" then
        for _, item in ipairs(content.content) do
            if type(item) == "table" and item.type == "text" then
                result_text = item.text
                break
            end
        end
    elseif type(content.content) == "string" then
        result_text = content.content
    end

    -- Check for error indicators
    if content.is_error or (result_text and (result_text:match("^Error:") or result_text:match("^error:"))) then
        is_error = true
    end

    local node = Node.create_result_node(tool_use_id, result_text, is_error)

    -- Add content lines as children
    if result_text and result_text ~= "" then
        for line in result_text:gmatch("[^\n]+") do
            local text_node = create_text_node(line, node.id)
            table.insert(node.children, text_node)
        end
    end

    return node
end

---Process nested tools (for Task agents)
---@param parent_node CcTui.ToolNode Parent tool node
---@param messages CcTui.Message[] All messages
---@return nil
function M.process_nested_tools(parent_node, messages)
    vim.validate({
        parent_node = { parent_node, "table" },
        messages = { messages, "table" },
    })

    -- Look for messages with parent_tool_use_id matching this tool
    for _, msg in ipairs(messages) do
        if msg.parent_tool_use_id == parent_node.tool_id then
            -- This is a nested tool call
            local child_node = M.create_message_node_from_message(msg)
            if child_node then
                table.insert(parent_node.children, child_node)
            end
        end
    end
end

return M
