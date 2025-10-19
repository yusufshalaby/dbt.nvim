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
				"seeds" "'seeds'" "\"seeds\"")
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
---@field parentkey "models" | "seeds"
---@field nodename string
---@field row integer

---@return table<SourceCandidate|NodeCandidate>
function M.parse_yaml()
	local query = vim.treesitter.query.parse("yaml", QUERY)
	local tree = vim.treesitter.get_parser():parse()[1]
	local matches = {}
	for id, node, metadata, match in query:iter_captures(tree:root(), 0) do
		if matches[match:info()] == nil then
			matches[match:info()] = {}
		end

		matches[match:info()][query.captures[id]] = vim.treesitter.get_node_text(node, vim.api.nvim_get_current_buf())
		if query.captures[id] == "tablename" or query.captures[id] == "nodename" then
			matches[match:info()]["row"] = vim.treesitter.get_range(node, vim.api.nvim_get_current_buf())[1] + 1
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
