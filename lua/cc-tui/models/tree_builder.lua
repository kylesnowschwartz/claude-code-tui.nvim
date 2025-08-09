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
                                        create_unique_text_node,
                                        content.name -- Pass tool name for formatting
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
        -- Look for text content first
        for _, content in ipairs(message.message.content) do
            if content.type == "text" and content.text then
                -- Take meaningful text, cleaned up
                local text = content.text:gsub("[\n\r]", " "):gsub("%s+", " ")
                preview = text
                break
            end
        end

        -- If no text found but has tools, create a tool summary
        if preview == "" then
            local tool_count = 0
            local tool_names = {}
            for _, content in ipairs(message.message.content) do
                if content.type == "tool_use" then
                    tool_count = tool_count + 1
                    table.insert(tool_names, content.name)
                end
            end
            if tool_count > 0 then
                if tool_count == 1 then
                    preview = string.format("Used %s", tool_names[1])
                else
                    preview = string.format("Used %d tools: %s", tool_count, table.concat(tool_names, ", "))
                end
            end
        end
    end

    local node = Node.create_message_node(msg_id, role, preview)

    -- Only add text children if no tools AND text is significantly longer than preview
    local has_tools = false
    local text_content = ""

    if message.message.content then
        for _, content in ipairs(message.message.content) do
            if content.type == "tool_use" then
                has_tools = true
            elseif content.type == "text" and content.text then
                text_content = content.text
            end
        end

        -- Only add detailed text as child if:
        -- 1. No tools present (tools are more important than text details)
        -- 2. Text is significantly longer than the preview (avoid duplication)
        if not has_tools and text_content and #text_content > 150 then
            local clean_text = text_content:gsub("[\n\r]", " "):gsub("%s+", " ")

            -- Break long text into readable chunks
            local chunks = M.split_text_into_chunks(clean_text, 120)
            for i, chunk in ipairs(chunks) do
                local prefix = i == 1 and "Full text: " or "          "
                local text_node = create_text_node(prefix .. chunk, node.id, i)
                table.insert(node.children, text_node)
            end
        end
    end

    return node
end

---Create result node from tool result content with Claude Code stream integration
---@param tool_use_id string Tool use identifier
---@param content table Tool result content (Claude Code structured data)
---@param create_text_node function Function to create unique text nodes
---@param tool_name? string Name of the tool that generated this result
---@param _stream_context? table Optional Claude Code stream context for deterministic classification (unused)
---@return CcTui.ResultNode? node Result node or nil
function M.create_result_node_from_content(tool_use_id, content, create_text_node, tool_name, _stream_context)
    vim.validate({
        tool_use_id = { tool_use_id, "string" },
        content = { content, "table" },
    })

    -- Extract text from content
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

    -- Create result node with tool-aware formatting
    local node = M.create_tool_aware_result_node(tool_use_id, result_text, is_error, tool_name, content)

    -- Add formatted content as children based on tool type and content length
    -- Enhanced with Claude Code stream context for deterministic classification
    if result_text and result_text ~= "" then
        M.add_formatted_result_children(node, result_text, tool_name, create_text_node, content)
    end

    return node
end

---Create tool-aware result node with appropriate preview
---@param tool_use_id string Tool use identifier
---@param result_text string Result content text
---@param is_error boolean Whether this is an error result
---@param tool_name? string Name of the tool
---@param structured_content? table Original Claude Code JSON structure
---@return CcTui.ResultNode node Result node
function M.create_tool_aware_result_node(tool_use_id, result_text, is_error, tool_name, structured_content)
    local preview_text = "Result" -- luacheck: ignore 311

    if is_error then
        preview_text = "❌ Error"
    else
        -- Create tool-specific previews
        local line_count = M.count_result_lines(result_text)

        if tool_name == "Read" then
            preview_text = line_count > 10 and string.format("+%d lines (expand to view)", line_count) or "File content"
        elseif tool_name == "Bash" then
            local first_line = M.get_first_line(result_text)
            preview_text = line_count > 5 and string.format("Command output (%d lines)", line_count) or first_line
        elseif tool_name and tool_name:match("^mcp__") then
            -- MCP tool results (API responses, etc.)
            preview_text = line_count > 8 and string.format("API response (%d lines)", line_count) or "API result"
        else
            -- Generic tool result
            preview_text = line_count > 6 and string.format("Output (%d lines)", line_count)
                or M.get_first_line(result_text)
        end
    end

    return Node.create_result_node(tool_use_id, result_text, is_error, preview_text, structured_content)
