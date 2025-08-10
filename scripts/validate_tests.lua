-- Test validation script for Neovim environment
-- This runs inside Neovim where MiniTest and vim globals are available
---@brief [[
--- Test Validation Script - Fail Fast for MiniTest Errors
--- Validates all test files can be loaded and return proper MiniTest sets
--- Catches structural issues before running expensive test suite
---@brief ]]

local function validate_test_file(filepath)
    local success, result = pcall(dofile, filepath)

    if not success then
        return false, "Failed to load: " .. tostring(result)
    end

    -- Check if it returns a table (MiniTest set)
    if type(result) ~= "table" then
        return false, "Must return MiniTest.new_set() table, got: " .. type(result)
    end

    -- Check if it has the expected MiniTest structure
    -- MiniTest sets can have hooks OR direct test cases OR nested test sets
    local has_structure = false

    if result.hooks then
        has_structure = true
    end

    -- Check for numeric indices (test cases)
    for key, _ in pairs(result) do
        if type(key) == "number" or type(key) == "string" then
            has_structure = true
            break
        end
    end

    if not has_structure then
        return false, "Doesn't appear to be a valid MiniTest set (no hooks or test cases found)"
    end

    return true, "Valid MiniTest structure"
end

local function scan_test_directory(test_dir)
    -- Use vim.fn.glob instead of shell command for cross-platform compatibility
    local pattern = test_dir .. "/test_*.lua"
    local files_string = vim.fn.glob(pattern, false, true)

    if type(files_string) == "table" then
        return files_string
    elseif type(files_string) == "string" and files_string ~= "" then
        return vim.split(files_string, "\n")
    else
        return {}
    end
end

local function main()
    print("🔍 Fast Test Validation - Checking MiniTest Structure")
    print("=" .. string.rep("=", 50))

    local test_dir = "tests"
    local test_files = scan_test_directory(test_dir)

    if #test_files == 0 then
        print("⚠️  No test files found in " .. test_dir)
        os.exit(0)
    end

    local total_files = #test_files
    local valid_files = 0
    local invalid_files = {}

    for _, filepath in ipairs(test_files) do
        local filename = filepath:match("([^/]+)$")

        -- Skip helper files and directories
        if not filename:match("^test_") or filename:match("helpers") then
            goto continue
        end

        local is_valid, message = validate_test_file(filepath)

        if is_valid then
            print("✅ " .. filename .. " - " .. message)
            valid_files = valid_files + 1
        else
            print("❌ " .. filename .. " - " .. message)
            table.insert(invalid_files, {
                file = filename,
                path = filepath,
                error = message
            })
        end

        ::continue::
    end

    print("\n" .. string.rep("=", 60))
    print(string.format("📊 Validation Summary: %d/%d files valid", valid_files, total_files))

    if #invalid_files > 0 then
        print("\n❌ VALIDATION FAILED - Fix these issues before running tests:")
        print(string.rep("-", 60))

        for _, file_info in ipairs(invalid_files) do
            print("🔧 " .. file_info.file .. ":")
            print("   Error: " .. file_info.error)
            print("   Path: " .. file_info.path)
            print("")
        end

        print("💡 Common fixes:")
        print("   • Add 'return T' at the end of test files")
        print("   • Ensure T = MiniTest.new_set() is used")
        print("   • Check for syntax errors in test file")

        return false
    else
        print("✅ All test files have valid MiniTest structure!")
        print("🚀 Safe to run 'make test'")
        return true
    end
end

-- Return the validation result for use in Neovim
return main()
