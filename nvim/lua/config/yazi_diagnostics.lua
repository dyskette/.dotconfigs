--- Forwards LSP diagnostic counts to a running yazi instance over yazi's DDS,
--- where the nvim-diag.yazi plugin renders them beside each file.
---
--- Yazi has no language server, so Neovim owns the data and pushes it in.
--- Neovim in turn only holds diagnostics an LSP client has published, which
--- for most servers means files that have been opened - browsing a large tree
--- annotates only what is in the buffer list. Roslyn is the exception in this
--- config: dotnet_analyzer_diagnostics_scope = "fullSolution" makes it report
--- across the whole solution, so C# trees are annotated in full.
local M = {}

local DIAG_KIND = "nvim-diag"
local DEBOUNCE_MS = 300

---@type string|nil Client id of the yazi instance to push to, if one is open.
local yazi_id = nil
local timer = nil

--- Error and warning counts per absolute path.
---
--- Collected across every buffer rather than per-window, so diagnostics
--- reported for files that were never opened are included too.
---@return table<string, { e: integer, w: integer }>
function M.collect()
  local files = {}

  for _, diagnostic in ipairs(vim.diagnostic.get()) do
    local bufnr = diagnostic.bufnr
    if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
      local name = vim.api.nvim_buf_get_name(bufnr)
      if name ~= "" then
        local counts = files[name] or { e = 0, w = 0 }
        if diagnostic.severity == vim.diagnostic.severity.ERROR then
          counts.e = counts.e + 1
        elseif diagnostic.severity == vim.diagnostic.severity.WARN then
          counts.w = counts.w + 1
        end
        files[name] = counts
      end
    end
  end

  return files
end

--- The DDS payload for the current diagnostics, as sent to yazi.
---
--- Each message replaces yazi's cache wholesale, so an empty set is how the
--- annotations get cleared. vim.empty_dict() keeps that encoding as a JSON
--- object; a bare table would serialize to [] and arrive as a list.
---@return string
function M.payload()
  local files = M.collect()
  if vim.tbl_isempty(files) then
    files = vim.empty_dict()
  end
  return vim.json.encode({ files = files })
end

--- Send the current diagnostics to the attached yazi, if there is one.
---
--- Safe to call from a fast event context: yazi.nvim's on_yazi_ready hook runs
--- inside a vim.system stdout handler, where the buffer API is off limits, so
--- the work is deferred to the main loop when called from there.
function M.push()
  if not yazi_id then
    return
  end

  if vim.in_fast_event() then
    vim.schedule(M.push)
    return
  end

  -- Failures are deliberately ignored: yazi may have exited between the hook
  -- firing and this call, which is not worth surfacing.
  vim.system({ "ya", "pub-to", yazi_id, DIAG_KIND, "--json", M.payload() })
end

local function schedule_push()
  if not yazi_id then
    return
  end
  if timer then
    timer:stop()
  else
    timer = vim.uv.new_timer()
  end
  timer:start(DEBOUNCE_MS, 0, vim.schedule_wrap(M.push))
end

--- Start pushing to the yazi instance with this client id.
---@param id string
function M.attach(id)
  yazi_id = id
  M.push()
end

--- Stop pushing; called when yazi exits.
function M.detach()
  yazi_id = nil
  if timer then
    timer:stop()
  end
end

function M.setup()
  vim.api.nvim_create_autocmd("DiagnosticChanged", {
    group = vim.api.nvim_create_augroup("dyskette_yazi_diagnostics", { clear = true }),
    desc = "Forward diagnostic counts to a running yazi",
    callback = schedule_push,
  })
end

return M
