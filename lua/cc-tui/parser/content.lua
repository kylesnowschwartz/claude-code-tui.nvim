---@brief [[
--- Semantic content parser for Claude Code output
--- Analyzes and structures content for better readability and navigation
---@brief ]]

---@class CcTui.Parser.Content
local M = {}

---@enum CcTui.ContentType
M.ContentType = {
    PARAGRAPH = "paragraph",
    JSON = "json",
    CODE_BLOCK = "code_block",
    LIST = "list",
    URL = "url",
    TITLE_SECTION = "title_section",
    ERROR = "error",
    PLAIN = "plain",
}

---@class CcTui.ContentSegment
---@field type CcTui.ContentType Content type
---@field content string Raw content
---@field metadata table Additional information about the content
---@field collapsible boolean Whether this content should be collapsible
---@field preview string Short preview for collapsed state

---Analyze content and detect its semantic type
---@param text string Text content to analyze
---@return CcTui.ContentType type Detected content type
---@return table metadata Additional metadata about the content
function M.detect_content_type(text)
    vim.validate({
        text = { text, "string" },
    })

    -- Clean and normalize text for analysis
    local normalized = text:gsub("^%s+", ""):gsub("%s+$", "")

    -- Detect JSON content
    if M.is_json_content(normalized) then
        local line_count = M.count_lines(text)
        return M.ContentType.JSON,
            {
                line_count = line_count,
                collapsible = line_count > 3,
            }
    end

    -- Detect code blocks
    if M.is_code_block(normalized) then
        return M.ContentType.CODE_BLOCK, { language = M.detect_language(normalized) }
    end

    -- Detect lists
    if M.is_list_content(normalized) then
        local items = M.extract_list_items(normalized)
        return M.ContentType.LIST,
            {
                items = items,
                list_type = M.detect_list_type(normalized),
            }
    end

    -- Detect title sections (TITLE:, DESCRIPTION:, etc.)
    if M.is_title_section(normalized) then
        local title = M.extract_title(normalized)
        return M.ContentType.TITLE_SECTION, { title = title }
    end

    -- Detect error content
    if M.is_error_content(normalized) then
        return M.ContentType.ERROR, { error_type = M.detect_error_type(normalized) }
    end

    -- Detect URLs
    if M.contains_urls(normalized) then
        local urls = M.extract_urls(normalized)
        return M.ContentType.URL, { urls = urls }
    end

    -- Check if it's a substantial paragraph
    if M.is_paragraph(normalized) then
        return M.ContentType.PARAGRAPH, { word_count = M.count_words(normalized) }
    end

    -- Default to plain text
    return M.ContentType.PLAIN, {}
end

---Check if content appears to be JSON
---@param text string Text to check
---@return boolean is_json Whether the text is JSON content
function M.is_json_content(text)
    -- Look for JSON patterns
    if text:match("^%s*{") and text:match("}%s*$") then
        return true
    end
    if text:match("^%s*%[") and text:match("%]%s*$") then
        return true
    end
    -- Look for JSON-like key-value patterns
    if text:match('"[^"]+"%s*:%s*') and (text:match("{") or text:match("}")) then
        return true
    end
    return false
end

---Check if content is a code block
---@param text string Text to check
---@return boolean is_code Whether the text is a code block
function M.is_code_block(text)
    -- Look for common code patterns
    if text:match("```") then
        return true
    end
    -- Look for code-like indentation patterns
    local lines = vim.split(text, "\n")
    local indent_count = 0
    for _, line in ipairs(lines) do
        if line:match("^%s%s%s%s+") then -- 4+ spaces indent
            indent_count = indent_count + 1
        end
    end
    return indent_count >= 3 -- Multiple indented lines suggest code
end

---Check if content is a list
---@param text string Text to check
---@return boolean is_list Whether the text is a list
function M.is_list_content(text)
    local lines = vim.split(text, "\n")
    local list_indicators = 0

    for _, line in ipairs(lines) do
        local trimmed = line:gsub("^%s+", "")
        -- Bullet points
        if trimmed:match("^[-*+]%s") then
            list_indicators = list_indicators + 1
        end
        -- Numbered lists
        if trimmed:match("^%d+%.%s") then
            list_indicators = list_indicators + 1
        end
    end

    return list_indicators >= 2 -- At least 2 list items
