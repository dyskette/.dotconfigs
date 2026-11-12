--- LSP progress ("Indexing", "Loading workspace") as one updating
--- notification per server, through snacks.notifier, which replaced
--- fidget.nvim's progress display.
local M = {}

local spinner = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }

---@type table<integer, { token: lsp.ProgressToken, msg: string, done: boolean }[]> per client id
local progress = vim.defaulttable()

--- Format one progress report as "[ 42%] Title message".
---@param value lsp.WorkDoneProgressBegin|lsp.WorkDoneProgressReport|lsp.WorkDoneProgressEnd
---@return string
local function format(value)
  local percent = value.kind == "end" and 100 or value.percentage or 100
  local message = value.message and (" " .. value.message) or ""
  return ("[%3d%%] %s%s"):format(percent, value.title or "", message)
end

--- Update the client's notification from an LspProgress event.
---@param ev { data: { client_id: integer, params: lsp.ProgressParams } }
local function on_progress(ev)
  local client = vim.lsp.get_client_by_id(ev.data.client_id)
  local value = ev.data.params.value
  if not client or type(value) ~= "table" then
    return
  end

  -- Replace this token's line, or add it.
  local tasks = progress[client.id]
  for i = 1, #tasks + 1 do
    if i == #tasks + 1 or tasks[i].token == ev.data.params.token then
      tasks[i] = { token = ev.data.params.token, msg = format(value), done = value.kind == "end" }
      break
    end
  end

  -- Every line is shown once more, finished tasks then dropped; the
  -- notification closes on its own timeout after the last one ends.
  local lines = {}
  progress[client.id] = vim.tbl_filter(function(task)
    table.insert(lines, task.msg)
    return not task.done
  end, tasks)

  vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO, {
    id = "lsp_progress_" .. client.id,
    title = client.name,
    opts = function(notif)
      notif.icon = #progress[client.id] == 0 and " "
        or spinner[math.floor(vim.uv.hrtime() / (1e6 * 80)) % #spinner + 1]
    end,
  })
end

--- Start forwarding LSP progress to vim.notify.
function M.setup()
  vim.api.nvim_create_autocmd("LspProgress", {
    group = vim.api.nvim_create_augroup("dyskette_lsp_progress", { clear = true }),
    desc = "Show LSP progress as notifications",
    callback = on_progress,
  })
end

return M
