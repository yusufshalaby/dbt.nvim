local parser = require("dbt.parser")
local jq = require("dbt.manifest")
local utils = require("dbt.utils")

---@class Node
---@field name string
---@field path? string
---@field key? string
---@field type "model" | "source" | "seed" | "snapshot"
---@field patch_path? string

---@class Column
---@field type string
---@field name string
---@field index integer
---@field comment string

---@class Content
---@field type "model" | "source" | "seed" | "header" | "noaction"
---@field value? "children" | "parents" | Node
---@field text? string

---@class dbt.PersistentWindow
---@field public name string
---@field public project string
---@field bufnr integer
---@field refwin integer
---@field _win integer?
---@field _manifest table
---@field _catalog table?
---@field _autocmd_group string
---@field _children table<Node>
---@field _parents table<Node>
---@field _columns table<Column>
---@field _children_collapsed boolean
---@field _parents_collapsed boolean
---@field _columns_collapsed boolean
---@field _index_map table<Content>
---@field _node Node?
---@field _yaml_candidates table<SourceCandidate|NodeCandidate>
---@field _yaml_node_lb integer?
---@field _yaml_node_ub integer?
local PersistentWindow = {}

local ui = {}
ui.persistent_window_instances = {}

---@class dbt.PersistentWindowOpts
---@field name string
---@field refwin integer
---@field manifest table
---@field catalog table

---@param opts dbt.PersistentWindowOpts
function PersistentWindow:new(opts)
	self.__index = self
	local bufnr = self:buffer(opts)
	local project = utils.get_dbt_project_name()
	return setmetatable({
		name = opts.name,
		project = project,
		refwin = opts.refwin,
		bufnr = bufnr,
		_win = nil,
		_manifest = opts.manifest,
		_catalog = opts.catalog,
		_autocmd_group = "dbt_nvim_win_" .. tostring(opts.refwin),
		_children = {},
		_parents = {},
		_columns = {},
		_children_collapsed = false,
		_parents_collapsed = false,
		_index_map = { "noaction" },
		_yaml_candidates = {},
		_yaml_node_lb = nil,
		_yaml_node_ub = nil,
	}, self)
end

function PersistentWindow:open()
	local total_cols = vim.opt.columns:get()
	local target_width = math.floor(total_cols / 3)
	self._win = vim.api.nvim_open_win(self.bufnr, true, { split = "right", style = "minimal", width = target_width })
	vim.api.nvim_set_option_value("number", false, { win = self._win })
	vim.api.nvim_set_option_value("relativenumber", false, { win = self._win })
	vim.api.nvim_set_option_value("spell", false, { win = self._win })
	vim.api.nvim_set_option_value("winfixwidth", true, { win = self._win })
	ui.persistent_window_instances[self._win] = self
	self:setup_autocmds()
	vim.api.nvim_set_current_win(self.refwin)
	self:update_node()
end

--- Creates and configures persistent read only buffer
--- @param opts dbt.PersistentWindowOpts
--- @return integer bufnr
function PersistentWindow:buffer(opts)
	if self.bufnr and vim.api.nvim_buf_is_valid(self.bufnr) and vim.api.nvim_buf_is_loaded(self.bufnr) then
		return self.bufnr
	end
	local bufnr = vim.api.nvim_create_buf(true, false)

	vim.api.nvim_set_option_value("buflisted", false, { buf = bufnr })
	vim.api.nvim_set_option_value("buftype", "nofile", { buf = bufnr })
	vim.api.nvim_set_option_value("modifiable", false, { buf = bufnr })
	vim.api.nvim_set_option_value("swapfile", false, { buf = bufnr })
	vim.api.nvim_set_option_value("filetype", "dbt_window", { buf = bufnr })

	vim.api.nvim_buf_set_name(bufnr, opts.name)
	return bufnr
end

