local M = {}

-- ============================================================================
-- Escape Sequence Handling
-- ============================================================================

--- Unescape common escape sequences to their actual characters.
--- @param text string
--- @return string, string?
local function unescape(text)
  if #text == 0 then
    return "", nil
  end

  local result = text

  -- Common escape sequences
  result = result:gsub("\\n", "\n")   -- newline
  result = result:gsub("\\t", "\t")   -- tab
  result = result:gsub("\\r", "\r")   -- carriage return
  result = result:gsub('\\"', '"')    -- double quote
  result = result:gsub("\\'", "'")    -- single quote
  result = result:gsub("\\\\", "\\")  -- backslash (must be last)

  return result, nil
end

-- ============================================================================
-- URL Encoding/Decoding
-- ============================================================================

--- Decode URL-encoded string.
--- On failure, second return parameter will contain error message.
---
--- @param encoded string
--- @return string, string?
local function url_decode(encoded)
  if #encoded == 0 then
    return "", nil
  end

  -- This approach doesn't generate error if the string was encoded incorrectly,
  -- instead it decodes parts that can be decoded.
  return encoded:gsub("%%(%x%x)", function(hex)
    return string.char(tonumber(hex, 16))
  end), nil
end

--- Encode string using URL encoding (aka percent encoding).
---
--- @param plain string
--- @return string, string?
local function url_encode(plain)
  if #plain == 0 then
    return "", nil
  end

  -- Substitute all "unsafe" characters with their codes.
  -- See RFC3986 2.3.
  return plain:gsub("([^%w%-%.~_])", function(c)
    -- For multi-byte characters, each byte is encoded.
    local bytes = { string.byte(c, 1, #c) }
    local encoded = {}
    for _, b in ipairs(bytes) do
      table.insert(encoded, string.format("%%%02X", b))
    end
    return table.concat(encoded)
  end), nil
end

-- ============================================================================
-- Generic Selection Encoding/Decoding Functions
-- ============================================================================

--- Get text from range (either visual selection marks or command range)
--- @param line1 number Start line from command range
--- @param line2 number End line from command range
--- @return string|nil selected_text, table|nil start_pos, table|nil end_pos
local function get_range_text(line1, line2)
  -- Use the last visual selection marks '< and '>
  local start_pos = vim.fn.getpos("'<")
  local end_pos = vim.fn.getpos("'>")

  -- If command was called with a range, use that instead
  if line1 and line2 then
    start_pos[2] = line1
    end_pos[2] = line2
  end

  local lines = vim.fn.getline(start_pos[2], end_pos[2])

  if #lines == 0 then
    return nil, nil, nil
  end

  local selected_text
  if #lines == 1 then
    -- Single line: use column positions from visual marks
    selected_text = lines[1]:sub(start_pos[3], end_pos[3])
  else
    -- Multi-line: trim first and last line based on visual marks
    lines[1] = lines[1]:sub(start_pos[3])
    lines[#lines] = lines[#lines]:sub(1, end_pos[3])
    selected_text = table.concat(lines, "\n")
  end

  return selected_text, start_pos, end_pos
end

--- Replace text at the given range with new text
--- @param new_text string
--- @param start_pos table
--- @param end_pos table
local function replace_range_text(new_text, start_pos, end_pos)
  local start_line = start_pos[2]
  local start_col = start_pos[3]
  local end_line = end_pos[2]
  local end_col = end_pos[3]

  -- Clamp end_col to actual line length (handles V-line selection)
  local end_line_content = vim.fn.getline(end_line)
  if end_col > #end_line_content then
    end_col = #end_line_content
  end

  -- Use nvim_buf_set_text for precise replacement (0-indexed)
  vim.api.nvim_buf_set_text(
    0,
    start_line - 1,
    start_col - 1,
    end_line - 1,
    end_col,
    vim.split(new_text, "\n", { plain = true })
  )
end

--- Generic function to encode/decode selection
--- @param encode_fn function Function that takes a string and returns encoded/decoded string and optional error
--- @param operation_name string Name of the operation for error messages (e.g., "URL encode")
--- @param line1 number Start line from command range
--- @param line2 number End line from command range
local function transform_selection(encode_fn, operation_name, line1, line2)
  local selected_text, start_pos, end_pos = get_range_text(line1, line2)

  if not selected_text or selected_text == "" then
    vim.notify(operation_name .. " requires a selection", vim.log.levels.WARN)
    return
  end

  local result, err = encode_fn(selected_text)

  if err then
    vim.notify(operation_name .. " failed: " .. err, vim.log.levels.ERROR)
    return
  end

  replace_range_text(result, start_pos, end_pos)
  vim.notify(operation_name .. " completed", vim.log.levels.INFO)
end

-- ============================================================================
-- Public API
-- ============================================================================

--- Encode the visual selection using URL encoding
--- @param opts table Command options including line1 and line2
M.encode_url = function(opts)
  transform_selection(url_encode, "URL encode", opts.line1, opts.line2)
end

--- Decode the visual selection from URL encoding
--- @param opts table Command options including line1 and line2
M.decode_url = function(opts)
  transform_selection(url_decode, "URL decode", opts.line1, opts.line2)
end

--- Unescape common escape sequences in selection
--- @param opts table Command options including line1 and line2
M.unescape = function(opts)
  transform_selection(unescape, "Unescape", opts.line1, opts.line2)
end

-- ============================================================================
-- Setup Commands
-- ============================================================================

M.setup = function()
  -- URL encoding/decoding commands
  vim.api.nvim_create_user_command("EncodeUrl", M.encode_url, {
    range = true,
    desc = "Encode selected text using URL encoding",
  })

  vim.api.nvim_create_user_command("DecodeUrl", M.decode_url, {
    range = true,
    desc = "Decode selected text from URL encoding",
  })

  -- Unescape command
  vim.api.nvim_create_user_command("Unescape", M.unescape, {
    range = true,
    desc = "Unescape common escape sequences (\\n, \\t, \\\", etc.)",
  })
end

return M
