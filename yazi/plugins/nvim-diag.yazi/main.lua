-- Renders LSP diagnostic counts pushed in from Neovim.
--
-- Yazi has no language server of its own, so Neovim owns the data and this
-- plugin only caches and draws it. Payload, sent by yazi.nvim's on_yazi_ready
-- hook and on every DiagnosticChanged:
--
--   ya pub-to <client-id> nvim-diag --json '{"files":{"/abs/path":{"e":2,"w":1}}}'
--
-- Each message replaces the cache wholesale, so Neovim clears the annotations
-- by sending an empty set rather than by a separate command.
--
-- Note that subscribing is what grants this instance the ability to receive
-- the `nvim-diag` kind at all: without a live ps.sub_remote, yazi rejects the
-- message with "does not have the ability to receive".

local M = {}

local ERROR_SIGN = ""
local WARN_SIGN = ""

function M:setup(opts)
	opts = opts or {}

	local st = self
	st.files = {}
	st.error_style = th.nvim_diag and th.nvim_diag.error or ui.Style():fg("red")
	st.warn_style = th.nvim_diag and th.nvim_diag.warn or ui.Style():fg("yellow")

	ps.sub_remote("nvim-diag", function(body)
		st.files = (body and body.files) or {}
		-- ui.render(), not ya.render(): the latter updates the cache without
		-- repainting, so a push stayed invisible until some unrelated event
		-- redrew the list.
		ui.render()
	end)

	Linemode:children_add(function(self)
		local counts = st.files[tostring(self._file.url)]
		if not counts then
			return ""
		end

		local spans = {}
		if (counts.e or 0) > 0 then
			spans[#spans + 1] = ui.Span(string.format(" %s%d", ERROR_SIGN, counts.e)):style(st.error_style)
		end
		if (counts.w or 0) > 0 then
			spans[#spans + 1] = ui.Span(string.format(" %s%d", WARN_SIGN, counts.w)):style(st.warn_style)
		end

		if #spans == 0 then
			return ""
		end
		return ui.Line(spans)
	end, opts.order or 1600)
end

return M
