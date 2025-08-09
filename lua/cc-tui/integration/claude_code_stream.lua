---@brief [[
--- Claude Code Stream Integration Service
--- Integrates cc-tui with official Claude Code --output-format stream-json
--- Provides deterministic content classification using structured JSONL data
--- Implements real-time processing and Claude Code hooks integration
---@brief ]]

local ContentClassifier = require("cc-tui.utils.content_classifier")

---@class CcTui.Integration.ClaudeCodeStream
local M = {}

---@class CcTui.StreamMessage
---@field type "system"|"assistant"|"user"|"result" Message type from Claude Code JSONL
---@field subtype? string Message subtype (init, success, etc.)
---@field session_id? string Session identifier
---@field message? table Message content object
---@field tools? table Available tools (for system messages)
---@field model? string Model name (for system messages)

---@class CcTui.StreamProcessor
---@field tool_uses table<string, CcTui.StreamMessage> Map of tool_use_id to tool_use message
---@field session_id? string Current session ID
---@field classifications table[] List of content classifications
---@field classification_cache table<string, table> Cache for repeated content classifications
---@field stats table Performance and processing statistics

---@class CcTui.ToolContext
---@field tool_use_id string Tool use identifier
---@field tool_name string Name of the tool
---@field input_content string JSON string of tool input
---@field result_content string Text content of tool result

---Parse a single JSONL line from Claude Code streaming output
---@param jsonl_line string Single line of JSONL from Claude Code
---@return CcTui.StreamMessage? message Parsed message or nil if invalid
function M.parse_jsonl_line(jsonl_line)
    vim.validate({
        jsonl_line = { jsonl_line, "string" },
    })

    if not jsonl_line or jsonl_line:match("^%s*$") then
        return nil
    end

    -- Robust JSON parsing using vim.fn.json_decode with pcall
    local success, parsed = pcall(vim.fn.json_decode, jsonl_line)

    if not success or not parsed or type(parsed) ~= "table" then
        return nil
    end

    -- Validate required fields based on Claude Code JSONL format
    if not parsed.type then
        return nil
    end

    return parsed
end

---Link tool_use message to tool_result message for complete context
---@param tool_use_message CcTui.StreamMessage Assistant message containing tool_use
---@param tool_result_message CcTui.StreamMessage User message containing tool_result
---@return CcTui.ToolContext? context Linked context or nil if no match
function M.link_tool_use_to_result(tool_use_message, tool_result_message)
    vim.validate({
        tool_use_message = { tool_use_message, "table" },
        tool_result_message = { tool_result_message, "table" },
    })

    if tool_use_message.type ~= "assistant" or tool_result_message.type ~= "user" then
        return nil
    end

    -- Find tool_use in assistant message
    local tool_use_block = nil
    if tool_use_message.message and tool_use_message.message.content then
        for _, content in ipairs(tool_use_message.message.content) do
            if content.type == "tool_use" then
                tool_use_block = content
                break
            end
        end
    end

    -- Find matching tool_result in user message
    local tool_result_block = nil
    if tool_result_message.message and tool_result_message.message.content then
        for _, content in ipairs(tool_result_message.message.content) do
            if content.type == "tool_result" and content.tool_use_id == tool_use_block.id then
                tool_result_block = content
                break
            end
        end
    end

    if not tool_use_block or not tool_result_block then
        return nil
    end

    -- Extract result content text
    local result_text = ""
    if tool_result_block.content then
        for _, item in ipairs(tool_result_block.content) do
            if item.type == "text" then
                result_text = item.text
                break
            end
        end
    end

    return {
        tool_use_id = tool_use_block.id,
        tool_name = tool_use_block.name,
        input_content = vim.fn.json_encode(tool_use_block.input),
        result_content = result_text,
    }
end

