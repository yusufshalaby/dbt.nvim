local M = {}
local utils = require("dbt.utils")

M.filters = {
	path_to_model = [['
		(.nodes | to_entries[] | select(.value.original_file_path == $filepath) |
		select(.key | startswith("model.") or startswith("seed.")) |
		{ "key": .key, "name": .value.name, "path": .value.original_file_path, "type": .value.resource_type})
	']],
	models = '\'.nodes | with_entries(select(.key | startswith("model."))) | .[] | {"name":.name, "path": .original_file_path}\'',
	seeds = '.nodes | with_entries(select(.key | startswith("seed."))) | .[].name',
	children = [['
	    . as $manifest |
	    (.child_map[$parent_model_id] // [] | 
	    map(select(startswith("model.")))) as $child_ids |
	      $child_ids[] | 
	      {
		      "key": .,
		      "name": $manifest.nodes[.].name,
		      "path": $manifest.nodes[.].original_file_path,
		      "type": $manifest.nodes[.].resource_type,
	      }
	']],
	parents = [['
	    . as $manifest |
	    (.parent_map[$child_model_id] // [] | 
	    map(select(startswith("model.") or startswith("seed.") or startswith("source.")))) as $parent_ids |
	      $parent_ids[]? | 
	      {
		      "key": .,
		      "name": ($manifest.nodes[.].name // $manifest.sources[.].source_name + "." + $manifest.sources[.].name),
		      "path": ($manifest.nodes[.].original_file_path // $manifest.sources[.].original_file_path),
		      "type": ($manifest.nodes[.].resource_type // $manifest.sources[.].resource_type),
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

--- @param parent_model_id string
--- @param manifest table
--- @return table
function M.get_children(parent_model_id, manifest)
	local child_ids = manifest["child_map"][parent_model_id]
	local children = {}
	for _, child_id in ipairs(child_ids) do
		if string.find(child_id, "^model.") then
			local child_node = manifest["nodes"][child_id]
			table.insert(children, {
				key = child_id,
				name = child_node["name"],
				path = child_node["original_file_path"],
				type = child_node["resource_type"],
			})
		end
	end

	return children
end

--- @param win integer
--- @param manifest table
--- @return table
function M.get_model(win, manifest)
	local file_path = utils.get_win_path(win)
	if not file_path then
		return {}
	end

	for key, val in pairs(manifest["nodes"]) do
		if val["original_file_path"] == file_path then
			return {
				key = key,
				path = val["original_file_path"],
				name = val["name"],
				type = val["resource_type"],
			}
		end
	end

	return {}
end

--- @param child_model_id string
--- @param manifest table
--- @return table
function M.get_parents(child_model_id, manifest)
	local parent_ids = manifest["parent_map"][child_model_id]
	local parents = {}
	for _, parent_id in ipairs(parent_ids) do
		if string.find(parent_id, "^model.") or string.find(parent_id, "^seed.") then
			local parent_node = manifest["nodes"][parent_id]
			table.insert(parents, {
				key = parent_id,
				name = parent_node["name"],
				path = parent_node["original_file_path"],
				type = parent_node["resource_type"],
			})
		end
		if string.find(parent_id, "^source.") then
			local parent_node = manifest["sources"][parent_id]
			table.insert(parents, {
				key = parent_id,
				name = parent_node["source_name"] .. "." .. parent_node["name"],
				path = parent_node["original_file_path"],
				type = parent_node["resource_type"],
			})
		end
	end
	return parents
end

return M
