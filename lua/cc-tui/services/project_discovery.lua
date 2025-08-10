---@brief [[
--- Project Discovery Service for Claude CLI conversation browsing (REFACTORED)
--- Delegates to focused modules: ClaudePathMapper, ConversationRepository, MetadataExtractor, ConversationFormatter
--- Maintains backward compatibility for existing API consumers
---@brief ]]

local ClaudePathMapper = require("cc-tui.services.claude_path_mapper")
local ConversationFormatter = require("cc-tui.ui.conversation_formatter")
local ConversationRepository = require("cc-tui.services.conversation_repository")
local MetadataExtractor = require("cc-tui.services.metadata_extractor")

---@class CcTui.Services.ProjectDiscovery
local M = {}

-- BACKWARD COMPATIBILITY API - Delegate to focused modules

---Clear metadata cache for a specific file or all files
---@param file_path? string Optional file path to clear, or nil to clear all
function M.clear_metadata_cache(file_path)
    return MetadataExtractor.clear_cache(file_path)
end

---Get the normalized project name from a directory path (matching Claude CLI convention)
---@param cwd string Current working directory path
---@return string project_name Project name matching Claude CLI's naming convention
function M.get_project_name(cwd)
    return ClaudePathMapper.get_project_name(cwd)
end

---Get the full path to a Claude project directory
---@param project_name string The project name
---@return string project_path Full path to project directory
function M.get_project_path(project_name)
    return ClaudePathMapper.get_project_path(project_name)
end

---Check if a Claude project exists
---@param project_name string The project name to check
---@return boolean exists Whether the project directory exists
function M.project_exists(project_name)
    return ClaudePathMapper.project_exists(project_name)
end

---List all available Claude projects
---@return string[] projects List of project names
function M.list_all_projects()
    return ClaudePathMapper.list_all_projects()
end

---@class CcTui.ConversationMetadata
---@field filename string The JSONL filename
---@field path string Full path to the conversation file
---@field timestamp string ISO timestamp from JSON content
---@field size number File size in bytes
---@field modified number Last modified time (Unix timestamp)
---@field title? string Extracted conversation title (from first user message)
---@field message_count? number Number of messages in conversation

---List all conversation files in a project
---@param project_name string The project name
---@return CcTui.ConversationMetadata[] conversations List of conversation metadata
function M.list_conversations(project_name)
    return ConversationRepository.list_conversations(project_name)
end

---Extract metadata from conversation file (title, message count, timestamp) - ASYNC
---@param conversation_path string Path to conversation JSONL file
---@param callback function Callback(title, message_count, timestamp)
function M.extract_conversation_metadata_async(conversation_path, callback)
    return MetadataExtractor.extract_async(conversation_path, callback)
end

---Extract metadata from conversation file (title, message count, timestamp) - SYNC
---@param conversation_path string Path to conversation JSONL file
---@return string? title First user message as title
---@return number message_count Total number of messages
---@return string? timestamp ISO timestamp from first message
function M.extract_conversation_metadata_sync(conversation_path)
    return MetadataExtractor.extract_sync(conversation_path)
end

---Get conversation metadata with lazy-loaded details - ASYNC
---@param conversation CcTui.ConversationMetadata Base conversation metadata
---@param callback function Callback(enriched_conversation)
function M.enrich_conversation_metadata_async(conversation, callback)
    return ConversationRepository.enrich_metadata_async(conversation, callback)
end

---Get conversation metadata with lazy-loaded details - SYNC
---@param conversation CcTui.ConversationMetadata Base conversation metadata
---@return CcTui.ConversationMetadata enriched Enriched with title, message count, and timestamp
function M.enrich_conversation_metadata_sync(conversation)
    return ConversationRepository.enrich_metadata_sync(conversation)
end

---Sort conversations by timestamp (most recent first)
---@param conversations CcTui.ConversationMetadata[] List of conversation metadata
---@return CcTui.ConversationMetadata[] sorted Sorted conversations
function M.sort_conversations_by_timestamp(conversations)
    return ConversationRepository.sort_by_timestamp(conversations)
end

---Find the most recent conversation in a project
---@param project_name string The project name
---@return CcTui.ConversationMetadata? conversation Most recent conversation or nil
function M.get_most_recent_conversation(project_name)
    return ConversationRepository.get_most_recent(project_name)
end

---Format conversation metadata for display
---@param conversation CcTui.ConversationMetadata Conversation metadata
---@return string display_text Formatted display text for tab/list
function M.format_conversation_display(conversation)
    return ConversationFormatter.format_display(conversation)
end

return M
