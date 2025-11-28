local M = {}
local commands = require("dbt.commands")

local function setup_keymaps()
	vim.keymap.set("n", "gd", function()
		local filename = vim.fn.expand("<cfile>")

		local result = ""
		result = vim.fn.findfile(filename .. ".sql", "models/**")
		if result == "" then
			result = vim.fn.findfile(filename .. ".csv", "seeds/**")
		end

		if result ~= "" then
			vim.cmd("edit " .. result)
		else
			vim.cmd("normal! gd")
		end
	end)
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
	setup_keymaps()
	setup_commands()
end

-- Return the module
return M