end

---Check if content is a title section
---@param text string Text to check
---@return boolean is_title Whether the text starts with a title pattern
function M.is_title_section(text)
    -- Look for patterns like "TITLE:", "DESCRIPTION:", etc.
    return text:match("^[A-Z][A-Z%s_]+:%s*") ~= nil
end

---Check if content indicates an error
---@param text string Text to check
---@return boolean is_error Whether the text represents an error
function M.is_error_content(text)
    local lower = text:lower()
    return lower:match("^error:")
        or lower:match("^failed")
        or lower:match("exception")
        or lower:match("traceback")
        or text:match("is_error.*true")
end

---Check if content is a substantial paragraph
---@param text string Text to check
---@return boolean is_paragraph Whether the text is a paragraph
function M.is_paragraph(text)
    local word_count = M.count_words(text)
    local sentence_count = M.count_sentences(text)

    -- Must have reasonable length and sentence structure
    return word_count >= 10 and sentence_count >= 1 and not text:match("\n\n")
end

---Count lines in text
---@param text string Text to count
---@return number count Number of lines
function M.count_lines(text)
    local _, count = text:gsub("\n", "")
    return count + 1
end

---Count words in text
---@param text string Text to count
---@return number count Number of words
function M.count_words(text)
    local _, count = text:gsub("%S+", "")
    return count
end

---Count sentences in text
---@param text string Text to count
---@return number count Number of sentences
function M.count_sentences(text)
    local _, count = text:gsub("[.!?]+", "")
    return count
end

---Extract title from title section
---@param text string Text containing title
---@return string title Extracted title
function M.extract_title(text)
    local title = text:match("^([A-Z][A-Z%s_]+):%s*")
    return title or "Section"
end

---Detect programming language from code content
---@param text string Code text
---@return string language Detected language
function M.detect_language(text)
    if text:match("function%s*%(") or text:match("local%s+") then
        return "lua"
    elseif text:match('{%s*"') and text:match(":%s*") then
        return "json"
    elseif text:match("def%s+") or text:match("import%s+") then
        return "python"
    elseif text:match("const%s+") or text:match("function%s+") then
        return "javascript"
    end
    return "text"
end

---Extract list items from list content
---@param text string List text
---@return string[] items List items
function M.extract_list_items(text)
    local items = {}
    local lines = vim.split(text, "\n")

    for _, line in ipairs(lines) do
        local trimmed = line:gsub("^%s+", "")
        local item = trimmed:match("^[-*+]%s*(.+)") or trimmed:match("^%d+%.%s*(.+)")
        if item then
            table.insert(items, item)
        end
    end

    return items
end

---Detect list type (bullet or numbered)
---@param text string List text
---@return string type List type
function M.detect_list_type(text)
    if text:match("%d+%.%s") then
        return "numbered"
    else
        return "bullet"
    end
end

---Check if text contains URLs
---@param text string Text to check
---@return boolean has_urls Whether text contains URLs
function M.contains_urls(text)
    return text:match("https?://") ~= nil
end

---Extract URLs from text
---@param text string Text containing URLs
---@return string[] urls Extracted URLs
function M.extract_urls(text)
    local urls = {}
    for url in text:gmatch("(https?://[%w%.%-_/#%%?=&]+)") do
        table.insert(urls, url)
    end
    return urls
end

---Detect error type from error content
---@param text string Error text
---@return string type Error type
function M.detect_error_type(text)
    local lower = text:lower()
    if lower:match("timeout") then
        return "timeout"
    elseif lower:match("permission") or lower:match("access") then
        return "permission"
    elseif lower:match("not found") or lower:match("404") then
        return "not_found"
    elseif lower:match("syntax") then
        return "syntax"
    else
        return "general"
    end
end

---Parse content into semantic segments for tree display
---@param text string Raw text content
---@param parent_id string Parent node ID for unique identification
---@param create_node_fn function Function to create tree nodes
---@return table[] nodes Array of semantic content nodes
function M.parse_content_semantically(text, parent_id, create_node_fn)
    vim.validate({
        text = { text, "string" },
        parent_id = { parent_id, "string" },
        create_node_fn = { create_node_fn, "function" },
    })

    local segments = M.split_into_semantic_segments(text)
    local nodes = {}
    local counter = 0

    for _, segment in ipairs(segments) do
        counter = counter + 1
        local node = M.create_semantic_node(segment, parent_id, counter, create_node_fn)
        if node then
            table.insert(nodes, node)
        end
    end

    return nodes
