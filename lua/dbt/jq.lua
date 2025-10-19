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

local function _node_processor(node_manifest)
	return {
		key = node_manifest["unique_id"],
		name = node_manifest["name"],
		path = node_manifest["original_file_path"],
		type = node_manifest["resource_type"],
		patch_path = type(node_manifest["patch_path"]) == "string"
				and node_manifest["patch_path"]:gsub("^[^:]+://", "", 1)
			or nil,
	}
end

function _source_processor(source_manifest)
	return {
		key = source_manifest["unique_id"],
		name = source_manifest["source_name"] .. "." .. source_manifest["name"],
		path = source_manifest["original_file_path"],
		type = source_manifest["resource_type"],
		patch_path = type(source_manifest["patch_path"]) == "string"
				and source_manifest["patch_path"]:gsub("^[^:]+://", "", 1)
			or nil,
	}
end

--- @param win integer
--- @param manifest table
--- @return table
function M.get_node(win, manifest)
	local file_path = utils.get_win_path(win)
	if not file_path then
		return {}
	end

	for _, val in pairs(manifest["nodes"]) do
		if val["original_file_path"] == file_path then
			return _node_processor(val)
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
			local node_manifest = manifest["nodes"][parent_id]
			local node = _node_processor(node_manifest)
			table.insert(parents, node)
		end
		if string.find(parent_id, "^source.") then
			local source_manifest = manifest["sources"][parent_id]
			local source = _source_processor(source_manifest)
			table.insert(parents, source)
		end
	end
	return parents
end

--- @param parent_model_id string
--- @param manifest table
--- @return table
function M.get_children(parent_model_id, manifest)
	local child_ids = manifest["child_map"][parent_model_id]
	local children = {}
	for _, child_id in ipairs(child_ids) do
		if string.find(child_id, "^model.") then
			local node_manifest = manifest["nodes"][child_id]
			local node = _node_processor(node_manifest)
			table.insert(children, node)
		end
	end

	return children
end

return M
