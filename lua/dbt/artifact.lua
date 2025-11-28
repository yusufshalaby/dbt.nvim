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
--- @param seen table|nil
--- @return table<Node>
function M.get_all_downstream(node_id, manifest, visited, seen)
	visited = visited or {}
	seen = seen or {}
	local downstream = {}

	-- Avoid cycles
	if visited[node_id] then
		return downstream
	end
	visited[node_id] = true

	local immediate_children = manifest["child_map"][node_id] or {}
	for _, child_id in ipairs(immediate_children) do
		if string.find(child_id, "^model.") or string.find(child_id, "^snapshot.") then
			-- Only add if we haven't seen this node before
			if not seen[child_id] then
				seen[child_id] = true
				local node_manifest = manifest["nodes"][child_id]
				local node = _node_processor(node_manifest)
				table.insert(downstream, node)
			end
			-- Recursively get downstream of this child
			local child_downstream = M.get_all_downstream(child_id, manifest, visited, seen)
			for _, desc_node in ipairs(child_downstream) do
				table.insert(downstream, desc_node)
			end
		end
	end

	return downstream
end

--- Get all upstream models recursively
--- @param node_id string
--- @param manifest table
--- @param visited table|nil
--- @param seen table|nil
--- @return table<Node>
function M.get_all_upstream(node_id, manifest, visited, seen)
	visited = visited or {}
	seen = seen or {}
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
		   string.find(parent_id, "^snapshot.") then
			-- Only add if we haven't seen this node before
			if not seen[parent_id] then
				seen[parent_id] = true
				local node_manifest = manifest["nodes"][parent_id]
				local node = _node_processor(node_manifest)
				table.insert(upstream, node)
			end
			-- Recursively get upstream of this parent
			local parent_upstream = M.get_all_upstream(parent_id, manifest, visited, seen)
			for _, anc_node in ipairs(parent_upstream) do
				table.insert(upstream, anc_node)
			end
		end
		if string.find(parent_id, "^source.") then
			-- Only add if we haven't seen this source before
			if not seen[parent_id] then
				seen[parent_id] = true
				local source_manifest = manifest["sources"][parent_id]
				local source = _source_processor(source_manifest)
				table.insert(upstream, source)
			end
			-- Recursively get upstream of this source
			local source_upstream = M.get_all_upstream(parent_id, manifest, visited, seen)
			for _, anc_node in ipairs(source_upstream) do
				table.insert(upstream, anc_node)
			end
		end
	end

	return upstream
end

--- Sort nodes by type and name following dbt conventions
--- Order: sources -> seeds -> snapshots -> models (base -> stg -> int -> marts/other)
--- Within each group, sort alphabetically by name
--- @param nodes table<Node>
--- @return table<Node>
function M.sort_nodes(nodes)
	local function get_type_order(node)
		if node.type == "source" then
			return 1
		elseif node.type == "seed" then
			return 2
		elseif node.type == "snapshot" then
			return 3
		elseif node.type == "model" then
			return 4
		else
			return 5
		end
	end

	local function get_model_prefix_order(name)
		if string.match(name, "^base_") then
			return 1
		elseif string.match(name, "^stg_") then
			return 2
		elseif string.match(name, "^int_") then
			return 3
		else
			return 4
		end
	end

	table.sort(nodes, function(a, b)
		local type_order_a = get_type_order(a)
		local type_order_b = get_type_order(b)

		if type_order_a ~= type_order_b then
			return type_order_a < type_order_b
		end

		-- If both are models, sort by prefix
		if a.type == "model" and b.type == "model" then
			local prefix_order_a = get_model_prefix_order(a.name)
			local prefix_order_b = get_model_prefix_order(b.name)

			if prefix_order_a ~= prefix_order_b then
				return prefix_order_a < prefix_order_b
			end
		end

		-- Within the same type and prefix, sort alphabetically by name
		return a.name < b.name
	end)

	return nodes
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
