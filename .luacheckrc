globals = { "vim", "MiniTest" }
max_line_length = false

exclude_files = { "deps" }

-- Ignore unused self parameter in abstract methods and utility functions
files["lua/cc-tui/providers/base.lua"] = {
    ignore = { "212/self" } -- unused argument
}

files["lua/cc-tui/providers/static.lua"] = {
    ignore = { "212/self" } -- unused argument
}

files["lua/cc-tui/ui/tabbed_manager.lua"] = {
    ignore = { "212/self" } -- unused argument
}

files["lua/cc-tui/ui/views/base.lua"] = {
    ignore = { "212/self" } -- unused argument for utility methods
}

files["lua/cc-tui/ui/views/current.lua"] = {
    ignore = { "212/session_info" } -- unused argument in callback
}

files["lua/cc-tui/ui/views/help.lua"] = {
    ignore = { "212/self" } -- unused argument in refresh method
}

files["lua/cc-tui/ui/views/logs.lua"] = {
    ignore = { "212/self" } -- unused argument in setup_keymaps
}

files["lua/cc-tui/utils/content_classifier.lua"] = {
    ignore = { "212/confidence", "212/structured_data" } -- unused arguments in compatibility methods
}

files["lua/cc-tui/utils/content_classifier_core.lua"] = {
    ignore = { "212/tool_name", "212/context" } -- unused arguments in delegate method
}
