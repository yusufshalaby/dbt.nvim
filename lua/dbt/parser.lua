local M = {}

local QUERY = [[
(block_mapping_pair
  key: (flow_node) @parentkey
  (#any-of? @parentkey "sources" "'sources'" "\"sources\""
  )
  value: (block_node
           (block_sequence
             (block_sequence_item
               (block_node
                 (block_mapping
                   (block_mapping_pair
			key: (flow_node) @sourcekeyname
			(#any-of? @sourcekeyname "name" "'name'" "\"name\"")
			value: (flow_node) @sourcename
		     )
		(block_mapping_pair
			key: (flow_node) @tableskey
			(#any-of? @tableskey "tables" "'tables'" "\"tables\"")
			value: (block_node
				 (block_sequence
				   (block_sequence_item
				     (block_node
				       (block_mapping
					 (block_mapping_pair
					   key: (flow_node) @tablekeyname
					(#any-of? @tablekeyname "name" "'name'" "\"name\"")
					  value: (flow_node) @tablename
					  )
					   )
					 )
				       )
				     )
				   )
				 )
		     )
                 )
               )
             )
           )
         )

(block_mapping_pair
  key: (flow_node) @parentkey
  (#any-of? @parentkey "models" "'models'" "\"models\""
				"seeds" "'seeds'" "\"seeds\""
				"snapshots" "'snapshots'" "\"snapshots\""
			      )
  value: (block_node
	   (block_sequence
	     (block_sequence_item
	       (block_node
		 (block_mapping
		   (block_mapping_pair
		     key: (flow_node) @nodekey
		     (#any-of? @nodekey "name" "'name'" "\"name\"")
		     value: (flow_node) @nodename
		     )
		   )
		 )
	       )
	     )
	   )
  )
  ]]

--- @param candidates table sorted table of candidates
--- @param row integer
--- @return integer
function M.binary_search(candidates, row)
	local lo, hi, ans = 1, #candidates, 0
	while lo <= hi do
		local mid = math.floor((lo + hi) / 2)
		if candidates[mid].row <= row then
			ans = mid
			lo = mid + 1
		else
			hi = mid - 1
		end
	end
	return ans
end

---@class SourceCandidate
---@field parentkey "sources"
---@field sourcename string
---@field tablename string
---@field row integer

---@class NodeCandidate
---@field parentkey "models" | "seeds" | "snapshots"
---@field nodename string
---@field row integer

---@return table<SourceCandidate|NodeCandidate>
function M.parse_yaml()
	local query = vim.treesitter.query.parse("yaml", QUERY)
	local parser = vim.treesitter.get_parser()
	if not parser then return {} end
	parser:parse()
	local trees = parser:parse()
	if not trees then return {} end
	local matches = {}
	for _, tree in ipairs(trees) do
		for _, match in query:iter_matches(tree:root(), 0) do
			local res = {}
			for id, nodes in pairs(match) do
				local node = nodes[1]
				res[query.captures[id]] = vim.treesitter.get_node_text(node, vim.api.nvim_get_current_buf())
				if query.captures[id] == "tablename" or query.captures[id] == "nodename" then
					res["row"] = vim.treesitter.get_range(node, vim.api.nvim_get_current_buf())[1] + 1
				end
			end

			table.insert(matches, res)
		end
	end
	local candidates = {}
	for _, v in pairs(matches) do
		table.insert(candidates, v)
	end
	table.sort(candidates, function(a, b)
		return a.row < b.row
	end)
	return candidates
end

return M
