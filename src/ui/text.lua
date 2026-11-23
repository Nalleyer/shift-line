-- Deterministic UTF-8 measurement, wrapping, fitting, and bitmap/CJK text rendering.
local FontMap = require('data.font_map')
local Theme = require('ui.theme')
local Assets = require('ui.assets')

local C = Theme.C
local Text = {}

local NO_LINE_START = {
  ['，'] = true, ['。'] = true, ['、'] = true, ['；'] = true, ['：'] = true,
  ['！'] = true, ['？'] = true, ['）'] = true, ['】'] = true, ['》'] = true,
  ['」'] = true, ['』'] = true, ['…'] = true, ['·'] = true,
  [','] = true, ['.'] = true, [':'] = true, [';'] = true, ['!'] = true,
  ['?'] = true, [')'] = true, [']'] = true, ['}'] = true, ['%'] = true,
}

local NO_LINE_END = {
  ['（'] = true, ['【'] = true, ['《'] = true, ['「'] = true, ['『'] = true,
  ['('] = true, ['['] = true, ['{'] = true,
}

local function set_color(c, a)
  if not c then
    love.graphics.setColor(1, 1, 1, a or 1)
    return
  end
  love.graphics.setColor(c[1], c[2], c[3], a or 1)
end

-- UTF-8 decoded manually so measurement/wrapping also runs under LuaJIT without utf8 stdlib.
function Text.chars(s)
  local out = {}
  local i, n = 1, #s
  while i <= n do
    local b = s:byte(i)
    local len = 1
    if b >= 240 then
      len = 4
    elseif b >= 224 then
      len = 3
    elseif b >= 192 then
      len = 2
    end
    out[#out + 1] = s:sub(i, i + len - 1)
    i = i + len
  end
  return out
end

-- Fusion Pixel 12px is monospaced: ASCII advances 6px, all other glyphs 12px.
function Text.cjk_px(s)
  local px, i, n = 0, 1, #s
  while i <= n do
    local b = s:byte(i)
    if b < 128 then
      px = px + 6
      i = i + 1
    else
      px = px + 12
      i = i + 1
      while i <= n do
        local c = s:byte(i)
        if c < 128 or c >= 192 then
          break
        end
        i = i + 1
      end
    end
  end
  return px
end

function Text.width(s, scale, bitmap)
  scale = scale or 1
  s = tostring(s)
  if #s == 0 then
    return 0
  end
  if Assets.cjk and not bitmap then
    return Text.cjk_px(s) * scale
  end
  return (#s * FontMap.cell_w - 1) * scale
end

function Text.ascii(str)
  local ok = true
  for i = 1, #str do
    local b = str:byte(i)
    if b < 32 or b > 126 then
      ok = false
      break
    end
  end
  if ok then
    return str
  end
  local out = {}
  for i = 1, #str do
    local b = str:byte(i)
    out[#out + 1] = (b >= 32 and b <= 126) and str:sub(i, i) or '?'
  end
  return table.concat(out)
end

function Text.raw_text(s, x, y, scale, col, alpha, bitmap)
  if Assets.cjk and not bitmap then
    if not Assets.cjkFont then
      return
    end
    set_color(col, alpha)
    local previous = love.graphics.getFont()
    love.graphics.setFont(Assets.cjkFont)
    love.graphics.print(s, x, y - scale, 0, scale, scale)
    love.graphics.setFont(previous)
    return
  end
  set_color(col, alpha)
  local dx = x
  for i = 1, #s do
    local idx = FontMap.chars:find(s:sub(i, i), 1, true)
    if idx then
      love.graphics.draw(Assets.fontImg, Assets.fontQuad[idx], dx, y, 0, scale, scale)
    end
    dx = dx + FontMap.cell_w * scale
  end
end

function Text.text(s, x, y, opts)
  opts = opts or {}
  local scale = opts.scale or 1
  local col = opts.color or C.paper
  local alpha = opts.alpha or 1
  s = tostring(s)
  if #s == 0 then
    return
  end

  local use_bitmap = (not Assets.cjk) or opts.bitmap
  if use_bitmap then
    s = Text.ascii(s:upper())
  end

  local w = use_bitmap and ((#s * FontMap.cell_w - 1) * scale) or Text.width(s, scale)
  local dx = x
  if opts.align == 'center' then
    dx = x - w / 2
  elseif opts.align == 'right' then
    dx = x - w
  end
  dx = math.floor(dx + 0.5)
  y = math.floor(y + 0.5)

  if opts.shadow then
    Text.raw_text(s, dx + scale, y + scale, scale, opts.shadow, (opts.shadow_alpha or 1) * alpha, use_bitmap)
  end
  Text.raw_text(s, dx, y, scale, col, alpha, use_bitmap)
end

function Text.text_outlined(s, x, y, opts)
  opts = opts or {}
  local ol = opts.outline or C.ink
  local scale = opts.scale or 1
  local alpha = opts.alpha or 1
  for _, d in ipairs({ { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 }, { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } }) do
    Text.text(s, x + d[1] * scale, y + d[2] * scale, {
      color = ol,
      scale = scale,
      align = opts.align,
      alpha = alpha,
      bitmap = opts.bitmap,
    })
  end
  Text.text(s, x, y, {
    color = opts.color,
    scale = scale,
    align = opts.align,
    alpha = alpha,
    bitmap = opts.bitmap,
  })
end

function Text.fit_text(s, x, y, width, opts)
  opts = opts or {}
  s = tostring(s)
  local scale = opts.scale or 1
  if #s == 0 or Text.width(s, scale, opts.bitmap) <= width then
    Text.text(s, x, y, opts)
    return s
  end
  local ell = '...'
  while ell ~= '' and Text.width(ell, scale, opts.bitmap) > width do
    ell = ell:sub(1, -2)
  end
  local budget = width - Text.width(ell, scale, opts.bitmap)
  local out = ''
  for _, ch in ipairs(Text.chars(s)) do
    if Text.width(out .. ch, scale, opts.bitmap) > budget then
      break
    end
    out = out .. ch
  end
  out = out .. ell
  Text.text(out, x, y, opts)
  return out
end

local function wrap_latin(s, width, scale)
  local cap = math.max(1, math.floor((width + 1) / (FontMap.cell_w * scale)))
  local lines = {}
  for para in (s .. '\n'):gmatch('(.-)\n') do
    local line = ''
    for word in para:gmatch('%S+') do
      if #line > 0 and #line + #word + 1 > cap then
        lines[#lines + 1] = line
        line = ''
      end
      while #word > cap do
        if #line > 0 then
          lines[#lines + 1] = line
          line = ''
        end
        lines[#lines + 1] = word:sub(1, cap)
        word = word:sub(cap + 1)
      end
      if #word > 0 then
        line = #line > 0 and (line .. ' ' .. word) or word
      end
    end
    lines[#lines + 1] = line
  end
  return lines
end

local function tokenize_cjk(para)
  local tokens = {}
  local i, n = 1, #para
  while i <= n do
    local b = para:byte(i)
    if b == 32 or b == 9 then
      local j = i
      while j <= n and (para:byte(j) == 32 or para:byte(j) == 9) do
        j = j + 1
      end
      tokens[#tokens + 1] = para:sub(i, j - 1)
      i = j
    elseif b < 128 then
      local j = i
      while j <= n do
        local c = para:byte(j)
        if c == 32 or c == 9 or c >= 128 then
          break
        end
        j = j + 1
      end
      tokens[#tokens + 1] = para:sub(i, j - 1)
      i = j
    else
      local len = 1
      if b >= 240 then
        len = 4
      elseif b >= 224 then
        len = 3
      elseif b >= 192 then
        len = 2
      end
      tokens[#tokens + 1] = para:sub(i, i + len - 1)
      i = i + len
    end
  end
  return tokens
end

local function last_char(s)
  local chars = Text.chars(s)
  return chars[#chars] or ''
end

local function drop_last_char(s)
  local chars = Text.chars(s)
  table.remove(chars)
  return table.concat(chars)
end

local function split_long_token(token, width, scale)
  local pieces, piece = {}, ''
  for _, ch in ipairs(Text.chars(token)) do
    if piece ~= '' and Text.width(piece .. ch, scale) > width then
      pieces[#pieces + 1] = piece
      piece = ch
    else
      piece = piece .. ch
    end
  end
  pieces[#pieces + 1] = piece
  return pieces
end

local function wrap_cjk(s, width, scale)
  local lines = {}
  for para in (s .. '\n'):gmatch('(.-)\n') do
    local line = ''
    local function flush()
      lines[#lines + 1] = line
      line = ''
    end
    for _, token in ipairs(tokenize_cjk(para)) do
      if token:match('^%s+$') then
        if line ~= '' and not line:match('%s$') and Text.width(line .. ' ', scale) <= width then
          line = line .. ' '
        end
      else
        local pieces = { token }
        if Text.width(token, scale) > width and not NO_LINE_START[token] then
          pieces = split_long_token(token, width, scale)
        end
        for _, piece in ipairs(pieces) do
          if line == '' then
            line = piece
          elseif Text.width(line .. piece, scale) <= width then
            line = line .. piece
          elseif NO_LINE_START[piece] and line ~= '' then
            local carry = last_char(line)
            line = drop_last_char(line)
            if line ~= '' then
              flush()
            end
            line = carry .. piece
          elseif NO_LINE_END[last_char(line)] then
            local carry = last_char(line)
            line = drop_last_char(line)
            flush()
            line = carry .. piece
          else
            flush()
            line = piece
          end
        end
      end
    end
    flush()
  end
  return lines
end

function Text.wrap_lines(s, width, opts)
  opts = opts or {}
  local scale = opts.scale or 1
  s = tostring(s)
  local lines = Assets.cjk and wrap_cjk(s, width, scale) or wrap_latin(s, width, scale)
  if opts.max_lines and #lines > opts.max_lines then
    while #lines > opts.max_lines do
      table.remove(lines)
    end
    local last = lines[#lines] or ''
    while #last > 0 and Text.width(last .. '...', scale) > width do
      last = drop_last_char(last)
    end
    lines[#lines] = last .. '...'
  end
  return lines
end

function Text.wrap_text(s, x, y, width, opts)
  opts = opts or {}
  local scale = opts.scale or 1
  local line_h = opts.line_h or Assets.line_h * scale
  for _, line in ipairs(Text.wrap_lines(s, width, opts)) do
    Text.text(line, x, y, opts)
    y = y + line_h
  end
  return y
end

return Text