end

---Add formatted children to result node based on content type
---@param node CcTui.ResultNode Result node to add children to
---@param result_text string Full result text
---@param tool_name? string Name of the tool
---@param create_text_node function Function to create text nodes
---@param structured_content? table Original structured content from Claude Code JSON
---@return nil
function M.add_formatted_result_children(node, result_text, _, create_text_node, structured_content)
    local line_count = M.count_result_lines(result_text)

    -- Hybrid approach: Only add children for very small content
    -- Large content will be handled by ContentRenderer popup windows

    -- Use rich display threshold logic (must match tree.lua logic)
    local should_use_rich_display
    if structured_content then
        -- DETERMINISTIC classification using structured Claude Code JSON data
        local ContentClassifier = require("cc-tui.utils.content_classifier")
        should_use_rich_display = ContentClassifier.should_use_rich_display_structured(structured_content, result_text)
    else
        -- Fallback to legacy inference-based classification
        should_use_rich_display = M.should_use_rich_display_for_content(result_text, node.is_error)
    end

    if should_use_rich_display then
        -- Content will be displayed via ContentRenderer - no children needed
        -- This prevents text wrapping issues and enables proper content display
        return
    end

    -- Only for very small content - add minimal inline children
    if line_count <= 2 and #result_text <= 100 then
        local clean_text = result_text:gsub("[\n\r]", " "):gsub("%s+", " ")
        local text_node = create_text_node(clean_text, node.id, 1)
        table.insert(node.children, text_node)
        return
    end

    -- For slightly larger but still small content, add limited children
    if line_count <= 4 and #result_text <= 200 then
        local lines = vim.split(result_text, "\n")
        for i = 1, math.min(2, #lines) do
            local text_node = create_text_node(lines[i], node.id, i)
            table.insert(node.children, text_node)
        end
        if #lines > 2 then
            local more_node = create_text_node(string.format("... (%d more lines)", #lines - 2), node.id, 3)
            table.insert(node.children, more_node)
        end
    end
end

---Determine if content should use rich display (matches tree.lua logic)
---@param content string Content to check
---@param is_error? boolean Whether content is an error
---@return boolean should_use_rich_display Whether ContentRenderer should handle this
function M.should_use_rich_display_for_content(content, is_error)
    -- Always use rich display for errors
    if is_error then
        return true
    end

    -- Use rich display if content is substantial
    if type(content) == "string" then
        local line_count = M.count_result_lines(content)
        local char_count = #content

        -- Use rich display for:
        -- - More than 5 lines
        -- - More than 200 characters
        -- - JSON-like content
        if line_count > 5 or char_count > 200 then
            return true
        end

        -- Check for JSON content using unified ContentClassifier
        local ContentClassifier = require("cc-tui.utils.content_classifier")
        if ContentClassifier.is_json_content(content) then
            return true
        end
    end

    return false
end

---Format file content (Read tool results)
---@param node CcTui.ResultNode Result node
---@param content string File content
---@param create_text_node function Function to create text nodes
---@return nil
function M.format_file_content(node, content, create_text_node)
    -- For file content, show only first few lines for short files
    local lines = vim.split(content, "\n")

    if #lines <= 3 then
        -- Very short files - show all lines
        for i, line in ipairs(lines) do
            local text_node = create_text_node(line, node.id, i)
            table.insert(node.children, text_node)
        end
    elseif #lines <= 6 then
        -- Short files - show first 3 lines only
        for i = 1, math.min(3, #lines) do
            local text_node = create_text_node(lines[i], node.id, i)
            table.insert(node.children, text_node)
        end
        if #lines > 3 then
            local more_node = create_text_node(string.format("... (%d more lines)", #lines - 3), node.id, 4)
            table.insert(node.children, more_node)
        end
    else
        -- Medium+ files - no children, preview is sufficient
        -- This should not be reached due to parent logic, but here for safety
        return
    end
end

---Format command output (Bash tool results)
---@param node CcTui.ResultNode Result node
---@param content string Command output
---@param create_text_node function Function to create text nodes
---@return nil
function M.format_command_output(node, content, create_text_node)
    local lines = vim.split(content, "\n")

    if #lines <= 2 then
        -- Very short output - show all
        for i, line in ipairs(lines) do
            local text_node = create_text_node(line, node.id, i)
            table.insert(node.children, text_node)
        end
    elseif #lines <= 4 then
        -- Short output - show first few lines
        for i = 1, math.min(3, #lines) do
            local text_node = create_text_node(lines[i], node.id, i)
            table.insert(node.children, text_node)
        end
        if #lines > 3 then
            local more_node = create_text_node(string.format("... (%d more lines)", #lines - 3), node.id, 4)
            table.insert(node.children, more_node)
        end
    else
        -- Medium+ output - no children, preview is sufficient
        -- This should not be reached due to parent logic, but here for safety
        return
    end
end

---Format API response (MCP tool results)
---@param node CcTui.ResultNode Result node
---@param content string API response content
---@param create_text_node function Function to create text nodes
---@return nil
function M.format_api_response(node, content, create_text_node)
    -- Try to detect JSON and format appropriately
    local is_json = content:match("^%s*{") or content:match("^%s*%[")
    local line_count = M.count_result_lines(content)

    if is_json then
        if line_count <= 3 then
            -- Very short JSON - show formatted in one line
            local formatted = content:gsub("[\n\r]", " "):gsub("%s+", " ")
            local text_node = create_text_node(formatted, node.id, 1, 150)
            table.insert(node.children, text_node)
        elseif line_count <= 6 then
            -- Short JSON - show first few lines
            local lines = vim.split(content, "\n")
            for i = 1, math.min(3, #lines) do
                local text_node = create_text_node(lines[i], node.id, i)
                table.insert(node.children, text_node)
            end
            if #lines > 3 then
                local more_node = create_text_node(string.format("... (%d more lines)", #lines - 3), node.id, 4)
                table.insert(node.children, more_node)
            end
        else
            -- Long JSON - no children, preview is sufficient
            return
        end
    else
        M.format_generic_output(node, content, create_text_node)
    end
end

---Format generic tool output
---@param node CcTui.ResultNode Result node
---@param content string Output content
---@param create_text_node function Function to create text nodes
---@return nil
function M.format_generic_output(node, content, create_text_node)
    -- Generic formatting - conservative approach for readability
    local line_count = M.count_result_lines(content)

    if line_count <= 2 and #content <= 150 then
        -- Very short content - show as is
        local clean_text = content:gsub("[\n\r]", " "):gsub("%s+", " ")
        local text_node = create_text_node(clean_text, node.id, 1)
        table.insert(node.children, text_node)
    elseif line_count <= 4 then
        -- Short content - show first few lines
        local lines = vim.split(content, "\n")
        for i = 1, math.min(2, #lines) do
            local text_node = create_text_node(lines[i], node.id, i)
            table.insert(node.children, text_node)
        end
        if #lines > 2 then
            local more_node = create_text_node(string.format("... (%d more lines)", #lines - 2), node.id, 3)
            table.insert(node.children, more_node)
        end
    else
        -- Medium+ content - no children, preview is sufficient
        return
    end
end

---Count lines in result text
---@param text string Text to count
---@return number count Number of lines
function M.count_result_lines(text)
    if not text or text == "" then
        return 0
    end
    local _, count = text:gsub("\n", "")
    return count + 1
end

---Get first line of text
---@param text string Text to extract from
---@return string first_line First line of text
function M.get_first_line(text)
    if not text or text == "" then
        return ""
    end
    local first_line = text:match("^[^\n]*")
    return first_line and first_line:sub(1, 80) or ""
end

---Split long text into readable chunks at word boundaries
---@param text string Text to split
---@param max_chunk_size number Maximum size per chunk
---@return string[] chunks Array of text chunks
function M.split_text_into_chunks(text, max_chunk_size)
    vim.validate({
        text = { text, "string" },
        max_chunk_size = { max_chunk_size, "number" },
    })

    if #text <= max_chunk_size then
        return { text }
    end

    local chunks = {}
    local remaining = text

    while #remaining > 0 do
        if #remaining <= max_chunk_size then
            table.insert(chunks, remaining)
            break
        end

        -- Find the last space within the chunk size
        local chunk = remaining:sub(1, max_chunk_size)
        local last_space = chunk:match(".*()%s")

        if last_space and last_space > max_chunk_size / 2 then
            -- Cut at last space if it's not too early
            chunk = remaining:sub(1, last_space - 1)
            remaining = remaining:sub(last_space + 1)
        else
            -- No good break point, cut at limit
            chunk = remaining:sub(1, max_chunk_size - 3) .. "..."
            remaining = remaining:sub(max_chunk_size - 2)
        end

        table.insert(chunks, chunk)
    end

    return chunks
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
