-- Reload buffers when their file changes on disk: an agent in the next pane
-- edits the files open here, and the edits should show up right away for
-- review (gitsigns, diffview), not when focus happens to come back.
--
-- 'autoread' only reloads when nvim checks (:checktime), and nvim checks on
-- few events. Here it checks on focus, on entering a buffer and when idle,
-- and a file watcher per buffer checks the moment the file changes. A buffer
-- with unsaved changes is never overwritten: nvim asks (W12) instead.
local M = {}

---@type table<integer, uv.uv_fs_event_t>
local watchers = {}

local function unwatch(buf)
  local watcher = watchers[buf]
  if watcher then
    watcher:stop()
    if not watcher:is_closing() then
      watcher:close()
    end
    watchers[buf] = nil
  end
end

--- Check one buffer, when it is safe to: not while typing a command, where
--- the reload prompt would break the command line.
local function check(buf)
  if not vim.api.nvim_buf_is_valid(buf) or vim.fn.mode():match("^c") then
    return
  end
  vim.cmd.checktime(buf)
end

local function watch(buf)
  unwatch(buf)
  if vim.bo[buf].buftype ~= "" then
    return
  end
  local name = vim.api.nvim_buf_get_name(buf)
  if name == "" or not vim.uv.fs_stat(name) then
    return
  end
  local watcher = vim.uv.new_fs_event()
  if not watcher then
    return
  end
  local pending = false
  watcher:start(name, {}, function(err)
    if err or pending then
      return
    end
    -- Editors and agents often write a new file and rename it over the old
    -- one, which ends the watch; one check per burst, then watch again.
    pending = true
    vim.defer_fn(function()
      pending = false
      check(buf)
      if vim.api.nvim_buf_is_valid(buf) then
        watch(buf)
      end
    end, 150)
  end)
  watchers[buf] = watcher
end

function M.setup()
  vim.o.autoread = true
  local group = vim.api.nvim_create_augroup("config_autoreload", { clear = true })

  vim.api.nvim_create_autocmd({ "FocusGained", "BufEnter", "CursorHold", "CursorHoldI", "TermLeave" }, {
    group = group,
    callback = function(ev)
      check(ev.buf)
    end,
  })
  -- (Re)watch after reading and writing: a write may replace the file.
  vim.api.nvim_create_autocmd({ "BufReadPost", "BufWritePost", "BufFilePost" }, {
    group = group,
    callback = function(ev)
      watch(ev.buf)
    end,
  })
  vim.api.nvim_create_autocmd({ "BufDelete", "BufWipeout" }, {
    group = group,
    callback = function(ev)
      unwatch(ev.buf)
    end,
  })
  vim.api.nvim_create_autocmd("FileChangedShellPost", {
    group = group,
    callback = function(ev)
      vim.notify("Reloaded " .. vim.fn.fnamemodify(ev.file, ":."), vim.log.levels.INFO)
    end,
  })
end

return M
