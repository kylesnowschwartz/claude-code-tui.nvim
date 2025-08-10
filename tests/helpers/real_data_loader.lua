---@brief [[
--- Test helper for loading real Claude Code JSONL conversation files
--- Provides utilities for integration testing with actual conversation data
---@brief ]]

local M = {}

--- Base path to real conversation test data
local REAL_DATA_PATH = vim.fn.expand("~/Code/cc-tui.nvim/docs/test/projects/-Users-kyle-Code-cc-tui-nvim")

---Get list of available real conversation files
---@return string[] files List of available JSONL file paths
function M.get_available_conversations()
    local conversations = {}
    local handle = vim.uv.fs_scandir(REAL_DATA_PATH)

    if handle then
        local name, type
        repeat
            name, type = vim.uv.fs_scandir_next(handle)
            if name and type == "file" and name:match("%.jsonl$") then
                table.insert(conversations, vim.fs.joinpath(REAL_DATA_PATH, name))
            end
        until not name
    end

    table.sort(conversations)
    return conversations
end

---Load a specific real conversation file by UUID
---@param uuid string Conversation UUID (without .jsonl extension)
---@return string[] lines Array of JSONL lines
---@return string? error Error message if loading failed
function M.load_conversation_by_uuid(uuid)
    local filepath = vim.fs.joinpath(REAL_DATA_PATH, uuid .. ".jsonl")

    local file = io.open(filepath, "r")
    if not file then
        return {}, "Failed to open conversation file: " .. filepath
    end

    local lines = {}
    for line in file:lines() do
        table.insert(lines, line)
    end
    file:close()

    return lines, nil
end

---Load the smallest available conversation (for fast tests)
---@return string[] lines Array of JSONL lines
---@return string? error Error message if loading failed
---@return string? uuid UUID of loaded conversation
function M.load_small_conversation()
    local conversations = M.get_available_conversations()
    local smallest_file = nil
    local smallest_size = math.huge

    for _, filepath in ipairs(conversations) do
        local stat = vim.uv.fs_stat(filepath)
        if stat and stat.size < smallest_size then
            smallest_size = stat.size
            smallest_file = filepath
        end
    end

    if not smallest_file then
        return {}, "No conversation files found", nil
    end

    local file = io.open(smallest_file, "r")
    if not file then
        return {}, "Failed to open file: " .. smallest_file, nil
    end

    local lines = {}
    for line in file:lines() do
        table.insert(lines, line)
    end
    file:close()

    local uuid = vim.fs.basename(smallest_file):gsub("%.jsonl$", "")
    return lines, nil, uuid
end

---Load a medium-sized conversation (good for comprehensive tests)
---@return string[] lines Array of JSONL lines
---@return string? error Error message if loading failed
---@return string? uuid UUID of loaded conversation
function M.load_medium_conversation()
    local conversations = M.get_available_conversations()
    local target_size = nil
    local best_file = nil

    -- Look for conversations between 20-100 lines
    for _, filepath in ipairs(conversations) do
        local line_count = 0
        local file = io.open(filepath, "r")
        if file then
            for _ in file:lines() do
                line_count = line_count + 1
            end
            file:close()

            if line_count >= 20 and line_count <= 100 and (not target_size or line_count < target_size) then
                target_size = line_count
                best_file = filepath
            end
        end
    end

    if not best_file then
        -- Fallback to any available conversation
        best_file = conversations[1]
    end

    if not best_file then
        return {}, "No conversation files found", nil
    end

    local file = io.open(best_file, "r")
    if not file then
        return {}, "Failed to open file: " .. best_file, nil
    end

    local lines = {}
    for line in file:lines() do
        table.insert(lines, line)
    end
    file:close()

    local uuid = vim.fs.basename(best_file):gsub("%.jsonl$", "")
    return lines, nil, uuid
end

---Load a large conversation (for stress testing)
---@return string[] lines Array of JSONL lines
---@return string? error Error message if loading failed
---@return string? uuid UUID of loaded conversation
function M.load_large_conversation()
    local conversations = M.get_available_conversations()
    local largest_file = nil
    local largest_size = 0

    for _, filepath in ipairs(conversations) do
        local stat = vim.uv.fs_stat(filepath)
        if stat and stat.size > largest_size then
            largest_size = stat.size
            largest_file = filepath
        end
    end

    if not largest_file then
        return {}, "No conversation files found", nil
    end

    local file = io.open(largest_file, "r")
    if not file then
        return {}, "Failed to open file: " .. largest_file, nil
    end

    local lines = {}
    for line in file:lines() do
        table.insert(lines, line)
    end
    file:close()

    local uuid = vim.fs.basename(largest_file):gsub("%.jsonl$", "")
    return lines, nil, uuid
end

---Get conversation metadata without loading full content
---@param uuid? string Optional specific UUID to check
---@return table[] metadata Array of conversation metadata
function M.get_conversation_metadata(uuid)
    local conversations = M.get_available_conversations()
    local metadata = {}

    for _, filepath in ipairs(conversations) do
        local file_uuid = vim.fs.basename(filepath):gsub("%.jsonl$", "")

        if not uuid or uuid == file_uuid then
            local stat = vim.uv.fs_stat(filepath)
            local line_count = 0

            -- Count lines efficiently
            local file = io.open(filepath, "r")
            if file then
                for _ in file:lines() do
                    line_count = line_count + 1
                end
                file:close()
            end

            table.insert(metadata, {
                uuid = file_uuid,
                filepath = filepath,
                size_bytes = stat and stat.size or 0,
                line_count = line_count,
                category = M.categorize_by_size(line_count),
            })
        end
    end

    return metadata
