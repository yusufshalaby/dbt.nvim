local M = {}

function M.split()
	local factory = require("dbt.ui")
	local curwin = vim.api.nvim_get_current_win()

	local ui = factory.new({ name = "dbt-deps", refwin = curwin })
	ui:open()

end

function M.setup(opts)
	-- Merge user options with defaults
	opts = opts or {}
end

-- Return the module
return M
