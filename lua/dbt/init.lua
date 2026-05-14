local M = {}
local commands = require("dbt.commands")
local ui = require("dbt.ui")
local utils = require("dbt.utils")
local artifact = require("dbt.artifact")

--- Resolve the node for the current buffer.
--- Reuses an open PersistentWindow's cached node if present; otherwise reads
--- target/manifest.json from disk.
--- @param win integer
--- @return Node?
local function get_current_node(win)
	local inst = ui.get_instance_from_refwin(win)
	if inst and inst._node and inst._node.key then
		return inst._node
	end
	local manifest = utils.read_json_file("target/manifest.json")
	if not manifest then return nil end
	local node = artifact.get_node(win, manifest)
	if node and node.key then return node end
end

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

	-- Fall back to the patch_path of the current buffer's node
	if #tags == 0 then
		local node = get_current_node(vim.api.nvim_get_current_win())
		if node and node.patch_path then
			local line = ui.find_patch_line(node.patch_path, node.name) or 1
			table.insert(tags, {
				name = pattern,
				filename = node.patch_path,
				cmd = tostring(line),
			})
		end
	end

	return tags
end

local function setup_tagfunc()
	-- Create an autocommand to set tagfunc for SQL files in dbt projects
	vim.api.nvim_create_autocmd("FileType", {
		pattern = { "sql", "yml", "yaml" },
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