end

---Split text into semantic segments based on content type
---@param text string Text to split
---@return CcTui.ContentSegment[] segments Array of content segments
function M.split_into_semantic_segments(text)
    -- Handle very short content as single segment
    if #text <= 100 then
        local content_type, metadata = M.detect_content_type(text)
        return {
            {
                type = content_type,
                content = text,
                metadata = metadata,
                collapsible = false,
                preview = M.create_preview(text, content_type, metadata),
            },
        }
    end

    local segments = {}

    -- Try to detect major content boundaries
    if M.contains_multiple_sections(text) then
        segments = M.split_by_sections(text)
    elseif M.is_json_content(text) then
        segments = M.handle_json_content(text)
    elseif M.is_list_content(text) then
        segments = M.handle_list_content(text)
    else
        segments = M.handle_paragraph_content(text)
    end

    return segments
end

---Check if text contains multiple distinct sections
---@param text string Text to check
---@return boolean has_sections Whether text has multiple sections
function M.contains_multiple_sections(text)
    local section_patterns = {
        "TITLE:%s*",
        "DESCRIPTION:%s*",
        "SOURCE:%s*",
        "LANGUAGE:%s*",
        "CODE:%s*",
        "EXAMPLE:%s*",
    }

    local section_count = 0
    for _, pattern in ipairs(section_patterns) do
        if text:match(pattern) then
            section_count = section_count + 1
        end
    end

    return section_count >= 2
end

---Split text by major sections
---@param text string Text to split
---@return CcTui.ContentSegment[] segments Array of content segments
function M.split_by_sections(text)
    local segments = {}
    local section_pattern = "([A-Z][A-Z%s_]+:%s*)"
    local current_pos = 1

    for section_start, section_title in text:gmatch("()" .. section_pattern) do
        -- Add content before this section (if any)
        if section_start > current_pos then
            local before_content = text:sub(current_pos, section_start - 1):gsub("^%s+", ""):gsub("%s+$", "")
            if #before_content > 0 then
                local content_type, metadata = M.detect_content_type(before_content)
                table.insert(segments, {
                    type = content_type,
                    content = before_content,
                    metadata = metadata,
                    collapsible = #before_content > 150,
                    preview = M.create_preview(before_content, content_type, metadata),
                })
            end
        end
        current_pos = section_start
    end

    -- Add remaining content
    if current_pos <= #text then
        local remaining = text:sub(current_pos):gsub("^%s+", ""):gsub("%s+$", "")
        if #remaining > 0 then
            local content_type, metadata = M.detect_content_type(remaining)
            table.insert(segments, {
                type = content_type,
                content = remaining,
                metadata = metadata,
                collapsible = #remaining > 150,
                preview = M.create_preview(remaining, content_type, metadata),
            })
        end
    end

    return segments
end

---Handle JSON content specially
---@param text string JSON text
---@return CcTui.ContentSegment[] segments Array of content segments
function M.handle_json_content(text)
    local content_type, metadata = M.detect_content_type(text)
    local line_count = M.count_lines(text)

    return {
        {
            type = content_type,
            content = text,
            metadata = metadata,
            collapsible = line_count > 5,
            preview = M.create_json_preview(text, line_count),
        },
    }
end

---Handle list content
---@param text string List text
---@return CcTui.ContentSegment[] segments Array of content segments
function M.handle_list_content(text)
    local content_type, metadata = M.detect_content_type(text)
    local item_count = #metadata.items

    return {
        {
            type = content_type,
            content = text,
            metadata = metadata,
            collapsible = item_count > 5,
            preview = M.create_list_preview(metadata.items, item_count, metadata.list_type),
        },
    }
end

