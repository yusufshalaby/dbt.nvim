local M = {}

local queries = {
	sources = [[
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
  (#any-of? @parentkey "models" "'models'" "\"models\"")
  value: (block_node
	   (block_sequence
	     (block_sequence_item
	       (block_node
		 (block_mapping
		   (block_mapping_pair
		     key: (flow_node) @modelkeyname
		     (#any-of? @modelkeyname "name" "'name'" "\"name\"")
		     value: (flow_node) @modelname
		     )
		   )
		 )
	       )
	     )
	   )
  )
  ]],
	models = [[
(block_mapping_pair
  key: (flow_node) @parentkey
  (#any-of? @parentkey "models" "'models'" "\"models\"")
  value: (block_node
	   (block_sequence
	     (block_sequence_item
	       (block_node
		 (block_mapping
		   (block_mapping_pair
		     key: (flow_node) @modelkeyname
		     (#any-of? @modelkeyname "name" "'name'" "\"name\"")
		     value: (flow_node) @modelname
		     )
		   )
		 )
	       )
	     )
	   )
  )
  ]],
}

--- @param candidates table sorted table of source candidates
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
	-- if ans == 0 then
	-- 	return nil
	-- end
	-- local hit = candidates[ans]
	-- if hit.sourcename and hit.tablename then
	-- 	return {
	-- 		type = "source",
	-- 		name = hit.sourcename .. "." .. hit.tablename,
	-- 	}
	-- elseif hit.modelname then
	-- 	return {
	-- 		type = "model",
	-- 		name = hit.modelname,
	-- 	}
	-- end
end

---@class SourceCandidate
---@field sourcename string
---@field tablenamme string
---@field row integer

---@class ModelCandidate
---@field modelname string
---@field row integer

---@return table<SourceCandidate|ModelCandidate>
function M.parse_yaml()
	local query = vim.treesitter.query.parse("yaml", queries.sources)
	local tree = vim.treesitter.get_parser():parse()[1]
	local matches = {}
	for id, node, metadata, match in query:iter_captures(tree:root(), 0) do
		if matches[match:info()] == nil then
			matches[match:info()] = {}
		end
		if query.captures[id] == "sourcename" then
			matches[match:info()]["sourcename"] = vim.treesitter.get_node_text(node, vim.api.nvim_get_current_buf())
		elseif query.captures[id] == "tablename" or query.captures[id] == "modelname" then
			matches[match:info()][query.captures[id]] =
				vim.treesitter.get_node_text(node, vim.api.nvim_get_current_buf())
			-- add 1 to row because vim.treesitter.get_range uses 0-based row index
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

-- ---@return Node?
-- function M.current_prior_node()
-- 	local candidates = M.parse_yaml()
-- 	local cur_row = vim.api.nvim_win_get_cursor(0)[1]
-- 	return M.binary_search(candidates, cur_row)
-- end

return M
