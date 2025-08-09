globals = { "vim", "MiniTest" }
max_line_length = false

exclude_files = { "deps" }

-- Ignore unused self parameter in abstract methods
files["lua/cc-tui/providers/base.lua"] = {
    ignore = { "212/self" } -- unused argument
}

files["lua/cc-tui/providers/static.lua"] = {
    ignore = { "212/self" } -- unused argument
}
