local M = {}

local filters = {
	models = '\'.nodes | with_entries(select(.key | startswith("model."))) | .[] | {"name":.name, "path": .original_file_path}\'',
	seeds = '.nodes | with_entries(select(.key | startswith("seed."))) | .[].name',
	children = [['
	    . as $manifest |
	    (.nodes | to_entries[] |
	    select(.value.original_file_path == $filepath) |
	    .key) as $parent_model_id |
	    (.child_map[$parent_model_id] | 
	    map(select(startswith("model.")))) as $child_ids |
	      $child_ids[] | 
	      {
		      "name": $manifest.nodes[.].name,
		      "path": $manifest.nodes[.].original_file_path
	      }
	']],
}

--- @param cmd string The command name (e.g., "jq").
--- @param args table List of arguments (e.g., {'.filter', 'file.json'}).
--- @return table|nil lines List of strings representing stdout output, or nil on error.
--- @return number exit_code The process exit code (0 for success).
--- @return string|nil err Error message if the command failed.
local function _run_sync(cmd, args)
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

--- Finds the dbt target directory from dbt_project.yml and constructs the manifest path.
--- Falls back to the default path if the command fails.
--- @return string path The path to the manifest.json file.
local function _get_manifest_path()
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

--- PRIVATE HELPER: Handles Quickfix population and opening.
--- @param qf_items table List of Quickfix entries.
--- @param title string The title for the Quickfix window.
local function _open_quickfix(qf_items, title)
	vim.fn.setqflist({}, " ", {
		items = qf_items,
		title = title,
	})
	vim.cmd("copen")
end

--- PRIVATE HELPER: Handles standard error notification for jq failures.
--- @param exit_code number The exit code from M.run_sync.
--- @param err string|nil The error string from M.run_sync.
--- @param manifest_path string The path that was queried.
local function _notify_error(exit_code, err, manifest_path)
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

--- PRIVATE HELPER: Runs a jq filter and processes the output into Quickfix items.
--- @param filter string The jq filter to use.
--- @param args table List of arguments to pass to jq after the filter (e.g., args for --arg).
--- @return table | nil lines Results from jq parsing of manifest
local function _run_filter(filter, args)
	local manifest_path = _get_manifest_path()

	table.insert(args, filter) -- Insert the filter
	table.insert(args, manifest_path) -- Insert the file path

	local lines, exit_code, err = _run_sync("jq", args)

	if exit_code == 0 and not err and lines and #lines > 0 then
		return lines
	else
		_notify_error(exit_code, err, manifest_path)
		return nil
	end
end

--- @param qf_items table
--- @param title_func function Function that returns the title string for the Quickfix list.
local function _populate_quickfix(qf_items, title_func)
	if #qf_items > 0 then
		_open_quickfix(qf_items, title_func(true))
	else
		-- Handle case where jq ran successfully but returned no results
		vim.notify("dbt.nvim: No resources found matching the filter.", vim.log.levels.INFO)
	end
end

--- @param lines table<string>
--- @return table
local function _model_processor(lines)
	local models = {}
	for _, line in ipairs(lines) do
		if #line > 0 then
			local success, entry = pcall(vim.json.decode, line)
			if success and entry and entry.name and entry.path then
				table.insert(models, {
					filename = entry.path,
					text = entry.name, -- Display model name
					lnum = 1,
				})
			end
		end
	end
	return models
end

--- Gets all dbt models from the manifest and loads them into the Quickfix list.
function M.get_models()
	local lines = _run_filter(filters.models, { "-r", "-c" })

	if lines and #lines > 0 then
		local models = _model_processor(lines)
		_populate_quickfix(models, function()
			return "dbt models"
		end)
	end
end

--- Gets the path of the current buffer relative to the CWD (project root).
--- @return string|nil The relative file path, or nil if the buffer is scratch/unnamed.
function M.get_current_model_path()
	-- Get path relative to CWD. This is crucial for matching manifest paths.
	local path = vim.fn.fnamemodify(vim.fn.bufname(), ":.")
	if path == "" or vim.bo.buftype ~= "" then
		vim.notify("Not a valid file in the project. Try saving first.", vim.log.levels.WARN)
		return nil
	end
	return path
end

--- Gets the immediate children (dependents) of the current model and loads them into the Quickfix list.
function M.get_children()
	local current_file = M.get_current_model_path()
	if not current_file then
		return
	end

	local title_func = function(success)
		local model_name = vim.fn.fnamemodify(current_file, ":t:r")
		if not success then
			return "dbt Children Error: " .. model_name
		end
		return "dbt Children of: " .. model_name
	end

	local lines = _run_filter(
		filters.children,
		-- Add -r and -c for compact JSON output, and the --arg for the file path
		{ "-r", "-c", "--arg", "filepath", current_file }
	)
	if lines and #lines > 0 then
		local models = _model_processor(lines)
		_populate_quickfix(models, title_func)
	end
end

function M.setup(opts)
	-- Merge user options with defaults
	opts = opts or {}
end

-- Return the module
return M
