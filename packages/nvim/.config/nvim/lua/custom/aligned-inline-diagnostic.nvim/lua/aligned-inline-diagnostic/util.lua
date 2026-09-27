local M = {}

local severity = vim.diagnostic.severity

local severity_names = {
  [severity.ERROR] = "Error",
  [severity.WARN] = "Warning",
  [severity.INFO] = "Info",
  [severity.HINT] = "Hint",
}

local severity_keys = {
  [severity.ERROR] = "Error",
  [severity.WARN] = "Warn",
  [severity.INFO] = "Info",
  [severity.HINT] = "Hint",
}

function M.display_width(text, start_column)
  if start_column ~= nil then
    return vim.fn.strdisplaywidth(text or "", start_column)
  end
  return vim.fn.strdisplaywidth(text or "")
end

function M.severity_name(value)
  return severity_names[value] or "Error"
end

function M.severity_key(value)
  return severity_keys[value] or "Error"
end

function M.icon_key(value)
  return M.severity_key(value):lower()
end

function M.hover_structural_width(config)
  local options = config.hover
  local icons = config.icons
  local cap_width = options.cap_style == "none" and 0
    or (M.display_width(icons.left) + M.display_width(icons.right))
  local lane_width = 0
  for _, key in ipairs({
    "error",
    "warn",
    "info",
    "hint",
    "branch",
    "continuation",
    "last",
    "related",
  }) do
    lane_width = math.max(lane_width, M.display_width(icons[key]))
  end
  -- One separator cell and at least two cells of message content.
  return cap_width + options.padding_left + options.padding_right + lane_width + 3
end

function M.collapse(text)
  return vim.trim((text or ""):gsub("[\r\n]+", " "):gsub("%s+", " "))
end

-- Returns the longest prefix that fits in `max_width` display cells and the
-- remaining suffix. This is character-safe for UTF-8 and wide glyphs.
function M.cut_cells(text, max_width)
  if max_width <= 0 or text == "" then
    return "", text
  end
  if M.display_width(text) <= max_width then
    return text, ""
  end

  local count = vim.fn.strchars(text)
  local accepted = 0
  local width = 0
  for index = 0, count - 1 do
    local character = vim.fn.strcharpart(text, index, 1)
    local character_width = M.display_width(character, width)
    if width + character_width > max_width then
      break
    end
    width = width + character_width
    accepted = index + 1
  end

  if accepted == 0 then
    -- Always make progress even when one glyph is wider than the requested
    -- width. Neovim will render that glyph in its natural width.
    accepted = 1
  end

  return vim.fn.strcharpart(text, 0, accepted), vim.fn.strcharpart(text, accepted)
end

function M.truncate(text, max_width, ellipsis)
  text = text or ""
  ellipsis = ellipsis or "…"
  if M.display_width(text) <= max_width then
    return text
  end

  local ellipsis_width = M.display_width(ellipsis)
  if ellipsis_width >= max_width then
    local clipped = M.cut_cells(ellipsis, max_width)
    return clipped
  end

  local prefix = M.cut_cells(text, max_width - ellipsis_width)
  return prefix .. ellipsis
end

local function push_long_word(lines, current, word, width)
  if current ~= "" then
    table.insert(lines, current)
    current = ""
  end

  while M.display_width(word) > width do
    local part
    part, word = M.cut_cells(word, width)
    table.insert(lines, part)
  end

  return word
end

local function balance_last_pair(lines, width)
  if #lines < 2 then
    return
  end
  local previous = lines[#lines - 1]
  local final = lines[#lines]
  if previous:find("%s") == nil and final:find("%s") == nil then
    return
  end

  local words = {}
  for word in (previous .. " " .. final):gmatch("%S+") do
    table.insert(words, word)
  end
  if #words < 3 then
    return
  end

  local best_left = previous
  local best_right = final
  local best_score = math.abs(M.display_width(previous) - M.display_width(final))
  for split = 1, #words - 1 do
    local left = table.concat(words, " ", 1, split)
    local right = table.concat(words, " ", split + 1)
    local left_width = M.display_width(left)
    local right_width = M.display_width(right)
    if left_width <= width and right_width <= width then
      local score = math.abs(left_width - right_width)
      if #words - split == 1 then
        score = score + math.floor(width / 3)
      end
      if score < best_score then
        best_left = left
        best_right = right
        best_score = score
      end
    end
  end
  lines[#lines - 1] = best_left
  lines[#lines] = best_right
end

local function wrap_paragraph(paragraph, width, mode)
  paragraph = vim.trim(paragraph)
  if paragraph == "" then
    return { "" }
  end

  local lines = {}
  local current = ""
  for word in paragraph:gmatch("%S+") do
    if M.display_width(word) > width then
      current = push_long_word(lines, current, word, width)
    elseif current == "" then
      current = word
    elseif M.display_width(current .. " " .. word) <= width then
      current = current .. " " .. word
    else
      table.insert(lines, current)
      current = word
    end
  end

  if current ~= "" then
    table.insert(lines, current)
  end
  if mode == "balanced" then
    balance_last_pair(lines, width)
  end
  return lines
end

function M.wrap(text, width, mode)
  width = math.max(1, width)
  local result = {}
  local paragraphs = vim.split((text or ""):gsub("\r", ""), "\n", {
    plain = true,
    trimempty = false,
  })

  for _, paragraph in ipairs(paragraphs) do
    vim.list_extend(result, wrap_paragraph(paragraph, width, mode))
  end

  if #result == 0 then
    return { "" }
  end
  return result
end

function M.sort_diagnostics(diagnostics)
  local copy = {}
  for index, diagnostic in ipairs(diagnostics or {}) do
    table.insert(copy, { diagnostic = diagnostic, index = index })
  end

  table.sort(copy, function(left, right)
    local a = left.diagnostic
    local b = right.diagnostic
    local a_severity = a.severity or severity.ERROR
    local b_severity = b.severity or severity.ERROR
    if a_severity ~= b_severity then
      return a_severity < b_severity
    end
    if (a.col or 0) ~= (b.col or 0) then
      return (a.col or 0) < (b.col or 0)
    end
    return left.index < right.index
  end)

  local result = {}
  for _, item in ipairs(copy) do
    table.insert(result, item.diagnostic)
  end
  return result
end

function M.is_disabled_filetype(filetype, disabled)
  for _, value in ipairs(disabled or {}) do
    if value == filetype then
      return true
    end
  end
  return false
end

return M
