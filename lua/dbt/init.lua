local M = {}
local factory = require("dbt.ui")
local utils = require("dbt.utils")

function M.ui()
	local curwin = vim.api.nvim_get_current_win()
	for _, ui in pairs(factory.persistent_window_instances) do
		if ui.refwin == curwin then
			ui:dispose()
			return
		end
	end
	local manifest = utils.read_json_file("target/manifest.json")
	local name = "dbtui-" .. tostring(curwin)
	local ui = factory.new({ name = name, refwin = curwin, manifest = manifest })
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
