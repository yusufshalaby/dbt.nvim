local M = {}

function M.get_manifest_path()
	-- The default path if no custom target-path is found in dbt_project.yml
	local default_path = "target/manifest.json"

	-- Command to find the 'target-path' value in dbt_project.yml and strip surrounding quotes
	local cmd = "awk '/target-path:/ {print $2}' dbt_project.yml | tr -d '\"'"

	-- Note: Using vim.fn.systemlist() directly here for the complex piped command
	-- is simpler than trying to pass it through M_run_sync.
	local lines = vim.fn.systemlist(cmd)

	-- Check for success (exit code 0) and ensure the command returned at least one line
	if vim.v.shell_error == 0 and lines and #lines > 0 then
		local target_dir = lines[1]

		-- Trim any surrounding whitespace that might be in the output
		target_dir = target_dir:match("^%s*(.-)%s*$")

		if target_dir and target_dir ~= "" then
			-- Construct the full path (e.g., "custom_target_dir/manifest.json")
			return target_dir .. "/manifest.json"
		end
	end

	return default_path
end

function M.get_dbt_project_name()
	-- Command to find the 'target-path' value in dbt_project.yml and strip surrounding quotes
	local cmd = "awk '/name:/ {print $2}' dbt_project.yml | tr -d '\"'"

	-- Note: Using vim.fn.systemlist() directly here for the complex piped command
	-- is simpler than trying to pass it through M_run_sync.
	local lines = vim.fn.systemlist(cmd)

	-- Check for success (exit code 0) and ensure the command returned at least one line
	if vim.v.shell_error == 0 and lines and #lines > 0 then
		return lines[1]
	end

	error("yooooo where the dbt_project at nigga")
end

---@param filepath string
function M.read_json_file(filepath)
	-- Read the entire file as a string
	local file = io.open(filepath, "r")
	if not file then
		error("Could not open file: " .. filepath)
	end

	local content = file:read("*a") -- read all contents
	file:close()

	-- Decode the JSON string into a Lua table
	local ok, data = pcall(vim.json.decode, content)
	if not ok then
		error("Invalid JSON in " .. filepath)
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
