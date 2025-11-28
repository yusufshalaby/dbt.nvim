local M = {}
local factory = require("dbt.ui")
local utils = require("dbt.utils")
local artifact = require("dbt.artifact")

--- Open or toggle the DBTUI window
function M.ui()
	local curwin = vim.api.nvim_get_current_win()
	for _, ui in pairs(factory.persistent_window_instances) do
		if ui.refwin == curwin then
			ui:dispose()
			return
		end
	end
	local manifest = utils.read_json_file("target/manifest.json")
	if not manifest then
		error("Could not load manifest")
	end
	local catalog = utils.read_json_file("target/catalog.json")
	local name = "dbtui-" .. tostring(curwin)
	local ui = factory.new({ name = name, refwin = curwin, manifest = manifest, catalog = catalog })
	ui:open()
end

--- Parse arguments for grep subcommand
--- @param args table List of arguments
--- @return string|nil mode "direct" or "all"
--- @return string|nil filter "upstream", "downstream", or "both"
--- @return string|nil pattern The search pattern
local function parse_grep_args(args)
	local mode = "all"
	local filter = "both"
	local pattern_parts = {}

	for _, arg in ipairs(args) do
		local key, val = arg:match("^(%w+)=(%w+)$")
		if key == "mode" then
			if val == "direct" or val == "all" then
				mode = val
			else
				vim.notify("Invalid mode: " .. val .. ". Use 'direct' or 'all'", vim.log.levels.ERROR)
				return nil, nil, nil
			end
		elseif key == "filter" then
			if val == "upstream" or val == "downstream" or val == "both" then
				filter = val
			else
				vim.notify("Invalid filter: " .. val .. ". Use 'upstream', 'downstream', or 'both'", vim.log.levels.ERROR)
				return nil, nil, nil
			end
		else
			table.insert(pattern_parts, arg)
		end
	end

	local pattern = table.concat(pattern_parts, " ")
	if pattern == "" then
		vim.notify("No search pattern provided", vim.log.levels.ERROR)
		return nil, nil, nil
	end

	return mode, filter, pattern
end

--- Execute grep on lineage nodes
--- @param args table Arguments passed to grep subcommand
function M.grep(args)
	local mode, filter, pattern = parse_grep_args(args)
	if not mode or not filter or not pattern then
		return
	end

	-- Get current node
	local curwin = vim.api.nvim_get_current_win()
	local manifest = utils.read_json_file("target/manifest.json")
	if not manifest then
		vim.notify("Could not load manifest.json", vim.log.levels.ERROR)
		return
	end

	local node = artifact.get_node(curwin, manifest)
	if not node or not node.key then
		vim.notify("No dbt node found in current buffer", vim.log.levels.ERROR)
		return
	end

	-- Collect nodes based on mode and filter
	local nodes = {}
	if filter == "upstream" or filter == "both" then
		local upstream = mode == "direct"
			and artifact.get_parents(node.key, manifest)
			or artifact.get_all_upstream(node.key, manifest, nil, nil)
		for _, n in ipairs(upstream) do
			table.insert(nodes, n)
		end
	end

	if filter == "downstream" or filter == "both" then
		local downstream = mode == "direct"
			and artifact.get_children(node.key, manifest)
			or artifact.get_all_downstream(node.key, manifest, nil, nil)
		for _, n in ipairs(downstream) do
			table.insert(nodes, n)
		end
	end

	if #nodes == 0 then
		vim.notify("No nodes found to search", vim.log.levels.WARN)
		return
	end

	-- Build file list
	local files = {}
	for _, n in ipairs(nodes) do
		if n.path then
			table.insert(files, n.path)
		end
	end

	if #files == 0 then
		vim.notify("No files found to search", vim.log.levels.WARN)
		return
	end

	-- Escape forward slashes for vimgrep delimiter
	local escaped_pattern = pattern:gsub("/", "\\/")
	-- Wrap with Vim word boundaries to match whole words only
	escaped_pattern = "\\<" .. escaped_pattern .. "\\>"

	-- Execute vimgrep
	local vimgrep_cmd = string.format("vimgrep /%s/gj %s", escaped_pattern, table.concat(files, " "))
	local success, err = pcall(vim.cmd, vimgrep_cmd)

	if success then
		vim.cmd("copen")
	else
		-- Check if error is just "no match found"
		if err:match("E480") then
			vim.notify("Pattern not found: " .. pattern, vim.log.levels.WARN)
		else
			vim.notify("vimgrep error: " .. tostring(err), vim.log.levels.ERROR)
		end
	end
end

return M