---Handle paragraph content
---@param text string Paragraph text
---@return CcTui.ContentSegment[] segments Array of content segments
function M.handle_paragraph_content(text)
    -- Split long paragraphs at sentence boundaries
    if #text <= 200 then
        local content_type, metadata = M.detect_content_type(text)
        return {
            {
                type = content_type,
                content = text,
                metadata = metadata,
                collapsible = false,
                preview = text,
            },
        }
    end

    -- Split at paragraph or sentence boundaries for long content
    local sentences = M.split_into_sentences(text)
    local segments = {}
    local current_chunk = {}
    local current_length = 0

    for _, sentence in ipairs(sentences) do
        if current_length + #sentence > 200 and #current_chunk > 0 then
            -- Create segment from current chunk
            local chunk_text = table.concat(current_chunk, " ")
            local content_type, metadata = M.detect_content_type(chunk_text)
            table.insert(segments, {
                type = content_type,
                content = chunk_text,
                metadata = metadata,
                collapsible = false,
                preview = chunk_text,
            })

            -- Start new chunk
            current_chunk = { sentence }
            current_length = #sentence
        else
            table.insert(current_chunk, sentence)
            current_length = current_length + #sentence + 1 -- +1 for space
        end
    end

    -- Add final chunk
    if #current_chunk > 0 then
        local chunk_text = table.concat(current_chunk, " ")
        local content_type, metadata = M.detect_content_type(chunk_text)
        table.insert(segments, {
            type = content_type,
            content = chunk_text,
            metadata = metadata,
            collapsible = false,
            preview = chunk_text,
        })
    end

    return segments
end

---Split text into sentences
---@param text string Text to split
---@return string[] sentences Array of sentences
function M.split_into_sentences(text)
    -- Simple sentence splitting on periods, exclamation marks, question marks
    local sentences = {}
    local current = ""

    for char in text:gmatch(".") do
        current = current .. char
        if char:match("[.!?]") and not current:match("%d%.%d") then -- Avoid splitting on decimals
            table.insert(sentences, current:gsub("^%s+", ""):gsub("%s+$", ""))
            current = ""
        end
    end

    -- Add remaining text
    if #current > 0 then
        table.insert(sentences, current:gsub("^%s+", ""):gsub("%s+$", ""))
    end

    return sentences
end

---Create preview text for content segment
---@param text string Full text content
---@param content_type CcTui.ContentType Type of content
---@param metadata table Content metadata
---@return string preview Preview text
function M.create_preview(text, content_type, metadata)
    if content_type == M.ContentType.JSON then
        return M.create_json_preview(text, metadata.line_count or M.count_lines(text))
    elseif content_type == M.ContentType.LIST then
        return M.create_list_preview(metadata.items or {}, #(metadata.items or {}), metadata.list_type)
    elseif content_type == M.ContentType.TITLE_SECTION then
        return metadata.title or "Section"
    else
        -- Default preview: first 80 characters
        local preview = text:gsub("[\n\r]", " "):gsub("%s+", " ")
        if #preview > 80 then
            preview = preview:sub(1, 77) .. "..."
        end
        return preview
    end
end

---Create preview for JSON content
---@param text string JSON text
---@param line_count number Number of lines
---@return string preview JSON preview
function M.create_json_preview(text, line_count)
    if line_count <= 5 then
        return text:gsub("[\n\r]", " "):gsub("%s+", " ")
    else
        return string.format("+%d lines (ctrl+r to expand)", line_count)
    end
end

---Create preview for list content
---@param items string[] List items
---@param item_count number Number of items
---@param list_type string Type of list
---@return string preview List preview
function M.create_list_preview(items, item_count, list_type)
    if item_count <= 3 then
        local marker = list_type == "numbered" and "1. " or "- "
        return marker .. (items[1] or "")
    else
        return string.format("List with %d items", item_count)
    end
end

---Create a semantic tree node from content segment
---@param segment CcTui.ContentSegment Content segment
---@param parent_id string Parent node ID
---@param counter number Unique counter
---@param create_node_fn function Function to create nodes
---@return table? node Created tree node or nil
function M.create_semantic_node(segment, parent_id, counter, create_node_fn)
    local display_text = segment.collapsible and segment.preview or segment.content

    -- Ensure display text is reasonable length
    if #display_text > 120 then
        display_text = display_text:sub(1, 117) .. "..."
    end

    local node = create_node_fn(display_text, parent_id, counter)

    -- Add metadata for semantic understanding
    node.semantic_type = segment.type
    node.semantic_metadata = segment.metadata
    node.collapsible = segment.collapsible
    node.full_content = segment.content

    return node
end

return M
