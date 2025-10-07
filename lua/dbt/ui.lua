---@class Model
---@field name string
---@field path string

---@class Content
---@field type "model" | "header" | "blank"
---@field value? string | Model
---@field text? string

---@class dbt.PersistentWindow
---@field public name string
---@field _bufnr integer
---@field _win? integer
---@field _children table<Model>
---@field _parents table<Model>
---@field _children_collapsed boolean
---@field _parents_collapsed boolean
---@field _index_map table<Content>
local PersistentWindow = {}

local ui = {}
ui.persistent_window_instances = {}

---@class dbt.PersistentWindowOpts
---@field name string

---@param opts dbt.PersistentWindowOpts
function PersistentWindow:new(opts)
	self.__index = self
	local bufnr = self:buffer(opts)
	return setmetatable({
		name = opts.name,
		_bufnr = bufnr,
		_children = {},
		_parents = {},
		_children_collapsed = false,
		_parents_collapsed = false,
		_index_map = { "blank" },
	}, self)
end

function PersistentWindow:open()
	local total_cols = vim.opt.columns:get()
	local target_width = math.floor(total_cols / 3)
	self._win = vim.api.nvim_open_win(self._bufnr, true, { split = "right", style = "minimal", width = target_width })
	vim.api.nvim_set_option_value("number", false, { win = self._win })
	vim.api.nvim_set_option_value("relativenumber", false, { win = self._win })
	vim.api.nvim_set_option_value("spell", false, { win = self._win })
	vim.api.nvim_set_option_value("winfixwidth", true, { win = self._win })
	ui.persistent_window_instances[self._win] = self
end

--- Creates and configures persistent read only buffer
--- @param opts dbt.PersistentWindowOpts
--- @return integer bufnr
function PersistentWindow:buffer(opts)
	if self._bufnr and vim.api.nvim_buf_is_valid(self._bufnr) and vim.api.nvim_buf_is_loaded(self._bufnr) then
		return self._bufnr
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

--- @param models table<Model>
--- @param type "children" | "parents"
function PersistentWindow:set_models(models, type)
	if type == "parents" then
		self._parents = models
	elseif type == "children" then
		self._children = models
	else
		local error_msg = string.format("Invalid model type: %s", type)
		vim.notify(error_msg, vim.log.levels.ERROR, { title = "dbt.nvim Error" })
	end
end

--- @param section "children" | "parents"
function PersistentWindow:toggle_section(section)
	if section == "parents" then
		self._parents_collapsed = not self._parents_collapsed
	elseif section == "children" then
		self._children_collapsed = not self._children_collapsed
	else
		local error_msg = string.format("Invalid section: %s", section)
		vim.notify(error_msg, vim.log.levels.ERROR, { title = "dbt.nvim Error" })
		return
	end
	self:render_content()
end

function PersistentWindow:user_action()
	local win_cursor = vim.api.nvim_win_get_cursor(self._win)
	local current_line = win_cursor[1]
	local content = self._index_map[current_line]

	if type(content) ~= "table" or content.type == nil or content.value == nil then
		return
	end

	if content.type == "header" then
		self:toggle_section(content.value)
	end
end

--- Sets up the <CR> key binding for toggling sections.
function PersistentWindow:setup_interactions()
	-- Clear existing maps (good practice)
	vim.api.nvim_buf_clear_namespace(self._bufnr, 0, 0, -1)

	-- FIX: Use the new static handler function for cleaner keymap definition.
	-- We pass self._win (the window ID) to the static handler function.
	vim.api.nvim_buf_set_keymap(
		self._bufnr,
		"n",
		"<CR>",
		string.format('<Cmd>lua require("dbt.ui").handle_key_press(%d)<CR>', self._win),
		{ noremap = true, silent = true }
	)
end

function PersistentWindow:render_content()
	local text = {}
	local index_map = {}

	--- @param list table
	--- @param section "parents" | "children"
	--- @param data table
	--- @param collapsed boolean
	local function format_models(list, section, data, collapsed)
		table.insert(list, string.format("%s (%d)", section:gsub("^%l", string.upper), #data))
		table.insert(index_map, { type = "header", value = section })
		if data and #data > 0 and not collapsed then
			local count = #data
			for i, model in ipairs(data) do
				local connector = (i == count) and "└╴" or "├╴"
				table.insert(list, "  " .. connector .. " " .. model.name)
				table.insert(index_map, { type = "model", value = model })
			end
		end
	end

	format_models(text, "parents", self._parents, self._parents_collapsed)
	table.insert(text, "")
	table.insert(index_map, { type = "blank" })
	format_models(text, "children", self._children, self._children_collapsed)

	vim.api.nvim_set_option_value("modifiable", true, { buf = self._bufnr })
	vim.api.nvim_buf_set_lines(self._bufnr, 0, -1, true, text)
	vim.api.nvim_set_option_value("modifiable", false, { buf = self._bufnr })

	self._index_map = index_map

	self:setup_interactions()
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
	return PersistentWindow:new({ name = opts.name })
end

return ui
