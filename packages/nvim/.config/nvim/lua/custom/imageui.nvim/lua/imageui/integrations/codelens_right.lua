local M = {}

local namespace = vim.api.nvim_create_namespace('imageui.nvim:codelens:right')
local enabled = false
local redraw_pending = {}
local states
local config

---@param spans table[]
---@return table[]
local function chunks_for(spans)
  local chunks = {}
  for _, span in ipairs(spans) do
    chunks[#chunks + 1] = { span.text, span.highlight }
  end
  return chunks
end

---@param spans table[]
---@return integer
local function spans_width(spans)
  local width = 0
  for _, span in ipairs(spans) do
    width = width + vim.fn.strdisplaywidth(span.text)
  end
  return width
end

---@param win integer
---@return integer, integer
local function text_area(win)
  local info = vim.fn.getwininfo(win)[1]
  local textoff = info and info.textoff or 0
  local leftcol = info and info.leftcol or 0
  return math.max(1, vim.api.nvim_win_get_width(win) - textoff), leftcol
end

---@param win integer
---@param width integer
---@param distance integer
---@param side 'before'|'after'
---@return integer?, string?
local function colorcolumn_start(win, width, distance, side)
  local value = vim.wo[win].colorcolumn
  local bufnr = vim.api.nvim_win_get_buf(win)
  local textwidth = vim.bo[bufnr].textwidth
  local available, leftcol = text_area(win)
  local saw_column = false

  for item in value:gmatch('[^,]+') do
    local column
    if item:match('^[+-]%d+$') then
      if textwidth > 0 then
        column = textwidth + tonumber(item)
      end
    elseif item:match('^%d+$') then
      column = tonumber(item)
    end
    if column and column > 0 then
      saw_column = true
      column = column - leftcol
      -- colorcolumn is one-based. virt_text_win_col is zero-based. Keep
      -- `distance` untouched cells between the label and the guide.
      local start = side == 'after' and column + distance or column - 1 - distance - width
      if start >= 0 and start + width <= available then
        return start
      end
    end
  end

  return nil, saw_column and 'colorcolumn_has_no_room' or 'colorcolumn_unset'
end

---@param win integer
---@param spans table[]
---@param right_config table
---@return table, table
function M.resolve(win, spans, right_config)
  local chunks = chunks_for(spans)
  local metadata = {
    requested_anchor = right_config.anchor,
    anchor = right_config.anchor,
    side = right_config.side,
    distance = right_config.distance,
  }
  local opts = {
    ephemeral = true,
    hl_mode = 'combine',
    priority = 90,
    virt_text = chunks,
  }

  if right_config.anchor == 'colorcolumn' then
    local start, reason =
      colorcolumn_start(win, spans_width(spans), right_config.distance, right_config.side)
    if start then
      opts.virt_text_win_col = start
      metadata.win_col = start
      return opts, metadata
    end
    metadata.anchor = 'window'
    metadata.fallback_reason = reason
  end

  if right_config.distance > 0 then
    chunks[#chunks + 1] = { string.rep(' ', right_config.distance) }
  end
  opts.virt_text_pos = 'eol_right_align'
  return opts, metadata
end

---@param bufnr integer
function M.redraw(bufnr)
  if not enabled or redraw_pending[bufnr] then
    return
  end
  redraw_pending[bufnr] = true
  vim.schedule(function()
    redraw_pending[bufnr] = nil
    if enabled and vim.api.nvim_buf_is_valid(bufnr) then
      pcall(vim.api.nvim__redraw, { buf = bufnr, valid = false })
    end
  end)
end

---@param opts table
function M.enable(opts)
  if enabled then
    return
  end
  enabled = true
  states = opts.states
  config = opts.config
  vim.api.nvim_set_decoration_provider(namespace, {
    on_win = function(_, win, bufnr, topline, botline)
      local state = states()[bufnr]
      local right_config = config()
      if not state or not right_config then
        return false
      end

      state.right_windows = state.right_windows or {}
      state.right_windows[win] = {}
      -- Iterate visible rows instead of every lens in the buffer. This runs
      -- inside Neovim's redraw phase, so work here directly affects input
      -- latency during key repeat.
      for row = topline, botline do
        local entry = state.entries[row]
        if entry then
          local visible = right_config.always
            or entry.mode == 'right'
            or state.fallback_modes[row] == 'right'
          if visible then
            local extmark_opts, metadata = M.resolve(win, entry.spans, right_config)
            local ok, err =
              pcall(vim.api.nvim_buf_set_extmark, bufnr, namespace, row, 0, extmark_opts)
            if ok then
              state.right_windows[win][row] = metadata
            else
              state.right_windows[win][row] = { error = tostring(err) }
            end
          end
        end
      end
      return false
    end,
  })
end

function M.disable()
  enabled = false
  redraw_pending = {}
  states = nil
  config = nil
  pcall(vim.api.nvim_set_decoration_provider, namespace, {})
end

---@return integer
function M.namespace()
  return namespace
end

return M
