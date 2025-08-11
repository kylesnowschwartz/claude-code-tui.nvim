globals = { "vim", "MiniTest" }
max_line_length = false

exclude_files = { "deps" }

-- Global ignore for unused self parameter since CLAUDE.md mandates colon syntax
-- "Always use colon syntax: state:method() not state.method()"
ignore = { "212/self" }

-- File-specific ignores for other unused arguments
files["lua/cc-tui/ui/views/current.lua"] = {
    ignore = { "212/session_info" } -- unused argument in callback
}

files["lua/cc-tui/utils/content_classifier.lua"] = {
    ignore = { "212/confidence", "212/structured_data" } -- unused arguments in compatibility methods
}

files["lua/cc-tui/utils/content_classifier_core.lua"] = {
    ignore = { "212/tool_name", "212/context" } -- unused arguments in delegate method
}
