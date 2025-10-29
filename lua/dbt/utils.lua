local M = {}

function M.get_dbt_project_name()
	local f = io.open("dbt_project.yml", "r")
	if not f then
		return nil
	end

	for line in f:lines() do
		-- Match: optional quoted key + : + optional quoted value
		-- Value allows letters, numbers, _, -, . (common for dbt project names)
		local q, val = line:match("^[\"']?name[\"']?%s*:%s*([\"']?)([%w_%.%-]+)%1")
		if val then
			f:close()
			return val
		end
	end

	f:close()
	return nil
end

---@param filepath string
---@return table?
function M.read_json_file(filepath)
	-- Read the entire file as a string
	local file = io.open(filepath, "r")
	if not file then
		-- error("Could not open file: " .. filepath)
		return
	end

	local content = file:read("*a") -- read all contents
	file:close()

	-- Decode the JSON string into a Lua table
	local ok, data = pcall(vim.json.decode, content)
	if not ok then
		-- error("Invalid JSON in " .. filepath)
		return
	end

	return data
end

--- Gets the path of the current buffer relative to the CWD (project root).
--- @param win integer
--- @return string|nil path The relative file path, or nil if the buffer is scratch/unnamed.
function M.get_win_path(win)
	-- Get path relative to CWD. This is crucial for matching manifest paths.
	local bufnr = vim.fn.winbufnr(win)
	local bufname = vim.fn.bufname(bufnr)
	local path = vim.fn.fnamemodify(bufname, ":.")
	if path == "" or vim.bo.buftype ~= "" then
		vim.notify("Not a valid file in the project. Try saving first.", vim.log.levels.WARN)
		return nil
	end
	return path
end

return M