---@param parse boolean
---@param node Node?
function PersistentWindow:update_yaml_candidates(parse, node)
	if parse then
		self._yaml_candidates = parser.parse_yaml()
	end
	if #self._yaml_candidates == 0 then
		self._node = nil
		self._yaml_node_lb = nil
		self._yaml_node_ub = nil
		return
	end

	local nearest = 0
	-- if the node was passed then set PersistentWindow node to that
	if node then
		for i, v in ipairs(self._yaml_candidates) do
			local key = ""
			if node.type == "source" then
				key = "source." .. self.project .. "." .. v.sourcename .. "." .. v.tablename
			elseif node.type == "model" then
				key = "model." .. self.project .. "." .. v.modellane
			end

			if node.key == key then
				nearest = i
				break
			end
		end
		self._node = node

		-- otherwise infer based on the location of the cursor
	else
		local cur_row = vim.api.nvim_win_get_cursor(0)[1]
		nearest = parser.binary_search(self._yaml_candidates, cur_row)
		if nearest == 0 then
			self._node = nil
			self._yaml_node_lb = nil
			self._yaml_node_ub = self._yaml_candidates[1].row - 1
			return
		end

		local hit = self._yaml_candidates[nearest]
		if hit.sourcename and hit.tablename then
			self._node = {
				type = "source",
				key = "source." .. self.project .. "." .. hit.sourcename .. "." .. hit.tablename,
				name = hit.sourcename .. "." .. hit.tablename,
			}
		elseif hit.nodename then
			-- local nodetype = hit.parentkey == "models" and "model" or "seed"
			local nodetype
			if hit.parentkey == "models" then
				nodetype = "model"
			elseif hit.parentkey == "seeds" then
				nodetype = "seed"
			elseif hit.parentkey == "snapshots" then
				nodetype = "snapshot"
			end
			self._node = {
				type = nodetype,
				key = nodetype .. "." .. self.project .. "." .. hit.nodename,
				name = hit.nodename,
			}
		else
			-- TODO: deal with this case properly
			self._node = nil
		end
	end

	if nearest > 0 then
		self._yaml_node_lb = self._yaml_candidates[nearest].row
		if nearest < #self._yaml_candidates then
			self._yaml_node_ub = self._yaml_candidates[nearest + 1].row - 1
		else
			self._yaml_node_ub = nil
		end
	else
		-- if the node is in the yaml file but can't be detected by treesitter
		-- we set the bounds to 1 to ensure the parsing continues to update
		-- when the cursor moves
		self._yaml_node_lb = 1
		self._yaml_node_ub = 1
	end
end

function PersistentWindow:update_node()
	local bufnr = vim.api.nvim_win_get_buf(self.refwin)
	local ft = vim.bo[bufnr].filetype
	if ft == "sql" or ft == "csv" or ft == "python" then
		self._node = jq.get_node(self.refwin, self._manifest)
	elseif ft == "yaml" then
		self:update_yaml_candidates(true)
	end
	self:update_sections()
end

function PersistentWindow:update_sections()
	if self._node ~= nil then
		self._parents = jq.get_parents(self._node.key, self._manifest)
		self._children = jq.get_children(self._node.key, self._manifest)
		if self._catalog ~= nil then
			self._columns = jq.get_columns(self._node, self._catalog)
		end
	else
		self._parents = {}
		self._children = {}
		self._columns = {}
	end
	self:render_content()
end

--- @param section "children" | "parents"
function PersistentWindow:toggle_section(section)
	if section == "parents" then
		self._parents_collapsed = not self._parents_collapsed
	elseif section == "children" then
		self._children_collapsed = not self._children_collapsed
	elseif section == "columns" then
		self._columns_collapsed = not self._columns_collapsed
	else
		local error_msg = string.format("Invalid section: %s", section)
		vim.notify(error_msg, vim.log.levels.ERROR, { title = "dbt.nvim Error" })
		return
	end
	self:render_content()
end

--- @param node Node
function PersistentWindow:go_to_path(node)
	local modelbufnr = vim.fn.bufnr(node.path, true)
	if modelbufnr > 0 then
		vim.api.nvim_win_set_buf(self.refwin, modelbufnr)
		if vim.bo[modelbufnr].filetype == "yaml" then
			-- the bufenter autocommand does the treesitter parsing
			self:update_yaml_candidates(false, node)
			self:update_sections()
		end
	end
	-- TODO error handling
end

--- @param node Node
function PersistentWindow:go_to_patch_path(node)
	if node.patch_path then
		local modelbufnr = vim.fn.bufnr(node.patch_path, true)
		if modelbufnr > 0 then
			vim.api.nvim_win_set_buf(self.refwin, modelbufnr)
			-- TODO error handling
		end
	end
end

function PersistentWindow:user_action()
	local win_cursor = vim.api.nvim_win_get_cursor(self._win)
	local current_line = win_cursor[1]
	local content = self._index_map[current_line]

	if type(content) ~= "table" or content.type == nil or content.value == nil then
		return
	end

	if content.type == "title" then
		self:go_to_patch_path(content.value)
	elseif content.type == "header" then
		self:toggle_section(content.value)
	elseif content.type == "model" or content.type == "seed" or content.type == "snapshot" or content.type == "source" then
		self:go_to_path(content.value)
	end
end

function PersistentWindow:setup_interactions()
	-- Clear existing maps (good practice)
	vim.api.nvim_buf_clear_namespace(self.bufnr, 0, 0, -1)

	-- We pass self._win (the window ID) to the static handler function.
	vim.api.nvim_buf_set_keymap(
		self.bufnr,
		"n",
		"<CR>",
		string.format('<Cmd>lua require("dbt.ui").handle_key_press(%d)<CR>', self._win),
		{ noremap = true, silent = true }
	)
end

