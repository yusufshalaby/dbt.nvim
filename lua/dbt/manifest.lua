local M = {}
local utils = require("dbt.utils")

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

local function _source_processor(source_manifest)
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

	for _, val in pairs(manifest["macros"]) do
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
	if not parent_ids then return parents end
	for _, parent_id in ipairs(parent_ids) do
		if string.find(parent_id, "^model.") or
		    string.find(parent_id, "^seed.") or
		    string.find(parent_id, "^snapshot.") then
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
	if not child_ids then return children end
	for _, child_id in ipairs(child_ids) do
		if string.find(child_id, "^model.") or string.find(child_id, "^snapshot.") then
			local node_manifest = manifest["nodes"][child_id]
			local node = _node_processor(node_manifest)
			table.insert(children, node)
		end
	end

	return children
end

return M
