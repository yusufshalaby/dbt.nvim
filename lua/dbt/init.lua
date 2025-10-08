local M = {}

function M.split()
	local factory = require("dbt.ui")
	local curwin = vim.api.nvim_get_current_win()

	local ui = factory.new({ name = "dbt-deps", refwin = curwin })
	ui:open()

	vim.api.nvim_create_augroup("whatever", { clear = true })
	vim.api.nvim_create_autocmd({ "BufWinEnter", "BufEnter" }, {
		group = "whatever",
		pattern = "*",
		callback = function(args)
			if not ui._win or not vim.api.nvim_win_is_valid(ui._win) then
				return
			end
			local win = vim.api.nvim_get_current_win()
			if win == curwin then
				ui:update()
			end
		end,
	})
end

function M.setup(opts)
	-- Merge user options with defaults
	opts = opts or {}
end

-- Return the module
return M
