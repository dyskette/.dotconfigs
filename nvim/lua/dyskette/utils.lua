local utils = {}

function utils.has_plugin(plugin)
	return require("lazy.core.config").plugins[plugin] ~= nil
end

---@param bufnr number
---@return integer|nil size in bytes if buffer is valid, nil otherwise
local get_buf_size = function(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	local ok, stat = pcall(function()
		return vim.loop.fs_stat(vim.api.nvim_buf_get_name(bufnr))
	end)

	if not (ok and stat) then
		return
	end

	return stat.size
end

---@param bufnr number
---@return integer|nil line_count number of lines in the buffer if valid, nil otherwise
local function get_buf_line_count(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	local ok, line_count = pcall(function()
		return vim.api.nvim_buf_line_count(bufnr)
	end)
	if not (ok and line_count) then
		return
	end
	return line_count
end

local max_bytes_per_line = 5000

---Determine if file looks to be minifed. Criteria is a large file with few lines
---@param bufnr number
---@return boolean
function utils.check_file_minified(bufnr)
	local filesize = get_buf_size(bufnr) or 0
	local line_count = get_buf_line_count(bufnr) or 0

	return filesize / line_count > max_bytes_per_line
end

return utils
