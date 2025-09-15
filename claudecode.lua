-- claudecode.lua
-- Neovim integration for Claude Code with interactive context selection

local M = {}

-- Configuration
M.config = {
    claude_cmd = "claude-code",  -- Adjust if claude-code is in a different path
    window = {
        width = 0.8,
        height = 0.8,
        border = "rounded",
        title = " Claude Code Response ",
    },
    temp_file_extension = ".py", -- Default extension for temp files
}

-- Get visual selection text
local function get_visual_selection()
    -- Save current register
    local save_reg = vim.fn.getreg('"')
    local save_regtype = vim.fn.getregtype('"')
    
    -- Yank selection to unnamed register
    vim.cmd('normal! gv"zy')
    local selection = vim.fn.getreg('"')
    
    -- Restore register
    vim.fn.setreg('"', save_reg, save_regtype)
    
    return selection
end

-- Get current function context using treesitter
local function get_current_function()
    local ts_utils = require('nvim-treesitter.ts_utils')
    local current_node = ts_utils.get_node_at_cursor()
    
    if not current_node then
        return nil
    end
    
    -- Walk up the tree to find function node
    local function_node = current_node
    while function_node do
        local node_type = function_node:type()
        if node_type:match("function") or node_type:match("method") or node_type:match("def") then
            break
        end
        function_node = function_node:parent()
    end
    
    if not function_node then
        return nil
    end
    
    -- Get function text
    local start_row, start_col, end_row, end_col = function_node:range()
    local lines = vim.api.nvim_buf_get_lines(0, start_row, end_row + 1, false)
    
    -- Adjust first and last line for column positions
    if #lines > 0 then
        lines[1] = string.sub(lines[1], start_col + 1)
        if #lines > 1 then
            lines[#lines] = string.sub(lines[#lines], 1, end_col)
        end
    end
    
    return table.concat(lines, '\n')
end

-- Fallback function detection for when treesitter isn't available
local function get_current_function_fallback()
    local cursor_line = vim.api.nvim_win_get_cursor(0)[1]
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    
    -- Find function start (looking backwards)
    local function_start = cursor_line
    for i = cursor_line, 1, -1 do
        local line = lines[i]
        if line and line:match("^%s*def%s+") or line:match("^%s*function%s+") or line:match("^%s*func%s+") then
            function_start = i
            break
        end
    end
    
    -- Find function end (looking forwards)
    local function_end = cursor_line
    local indent_level = nil
    for i = function_start + 1, #lines do
        local line = lines[i]
        if line and line:trim() ~= "" then
            local current_indent = line:match("^%s*")
            if indent_level == nil then
                indent_level = #current_indent
            elseif #current_indent <= indent_level and line:match("^%s*[%w]") then
                function_end = i - 1
                break
            end
        end
        function_end = i
    end
    
    return table.concat(vim.list_slice(lines, function_start, function_end), '\n')
end

-- Get appropriate file extension based on current buffer
local function get_file_extension()
    if not M.config.auto_detect_filetype then
        return M.config.temp_file_extension
    end
    
    -- Get current buffer's filetype
    local filetype = vim.bo.filetype
    
    -- Map common filetypes to extensions
    local extension_map = {
        python = ".py",
        javascript = ".js",
        typescript = ".ts",
        lua = ".lua",
        go = ".go",
        rust = ".rs",
        java = ".java",
        cpp = ".cpp",
        c = ".c",
        sh = ".sh",
        bash = ".sh",
        zsh = ".sh",
        fish = ".fish",
        sql = ".sql",
        html = ".html",
        css = ".css",
        json = ".json",
        yaml = ".yaml",
        yml = ".yml",
        xml = ".xml",
        markdown = ".md",
        vim = ".vim",
        php = ".php",
        ruby = ".rb",
        perl = ".pl",
        r = ".r",
        matlab = ".m",
        scala = ".scala",
        kotlin = ".kt",
        swift = ".swift",
        dart = ".dart",
        elixir = ".ex",
        erlang = ".erl",
        haskell = ".hs",
        clojure = ".clj",
        scheme = ".scm",
        terraform = ".tf",
        dockerfile = ".dockerfile",
        makefile = ".mk",
    }
    
    -- Return mapped extension or fallback
    return extension_map[filetype] or M.config.temp_file_extension
end

-- Create temporary file with content
local function create_temp_file(content, extension)
    local ext = extension or get_file_extension()
    local temp_file = vim.fn.tempname() .. ext
    local file = io.open(temp_file, 'w')
    if not file then
        vim.notify("Failed to create temporary file", vim.log.levels.ERROR)
        return nil
    end
    file:write(content)
    file:close()
    return temp_file
end

-- Display result in floating window
local function show_result(result, title)
    local buf = vim.api.nvim_create_buf(false, true)
    
    -- Set buffer options
    vim.api.nvim_buf_set_option(buf, 'buftype', 'nofile')
    vim.api.nvim_buf_set_option(buf, 'swapfile', false)
    vim.api.nvim_buf_set_option(buf, 'filetype', 'markdown')
    vim.api.nvim_buf_set_option(buf, 'bufhidden', 'wipe')
    
    -- Set content
    local lines = vim.split(result, '\n')
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    
    -- Calculate window size
    local width = math.floor(vim.o.columns * M.config.window.width)
    local height = math.floor(vim.o.lines * M.config.window.height)
    local row = math.floor((vim.o.lines - height) / 2)
    local col = math.floor((vim.o.columns - width) / 2)
    
    -- Create window
    local win = vim.api.nvim_open_win(buf, true, {
        relative = 'editor',
        width = width,
        height = height,
        row = row,
        col = col,
        border = M.config.window.border,
        title = title or M.config.window.title,
        title_pos = 'center',
    })
    
    -- Set window options
    vim.api.nvim_win_set_option(win, 'wrap', true)
    vim.api.nvim_win_set_option(win, 'linebreak', true)
    
    -- Set keymaps for the buffer
    local opts = { noremap = true, silent = true, buffer = buf }
    vim.keymap.set('n', 'q', '<cmd>close<cr>', opts)
    vim.keymap.set('n', '<Esc>', '<cmd>close<cr>', opts)
    
    return buf, win
end

-- Execute Claude Code command
local function execute_claude_code(prompt, file_path, context_description)
    local cmd
    if file_path and file_path ~= vim.api.nvim_buf_get_name(0) then
        -- For temporary files, read the content and pass it directly in the prompt
        local file = io.open(file_path, 'r')
        if not file then
            vim.notify("Failed to read temporary file", vim.log.levels.ERROR)
            return
        end
        local content = file:read("*all")
        file:close()
        
        -- Pass content directly in the prompt using print mode
        cmd = string.format('%s -p "%s\n\nHere is the code:\n```\n%s\n```"', 
              M.config.claude_cmd, prompt:gsub('"', '\\"'), content:gsub('"', '\\"'))
    else
        -- For current file, Claude Code can access it directly from the working directory
        cmd = string.format('%s -p "%s"', M.config.claude_cmd, prompt:gsub('"', '\\"'))
    end
    
    -- Show loading message
    vim.notify("Claude Code is thinking...", vim.log.levels.INFO)
    
    -- Execute command
    local handle = io.popen(cmd .. " 2>&1")  -- Capture stderr too
    if not handle then
        vim.notify("Failed to execute Claude Code", vim.log.levels.ERROR)
        return
    end
    
    local result = handle:read("*a")
    local success = handle:close()
    
    if not success then
        vim.notify("Claude Code command failed:\n" .. result, vim.log.levels.ERROR)
        return
    end
    
    if result == "" then
        vim.notify("Claude Code returned no output", vim.log.levels.WARN)
        return
    end
    
    -- Show result
    local title = string.format(" Claude Code: %s ", context_description or "Analysis")
    show_result(result, title)
end

-- Main function to handle context selection and prompt
function M.interactive_claude_code()
    local mode = vim.api.nvim_get_mode().mode
    local options = {
        'Selected Code',
        'Current Function', 
        'Entire File',
        'Custom Range'
    }
    
    -- Filter options based on current mode
    if not mode:match('^[vV]') then
        -- Remove 'Selected Code' if not in visual mode
        options = vim.tbl_filter(function(opt) return opt ~= 'Selected Code' end, options)
    end
    
    vim.ui.select(options, {
        prompt = 'What should Claude analyze?',
        format_item = function(item)
            return "  " .. item
        end,
    }, function(choice)
        if not choice then return end
        
        -- Get the prompt from user
        local prompt = vim.fn.input("Claude Code: ")
        if prompt == "" then return end
        
        local context_prompt = prompt
        local target_file = vim.api.nvim_buf_get_name(0)
        local context_description = choice
        local temp_file = nil
        
        if choice == 'Selected Code' then
            local selection = get_visual_selection()
            if selection == "" then
                vim.notify("No text selected", vim.log.levels.WARN)
                return
            end
            
            temp_file = create_temp_file(selection)
            if not temp_file then return end
            
            target_file = temp_file
            context_prompt = prompt .. "\n\nAnalyze this code snippet:"
            context_description = "Selected Code"
            
        elseif choice == 'Current Function' then
            local function_code = get_current_function()
            if not function_code then
                function_code = get_current_function_fallback()
            end
            
            if not function_code or function_code == "" then
                vim.notify("Could not detect current function", vim.log.levels.WARN)
                return
            end
            
            temp_file = create_temp_file(function_code)
            if not temp_file then return end
            
            target_file = temp_file
            context_prompt = prompt .. "\n\nAnalyze this function:"
            context_description = "Current Function"
            
        elseif choice == 'Entire File' then
            if target_file == "" then
                vim.notify("Buffer has no associated file", vim.log.levels.WARN)
                return
            end
            context_prompt = prompt .. "\n\nAnalyze this entire file:"
            context_description = "Entire File"
            
        elseif choice == 'Custom Range' then
            local start_line = vim.fn.input("Start line: ")
            local end_line = vim.fn.input("End line: ")
            
            start_line = tonumber(start_line)
            end_line = tonumber(end_line)
            
            if not start_line or not end_line or start_line < 1 or end_line < start_line then
                vim.notify("Invalid line range", vim.log.levels.WARN)
                return
            end
            
            local lines = vim.api.nvim_buf_get_lines(0, start_line - 1, end_line, false)
            local range_content = table.concat(lines, '\n')
            
            temp_file = create_temp_file(range_content)
            if not temp_file then return end
            
            target_file = temp_file
            context_prompt = prompt .. string.format("\n\nAnalyze lines %d-%d:", start_line, end_line)
            context_description = string.format("Lines %d-%d", start_line, end_line)
        end
        
        -- Execute Claude Code
        execute_claude_code(context_prompt, target_file, context_description)
        
        -- Cleanup temporary file
        if temp_file then
            vim.defer_fn(function()
                os.remove(temp_file)
            end, 1000) -- Clean up after 1 second
        end
    end)
end

-- Generate tests for current file
function M.generate_tests()
    local current_file = vim.api.nvim_buf_get_name(0)
    local filetype = vim.bo.filetype
    
    -- Check if current file exists and is saved
    if current_file == "" then
        vim.notify("Please save the current buffer to a file first", vim.log.levels.WARN)
        return
    end
    
    -- Check if buffer has unsaved changes
    if vim.bo.modified then
        vim.notify("Please save your changes first", vim.log.levels.WARN)
        return
    end
    
    -- Determine test file naming convention and framework based on filetype
    local test_info = {}
    if filetype == "python" then
        test_info = {
            framework = "pytest",
            test_file_pattern = "test_*.py or *_test.py",
            imports = "import pytest\nfrom unittest.mock import Mock, patch\n"
        }
    elseif filetype == "go" then
        test_info = {
            framework = "Go testing package",
            test_file_pattern = "*_test.go",
            imports = "import (\n\t\"testing\"\n)"
        }
    elseif filetype == "javascript" or filetype == "typescript" then
        test_info = {
            framework = "Jest",
            test_file_pattern = "*.test.js or *.spec.js",
            imports = "// Jest framework"
        }
    else
        test_info = {
            framework = "standard testing framework",
            test_file_pattern = "test files",
            imports = ""
        }
    end
    
    -- Build comprehensive prompt for test generation
    local test_prompt = string.format(
        "Generate comprehensive unit tests for this %s file using %s.\n\n" ..
        "Requirements:\n" ..
        "- Test all public functions, methods, and classes\n" ..
        "- Include edge cases, error conditions, and boundary testing\n" ..
        "- Use proper mocking for dependencies and external calls\n" ..
        "- Follow %s best practices and conventions\n" ..
        "- Use descriptive test names that explain what is being tested\n" ..
        "- Group related tests logically\n" ..
        "- Include setup/teardown where appropriate\n\n" ..
        "The tests should be ready to run in a %s file following %s naming convention.\n" ..
        "Provide complete, runnable test code with all necessary imports.",
        filetype, test_info.framework, filetype, filetype, test_info.test_file_pattern
    )
    
    -- Show loading message
    vim.notify("Claude Code is generating comprehensive tests...", vim.log.levels.INFO)
    
    -- Execute Claude Code in the current directory
    local cmd = string.format('cd "%s" && %s -p "%s"', 
                              vim.fn.fnamemodify(current_file, ":h"),
                              M.config.claude_cmd, 
                              test_prompt:gsub('"', '\\"'))
    
    local handle = io.popen(cmd .. " 2>&1")
    if not handle then
        vim.notify("Failed to execute Claude Code", vim.log.levels.ERROR)
        return
    end
    
    local result = handle:read("*all")
    local success = handle:close()
    
    if not success then
        vim.notify("Claude Code command failed:\n" .. result, vim.log.levels.ERROR)
        return
    end
    
    if result == "" then
        vim.notify("Claude Code returned no output", vim.log.levels.WARN)
        return
    end
    
    -- Extract code blocks from the response
    local code_blocks = extract_code_blocks(result)
    
    if #code_blocks > 0 then
        -- For tests, we want to create a new file rather than insert into current file
        show_test_creation_dialog(code_blocks, current_file, test_info, result)
    else
        -- Fallback: show the full response
        show_result(result, " Claude Code: Test Generation ")
    end
end

-- Quick commands for common operations
function M.explain_selection()
    local mode = vim.api.nvim_get_mode().mode
    if not mode:match('^[vV]') then
        vim.notify("No text selected", vim.log.levels.WARN)
        return
    end
    
    local selection = get_visual_selection()
    if selection == "" then
        vim.notify("No text selected", vim.log.levels.WARN)
        return
    end
    
    local temp_file = create_temp_file(selection)
    if not temp_file then return end
    
    execute_claude_code("Explain what this code does and how it works", temp_file, "Code Explanation")
    
    vim.defer_fn(function()
        os.remove(temp_file)
    end, 1000)
end

function M.explain_function()
    local function_code = get_current_function()
    if not function_code then
        function_code = get_current_function_fallback()
    end
    
    if not function_code or function_code == "" then
        vim.notify("Could not detect current function", vim.log.levels.WARN)
        return
    end
    
    local temp_file = create_temp_file(function_code)
    if not temp_file then return end
    
    execute_claude_code("Explain what this function does and how it works", temp_file, "Function Explanation")
    
    vim.defer_fn(function()
        os.remove(temp_file)
    end, 1000)
end

-- Setup function
function M.setup(opts)
    opts = opts or {}
    M.config = vim.tbl_deep_extend("force", M.config, opts)
    
    -- Set up keymaps
    vim.keymap.set({'n', 'v'}, '<leader>cc', M.interactive_claude_code, { desc = "Claude Code with context" })
    vim.keymap.set('v', '<leader>ce', M.explain_selection, { desc = "Claude Code explain selection" })
    vim.keymap.set('n', '<leader>cf', M.explain_function, { desc = "Claude Code explain function" })
    vim.keymap.set('n', '<leader>cg', M.generate_function, { desc = "Claude Code generate function" })
    vim.keymap.set('n', '<leader>ct', M.generate_tests, { desc = "Claude Code generate tests" })
    vim.keymap.set({'n', 'v'}, '<leader>cd', M.generate_docs, { desc = "Claude Code generate documentation" })
    
    -- Create user commands
    vim.api.nvim_create_user_command('ClaudeCode', M.interactive_claude_code, {})
    vim.api.nvim_create_user_command('ClaudeExplain', M.explain_function, {})
    vim.api.nvim_create_user_command('ClaudeGenerate', M.generate_function, {})
    vim.api.nvim_create_user_command('ClaudeTest', M.generate_tests, {})
    vim.api.nvim_create_user_command('ClaudeDocs', M.generate_docs, {})
end

return M
