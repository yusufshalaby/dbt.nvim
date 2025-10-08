local M = {}
local utils = require("dbt.utils")

M.filters = {
	models = '\'.nodes | with_entries(select(.key | startswith("model."))) | .[] | {"name":.name, "path": .original_file_path}\'',
	seeds = '.nodes | with_entries(select(.key | startswith("seed."))) | .[].name',
	children = [['
	    . as $manifest |
	    (.nodes | to_entries[] |
	    select(.value.original_file_path == $filepath) |
	    select(.key | startswith("model.") or startswith("seed.")) |
	    .key) as $parent_model_id |
	    (.child_map[$parent_model_id] | 
	    map(select(startswith("model.")))) as $child_ids |
	      $child_ids[] | 
	      {
		      "name": $manifest.nodes[.].name,
		      "path": $manifest.nodes[.].original_file_path
	      }
	']],
	parents = [['
	    . as $manifest |
	    (.nodes | to_entries[] |
	    select(.value.original_file_path == $filepath) |
	    select(.key | startswith("model.") or startswith("seed.")) |
	    .key) as $child_model_id |
	    (.parent_map[$child_model_id] | 
	    map(select(startswith("model.") or startswith("seed.")))) as $parent_ids |
	      $parent_ids[] | 
	      {
		      "name": $manifest.nodes[.].name,
		      "path": $manifest.nodes[.].original_file_path
	      }
	']],
}

--- @param filter string The jq filter to use.
--- @param args table List of arguments to pass to jq after the filter (e.g., args for --arg).
--- @return table | nil lines Results from jq parsing of manifest
function M.run_filter(filter, args)
	local manifest_path = utils.get_manifest_path()

	table.insert(args, filter) -- Insert the filter
	table.insert(args, manifest_path) -- Insert the file path

	local lines, exit_code, err = utils.run_sync("jq", args)

	if exit_code == 0 and not err and lines and #lines > 0 then
		return lines
	else
		-- utils.notify_error(exit_code, err, manifest_path)
		return nil
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
					path = entry.path,
					name = entry.name, -- Display model name
				})
			end
		end
	end
	return models
end

--- @param win integer
function M.get_children(win)
	local file_path = utils.get_win_path(win)
	if not file_path then
		return {}
	end

	local lines = M.run_filter(
		M.filters.children,
		-- Add -r and -c for compact JSON output, and the --arg for the file path
		{ "-r", "-c", "--arg", "filepath", file_path }
	)
	if lines and #lines > 0 then
		local models = _model_processor(lines)
		return models
	end
	return {}
end

--- @param win integer
--- @return table
function M.get_parents(win)
	local file_path = utils.get_win_path(win)
	if not file_path then
		return {}
	end

	local lines = M.run_filter(
		M.filters.parents,
		-- Add -r and -c for compact JSON output, and the --arg for the file path
		{ "-r", "-c", "--arg", "filepath", file_path }
	)
	if lines and #lines > 0 then
		local models = _model_processor(lines)
		return models
	end
	return {}
end

return M