end

---Categorize conversation by size for test selection (enhanced for TDD test plan)
---@param line_count number Number of lines in conversation
---@return string category Size category
function M.categorize_by_size(line_count)
    -- Enhanced categorization based on TEST_REFACTORING_PLAN.md
    if line_count < 5 then
        return "tiny" -- Fast unit tests, basic functionality validation
    elseif line_count < 25 then
        return "small" -- Standard integration tests, typical conversation handling
    elseif line_count < 100 then
        return "medium" -- Comprehensive feature testing, realistic usage scenarios
    elseif line_count < 300 then
        return "large" -- Stress testing, performance validation
    else
        return "huge" -- Memory management, performance edge cases
    end
end

---Create a test provider using real conversation data
---@param conversation_type? string "small", "medium", "large", or specific UUID
---@return function provider_factory Function that creates StaticProvider with real data
function M.create_real_data_provider(conversation_type)
    conversation_type = conversation_type or "small"

    return function()
        local lines, err, uuid

        if conversation_type == "small" then
            lines, err, uuid = M.load_small_conversation()
        elseif conversation_type == "medium" then
            lines, err, uuid = M.load_medium_conversation()
        elseif conversation_type == "large" then
            lines, err, uuid = M.load_large_conversation()
        else
            -- Assume it's a specific UUID
            lines, err = M.load_conversation_by_uuid(conversation_type)
            uuid = conversation_type
        end

        if err then
            error("Failed to load real conversation data: " .. err)
        end

        local StaticProvider = require("cc-tui.providers.static")
        local provider = StaticProvider:new({
            lines = lines,
            uuid = uuid,
        })

        return provider
    end
end

---Validate that real data directory exists and has conversations
---@return boolean valid True if real data is available
---@return string? error Error message if validation failed
function M.validate_real_data_available()
    local stat = vim.uv.fs_stat(REAL_DATA_PATH)
    if not stat or stat.type ~= "directory" then
        return false, "Real data directory not found: " .. REAL_DATA_PATH
    end

    local conversations = M.get_available_conversations()
    if #conversations == 0 then
        return false, "No JSONL conversation files found in: " .. REAL_DATA_PATH
    end

    return true, nil
end

-- TDD-FRIENDLY ENHANCEMENTS FOR TEST REFACTORING PLAN

---Get conversations by category for targeted testing
---@param category string "tiny", "small", "medium", "large", "huge"
---@return table[] conversations Array of conversation metadata in specified category
function M.get_conversations_by_category(category)
    local all_metadata = M.get_conversation_metadata()
    local filtered = {}

    for _, metadata in ipairs(all_metadata) do
        if metadata.category == category then
            table.insert(filtered, metadata)
        end
    end

    -- Sort by size within category (smallest first for deterministic tests)
    table.sort(filtered, function(a, b)
        return a.line_count < b.line_count
    end)

    return filtered
end

---Load conversation by category (gets first available in category)
---@param category string "tiny", "small", "medium", "large", "huge"
---@return string[] lines Array of JSONL lines
---@return string? error Error message if loading failed
---@return string? uuid UUID of loaded conversation
---@return table? metadata Conversation metadata
function M.load_conversation_by_category(category)
    local conversations = M.get_conversations_by_category(category)

    if #conversations == 0 then
        return {}, "No conversations found in category: " .. category, nil, nil
    end

    local metadata = conversations[1] -- Get smallest in category for consistent tests
    local lines, err = M.load_conversation_by_uuid(metadata.uuid)

    return lines, err, metadata.uuid, metadata
end

---Get comprehensive test data overview for planning
---@return table overview Test data overview with categories and counts
function M.get_test_data_overview()
    local all_metadata = M.get_conversation_metadata()
    local overview = {
        total_conversations = #all_metadata,
        categories = {
            tiny = {},
            small = {},
            medium = {},
            large = {},
            huge = {},
        },
        size_range = {
            smallest_lines = math.huge,
            largest_lines = 0,
            smallest_bytes = math.huge,
            largest_bytes = 0,
        },
    }

    -- Categorize and collect stats
    for _, metadata in ipairs(all_metadata) do
        local category = metadata.category
        table.insert(overview.categories[category], metadata)

        -- Update size range
        overview.size_range.smallest_lines = math.min(overview.size_range.smallest_lines, metadata.line_count)
        overview.size_range.largest_lines = math.max(overview.size_range.largest_lines, metadata.line_count)
        overview.size_range.smallest_bytes = math.min(overview.size_range.smallest_bytes, metadata.size_bytes)
        overview.size_range.largest_bytes = math.max(overview.size_range.largest_bytes, metadata.size_bytes)
    end

    -- Add category counts
    for category, conversations in pairs(overview.categories) do
        overview.categories[category] = {
            count = #conversations,
            conversations = conversations,
        }
    end

    return overview
end

---Create TDD test provider factory with category selection
---@param category string "tiny", "small", "medium", "large", "huge"
---@return function provider_factory Function that creates StaticProvider with categorized real data
function M.create_categorized_provider(category)
    return function()
        local lines, err, uuid, metadata = M.load_conversation_by_category(category)

        if err then
            error("Failed to load " .. category .. " conversation data: " .. err)
        end

        local StaticProvider = require("cc-tui.providers.static")
        local provider = StaticProvider:new({
            lines = lines,
            uuid = uuid,
            metadata = metadata,
        })

        return provider, metadata
    end
end

return M
