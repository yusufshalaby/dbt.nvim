local M = {}

---@param filepath string
local function _read_json_file(filepath)
	-- Read the entire file as a string
	local file = io.open(filepath, "r")
	if not file then
		error("Could not open file: " .. filepath)
	end

	local content = file:read("*a") -- read all contents
	file:close()

	-- Decode the JSON string into a Lua table
	local ok, data = pcall(vim.json.decode, content)
	if not ok then
		error("Invalid JSON in " .. filepath)
	end

	return data
end

function M.split()
	local factory = require("dbt.ui")
	local curwin = vim.api.nvim_get_current_win()
	local manifest = _read_json_file("target/manifest.json")
	local ui = factory.new({ name = "dbt-deps", refwin = curwin, manifest = manifest })
	ui:open()
end

function M.setup(opts)
	vim.keymap.set("n", "gd", function()
		local filename = vim.fn.expand("<cfile>")

		local result = ""
		result = vim.fn.findfile(filename .. ".sql", "models/**")
		if result == "" then
			result = vim.fn.findfile(filename .. ".csv", "seeds/**")
		end

		if result ~= "" then
			vim.cmd("edit " .. result)
		else
			vim.cmd("normal! gd")
		end
	end)
end

-- Return the module
return M
