local M = {}
local commands = require("dbt.commands")

local function dbt_tagfunc(pattern, flags, info)
	local tags = {}

	-- Search for model files
	local model_result = vim.fn.findfile(pattern .. ".sql", "models/**")
	if model_result ~= "" then
		local full_path = vim.fn.fnamemodify(model_result, ":p")
		table.insert(tags, {
			name = pattern,
			filename = full_path,
			cmd = "1",
			kind = "m",
		})
	end

	-- Search for seed files
	local seed_result = vim.fn.findfile(pattern .. ".csv", "seeds/**")
	if seed_result ~= "" then
		local full_path = vim.fn.fnamemodify(seed_result, ":p")
		table.insert(tags, {
			name = pattern,
			filename = full_path,
			cmd = "1",
			kind = "s",
		})
	end

	return tags
end

local function setup_tagfunc()
	-- Create an autocommand to set tagfunc for SQL files in dbt projects
	vim.api.nvim_create_autocmd("FileType", {
		pattern = "sql",
		callback = function()
			-- Check if we're in a dbt project by looking for dbt_project.yml
			if vim.fn.findfile("dbt_project.yml", ".;") ~= "" then
				vim.opt_local.tagfunc = "v:lua.require'dbt'.tagfunc"
			end
		end,
	})
end

local function setup_commands()
	vim.api.nvim_create_user_command("DBTUI", function(opts)
		local args = opts.fargs

		if #args == 0 then
			-- No arguments, open UI
			commands.ui()
		elseif args[1] == "grep" then
			-- Remove "grep" from args and pass the rest
			table.remove(args, 1)
			commands.grep(args)
		else
			vim.notify("Unknown DBTUI subcommand: " .. args[1], vim.log.levels.ERROR)
		end
	end, {
		nargs = "*",
		complete = function(arg_lead, cmd_line, cursor_pos)
			-- Basic completion for subcommands
			local subcommands = { "grep" }
			if cmd_line:match("^DBTUI%s+$") or cmd_line:match("^DBTUI%s+%w*$") then
				return vim.tbl_filter(function(val)
					return vim.startswith(val, arg_lead)
				end, subcommands)
			end
		end,
	})
end

function M.setup(opts)
	setup_tagfunc()
	setup_commands()
end

-- Expose tagfunc for vim to call
M.tagfunc = dbt_tagfunc

-- Return the module
return M
