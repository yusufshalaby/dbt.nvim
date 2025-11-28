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
--- @return table<Node>
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
--- @return table<Node>
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

--- Get all downstream models recursively
--- @param node_id string
--- @param manifest table
--- @param visited table|nil
--- @return table<string>
function M.get_all_downstream(node_id, manifest, visited)
	visited = visited or {}
	local downstream = {}

	-- Avoid cycles
	if visited[node_id] then
		return downstream
	end
	visited[node_id] = true

	local immediate_children = manifest["child_map"][node_id] or {}
	for _, child_id in ipairs(immediate_children) do
		if string.find(child_id, "^model.") or string.find(child_id, "^snapshot.") then
			table.insert(downstream, child_id)
			-- Recursively get downstream of this child
			local child_downstream = M.get_all_downstream(child_id, manifest, visited)
			for _, desc_id in ipairs(child_downstream) do
				table.insert(downstream, desc_id)
			end
		end
	end

	return downstream
end

--- Get all upstream models recursively
--- @param node_id string
--- @param manifest table
--- @param visited table|nil
--- @return table<string>
function M.get_all_upstream(node_id, manifest, visited)
	visited = visited or {}
	local upstream = {}

	-- Avoid cycles
	if visited[node_id] then
		return upstream
	end
	visited[node_id] = true

	local immediate_parents = manifest["parent_map"][node_id] or {}
	for _, parent_id in ipairs(immediate_parents) do
		if string.find(parent_id, "^model.") or
		   string.find(parent_id, "^seed.") or
		   string.find(parent_id, "^snapshot.") or
		   string.find(parent_id, "^source.") then
			table.insert(upstream, parent_id)
			-- Recursively get upstream of this parent
			local parent_upstream = M.get_all_upstream(parent_id, manifest, visited)
			for _, anc_id in ipairs(parent_upstream) do
				table.insert(upstream, anc_id)
			end
		end
	end

	return upstream
end

---@param node Node
---@param catalog table
---@return table<Column>
function M.get_columns(node, catalog)
	local key = node.type == "source" and "sources" or "nodes"
	local node_catalog = catalog[key][node.key]
	if node_catalog == nil then
		return {}
	end
	local cols_dict = node_catalog["columns"]
	-- Convert dictionary to array
	local cols = {}
	for _, col in pairs(cols_dict) do
		table.insert(cols, col)
	end
	-- Sort the array by index
	table.sort(cols, function(a, b)
		return a.index < b.index
	end)
	return cols
end

return M