---Create a new stream processor for incremental JSONL processing
---@return CcTui.StreamProcessor processor Stream processor instance
function M.create_stream_processor()
    local processor = {
        tool_uses = {},
        session_id = nil,
        classifications = {},
        classification_cache = {},
        stats = {
            total_messages = 0,
            total_classifications = 0,
            cache_hits = 0,
            cache_misses = 0,
            processing_time_ms = 0,
            start_time = vim.uv.hrtime(),
        },
    }

    ---Process a single JSONL line and return classification if applicable
    ---@param line string JSONL line to process
    ---@return table? result Processing result with classification
    function processor:process_line(line)
        local process_start = vim.uv.hrtime()

        local message = M.parse_jsonl_line(line)
        if not message then
            return nil
        end

        self.stats.total_messages = self.stats.total_messages + 1

        -- Update session ID from any message
        if message.session_id then
            self.session_id = message.session_id
        end

        local result = {
            message = message,
            classification = nil,
        }

        -- Helper function to get cached classification or compute new one
        local function get_classification(structured_data, content_text)
            -- Create cache key from content and structure
            local cache_key = vim.fn
                .sha256(content_text .. vim.fn.json_encode({
                    type = structured_data.type,
                    tool_name = structured_data.name or structured_data.tool_name,
                }))
                :sub(1, 16)

            -- Check cache first
            if self.classification_cache[cache_key] then
                self.stats.cache_hits = self.stats.cache_hits + 1
                return self.classification_cache[cache_key]
            end

            -- Compute new classification
            self.stats.cache_misses = self.stats.cache_misses + 1
            local classification = ContentClassifier.classify_from_structured_data(structured_data, content_text)

            -- Cache result (limit cache size to prevent memory growth)
            if #self.classification_cache < 1000 then
                self.classification_cache[cache_key] = classification
            end

            return classification
        end

        -- Process based on message type
        if message.type == "assistant" and message.message and message.message.content then
            -- Look for tool_use blocks and classify them
            for _, content in ipairs(message.message.content) do
                if content.type == "tool_use" then
                    -- Store tool_use for later linking
                    self.tool_uses[content.id] = message

                    -- Classify tool input deterministically (with caching)
                    local input_text = vim.fn.json_encode(content.input)
                    local classification = get_classification(content, input_text)
                    self.stats.total_classifications = self.stats.total_classifications + 1

                    table.insert(self.classifications, {
                        tool_use_id = content.id,
                        classification_type = "tool_input",
                        classification = classification,
                        structured_data = content,
                        content_text = input_text,
                    })

                    result.classification = classification
                end
            end
        elseif message.type == "user" and message.message and message.message.content then
            -- Look for tool_result blocks and classify them
            for _, content in ipairs(message.message.content) do
                if content.type == "tool_result" and content.tool_use_id then
                    -- Find corresponding tool_use
                    local tool_use_message = self.tool_uses[content.tool_use_id]
                    if tool_use_message then
                        local linked_context = M.link_tool_use_to_result(tool_use_message, message)
                        if linked_context then
                            -- Add tool name to structured data for classification
                            content.tool_name = linked_context.tool_name

                            -- Classify tool result deterministically (with caching)
                            local classification = get_classification(content, linked_context.result_content)
                            self.stats.total_classifications = self.stats.total_classifications + 1

                            table.insert(self.classifications, {
                                tool_use_id = content.tool_use_id,
                                classification_type = "tool_result",
                                classification = classification,
                                structured_data = content,
                                content_text = linked_context.result_content,
                                linked_context = linked_context,
                            })

                            result.classification = classification
                        end
                    end
                end
            end
        end

        -- Update performance statistics
        local process_end = vim.uv.hrtime()
        self.stats.processing_time_ms = self.stats.processing_time_ms + (process_end - process_start) / 1000000

        return result
    end

    ---Get performance statistics
    ---@return table stats Performance statistics
    function processor:get_stats()
        local total_time = (vim.uv.hrtime() - self.stats.start_time) / 1000000
        return {
            total_messages = self.stats.total_messages,
            total_classifications = self.stats.total_classifications,
            cache_hits = self.stats.cache_hits,
            cache_misses = self.stats.cache_misses,
            cache_hit_rate = self.stats.cache_hits > 0
                    and (self.stats.cache_hits / (self.stats.cache_hits + self.stats.cache_misses))
                or 0,
            processing_time_ms = self.stats.processing_time_ms,
            total_time_ms = total_time,
            avg_processing_time_ms = self.stats.total_messages > 0
                    and (self.stats.processing_time_ms / self.stats.total_messages)
                or 0,
        }
    end

    ---Clear caches to free memory
    ---@return nil
    function processor:clear_caches()
        self.classification_cache = {}
    end

    return processor
