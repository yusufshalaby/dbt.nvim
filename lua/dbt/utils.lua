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
	-- The default path if no custom target-path is found in dbt_project.yml
	local default_path = "target/manifest.json"

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

--- @param cmd string The command name (e.g., "jq").
--- @param args table List of arguments (e.g., {'.filter', 'file.json'}).
--- @return table|nil lines List of strings representing stdout output, or nil on error.
--- @return number exit_code The process exit code (0 for success).
--- @return string|nil err Error message if the command failed.
function M.run_sync(cmd, args)
	-- Concatenate the command and arguments into a single shell string.
	-- We wrap the command in single quotes to protect the filter string.
	-- Example: "jq -r '.filter' target/manifest.json"
	local full_cmd = string.format("%s %s", cmd, table.concat(args, " "))

	-- Execute the command synchronously and capture output as a list of lines.
	local lines = vim.fn.systemlist(full_cmd)

	-- vim.v.shell_error is set to 0 on success, >0 on failure.
	local exit_code = vim.v.shell_error
	if exit_code ~= 0 then
		local error_msg = string.format("Command '%s' failed with exit code: %d.", full_cmd, exit_code)
		vim.notify(error_msg, vim.log.levels.ERROR, { title = "dbt.nvim Job Error" })
		return nil, exit_code, error_msg
	end

	-- Return the collected lines, success exit code, and no error message.
	return lines, 0, nil
end

--- PRIVATE HELPER: Handles standard error notification for jq failures.
--- @param exit_code number The exit code from M.run_sync.
--- @param err string|nil The error string from M.run_sync.
--- @param manifest_path string The path that was queried.
function M.notify_error(exit_code, err, manifest_path)
	if exit_code ~= 0 or err then
		local error_details = err or "Check your jq filter and manifest file."
		vim.notify(
			string.format(
				"dbt.nvim: Error running jq (Code %s) on '%s'. Details: %s",
				exit_code or "N/A",
				manifest_path,
				error_details
			),
			vim.log.levels.ERROR
		)
	else
		vim.notify("dbt.nvim: Manifest is valid, but no models matched the filter.", vim.log.levels.INFO)
	end
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