function PersistentWindow:render_content()
	local text = {}
	local index_map = {}

	if self._node then
		local type = self._node.type:gsub("^%l", string.upper)
		local title = string.format("%s: %s", type, self._node.name)
		table.insert(text, title)
		table.insert(index_map, { type = "title", value = self._node })
		table.insert(text, "")
		table.insert(index_map, { type = "noaction" })
	end

	--- @param list table
	--- @param section "parents" | "children"
	--- @param data table
	--- @param collapsed boolean
	local function format_nodes(list, section, data, collapsed)
		table.insert(list, string.format("%s (%d)", section:gsub("^%l", string.upper), #data))
		table.insert(index_map, { type = "header", value = section })
		if data and #data > 0 and not collapsed then
			local count = #data
			for i, node in ipairs(data) do
				local connector = (i == count) and "└╴" or "├╴"
				table.insert(list,
					"  " .. connector .. " " .. node.name .. " " .. string.upper(node.type))
				table.insert(index_map, { type = node.type, value = node })
			end
		end
	end


	local function format_columns()
		table.insert(text, string.format("Columns (%d)", #self._columns))
		table.insert(index_map, { type = "header", value = "columns" })
		if self._columns and #self._columns > 0 and not self._columns_collapsed then
			local count = #self._columns
			for i, col in pairs(self._columns) do
				local connector = (i == count) and "└╴" or "├╴"
				table.insert(text, "  " .. connector .. " " .. col.name .. " " .. col.type)
				table.insert(index_map, { type = "column", value = col })
			end
		end
	end

	format_nodes(text, "parents", self._parents, self._parents_collapsed)
	table.insert(text, "")
	table.insert(index_map, { type = "noaction" })
	format_nodes(text, "children", self._children, self._children_collapsed)
	table.insert(text, "")
	table.insert(index_map, { type = "noaction" })
	format_columns()

	vim.api.nvim_set_option_value("modifiable", true, { buf = self.bufnr })
	vim.api.nvim_buf_set_lines(self.bufnr, 0, -1, true, text)
	vim.api.nvim_set_option_value("modifiable", false, { buf = self.bufnr })

	self._index_map = index_map

	self:setup_interactions()
end

function PersistentWindow:dispose()
	pcall(vim.api.nvim_del_augroup_by_name, self._autocmd_group)
	ui.persistent_window_instances[self._win] = nil
	vim.api.nvim_buf_delete(self.bufnr, { force = true })
end

function PersistentWindow:setup_autocmds()
	vim.api.nvim_create_augroup(self._autocmd_group, { clear = true })
	vim.api.nvim_create_autocmd("BufWinEnter", {
		group = self._autocmd_group,
		pattern = { "*.sql", "*.csv", "*.py" },
		callback = function()
			local win = vim.api.nvim_get_current_win()
			if win == self.refwin then
				self._node = jq.get_node(self.refwin, self._manifest)
				self:update_sections()
			end
		end,
	})

	vim.api.nvim_create_autocmd("BufWinEnter", {
		group = self._autocmd_group,
		pattern = { "*.yml", "*.yaml" },
		callback = function()
			local win = vim.api.nvim_get_current_win()
			if win == self.refwin then
				self:update_yaml_candidates(true)
			end
		end,
	})

	vim.api.nvim_create_autocmd("BufWrite", {
		group = self._autocmd_group,
		pattern = { "*.yml", "*.yaml" },
		callback = function()
			local win = vim.api.nvim_get_current_win()
			if win == self.refwin then
				self:update_yaml_candidates(true)
				self:update_sections()
			end
		end,
	})

	vim.api.nvim_create_autocmd("CursorHold", {
		group = self._autocmd_group,
		pattern = { "*.yml", "*.yaml" },
		callback = function()
			local win = vim.api.nvim_get_current_win()
			if win == self.refwin then
				local cur_row = vim.api.nvim_win_get_cursor(0)[1]
				if
				    (self._yaml_node_lb and cur_row < self._yaml_node_lb)
				    or (self._yaml_node_ub and cur_row > self._yaml_node_ub)
				then
					self:update_yaml_candidates(false)
					self:update_sections()
				end
			end
		end,
	})

	vim.api.nvim_create_autocmd("WinClosed", {
		group = self._autocmd_group,
		pattern = tostring(self._win),
		callback = function()
			self:dispose()
		end,
	})
end

--- Utility function to get the instance from a window ID for keymaps
-- @param win_id number The Neovim window ID
-- @return PersistentWindow|nil
function ui.get_instance_from_win(win_id)
	return ui.persistent_window_instances[win_id]
end

--- STATIC HANDLER: Centralized function called directly by the keymap.
-- It retrieves the instance and calls the action method.
-- This cleans up the logic inside the setup_interactions string.
-- @param win_id number The window ID passed by the keymap execution.
ui.handle_key_press = function(win_id)
	local inst = ui.get_instance_from_win(win_id)
	if inst then
		inst:user_action()
	end
end

--- @param opts dbt.PersistentWindowOpts
function ui.new(opts)
	return PersistentWindow:new({
		name = opts.name,
		refwin = opts.refwin,
		manifest = opts.manifest,
		catalog = opts
		    .catalog
	})
end

return ui