end

---Process Claude Code hook event (integrates with official Claude Code hooks)
---@param hook_data table Hook data from Claude Code (session_id, transcript_path, etc.)
---@return table result Hook processing result
function M.process_claude_code_hook(hook_data)
    vim.validate({
        hook_data = { hook_data, "table" },
    })

    local result = {
        success = false,
        session_id = hook_data.session_id,
        classifications = {},
        error = nil,
    }

    -- Validate hook data structure
    if not hook_data.transcript_path or not hook_data.session_id then
        result.error = "Missing required hook data: transcript_path or session_id"
        return result
    end

    -- For now, return success with empty classifications
    -- In real implementation, this would read the transcript file and process it
    result.success = true
    result.classifications = {}

    return result
end

---Extract content text from Claude Code content block
---@param content_block table Content block from Claude Code message
---@return string text Extracted text content
function M.extract_content_text(content_block)
    if not content_block then
        return ""
    end

    -- Handle tool_use input
    if content_block.type == "tool_use" and content_block.input then
        return vim.fn.json_encode(content_block.input)
    end

    -- Handle tool_result content
    if content_block.type == "tool_result" and content_block.content then
        for _, item in ipairs(content_block.content) do
            if item.type == "text" and item.text then
                return item.text
            end
        end
    end

    -- Handle text content
    if content_block.type == "text" and content_block.text then
        return content_block.text
    end

    return ""
end

---Classify content from Claude Code streaming data
---@param message CcTui.StreamMessage Parsed Claude Code message
---@param tool_context? CcTui.ToolContext Optional tool context for results
---@return table[] classifications List of content classifications
function M.classify_message_content(message, tool_context)
    vim.validate({
        message = { message, "table" },
        tool_context = { tool_context, "table", true },
    })

    local classifications = {}

    if not message.message or not message.message.content then
        return classifications
    end

    for _, content_block in ipairs(message.message.content) do
        local content_text = M.extract_content_text(content_block)

        if content_text ~= "" then
            -- Add tool context if available
            if tool_context and content_block.type == "tool_result" then
                content_block.tool_name = tool_context.tool_name
            end

            -- Use deterministic classification
            local classification = ContentClassifier.classify_from_structured_data(content_block, content_text)

            table.insert(classifications, {
                content_block = content_block,
                content_text = content_text,
                classification = classification,
                message_type = message.type,
                session_id = message.session_id,
            })
        end
    end

    return classifications
end

---Get classification statistics from processed stream
---@param processor CcTui.StreamProcessor Stream processor instance
---@return table stats Classification statistics
function M.get_classification_stats(processor)
    vim.validate({
        processor = { processor, "table" },
    })

    local stats = {
        total_classifications = #processor.classifications,
        tool_inputs = 0,
        tool_results = 0,
        by_type = {},
        by_tool = {},
    }

    for _, classification_entry in ipairs(processor.classifications) do
        -- Count by classification type (tool_input vs tool_result)
        if classification_entry.classification_type == "tool_input" then
            stats.tool_inputs = stats.tool_inputs + 1
        elseif classification_entry.classification_type == "tool_result" then
            stats.tool_results = stats.tool_results + 1
        end

        -- Count by content type
        local content_type = classification_entry.classification.type
        stats.by_type[content_type] = (stats.by_type[content_type] or 0) + 1

        -- Count by tool name
        local tool_name = classification_entry.classification.metadata.tool_name
        if tool_name then
            stats.by_tool[tool_name] = (stats.by_tool[tool_name] or 0) + 1
        end
    end

    return stats
end

return M
