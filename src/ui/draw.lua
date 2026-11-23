-- Geometric primitives, buttons, sprites, bars, footers, and shared backgrounds.
local SpriteMap = require('data.sprite_map')
local Unit = require('core.unit')
local Theme = require('ui.theme')
local Assets = require('ui.assets')
local Text = require('ui.text')

local C = Theme.C
local Draw = {}

function Draw.set(c, a)
  if not c then
    love.graphics.setColor(1, 1, 1, a or 1)
    return
  end
  love.graphics.setColor(c[1], c[2], c[3], a or 1)
end

function Draw.mix(c1, c2, t)
  return {
    c1[1] + (c2[1] - c1[1]) * t,
    c1[2] + (c2[2] - c1[2]) * t,
    c1[3] + (c2[3] - c1[3]) * t,
  }
end

function Draw.hit(r, x, y)
  return r ~= nil and x >= r.x and x <= r.x + r.w and y >= r.y and y <= r.y + r.h
end

function Draw.inside(r, x, y)
  return r ~= nil and x >= r.x and x < r.x + r.w and y >= r.y and y < r.y + r.h
end

function Draw.rect(x, y, w, h, col, alpha)
  Draw.set(col, alpha)
  love.graphics.rectangle('fill', math.floor(x), math.floor(y), math.floor(w), math.floor(h))
end

function Draw.frame(x, y, w, h, col, alpha, t)
  t = t or 1
  Draw.set(col, alpha)
  love.graphics.rectangle('fill', math.floor(x), math.floor(y), math.floor(w), t)
  love.graphics.rectangle('fill', math.floor(x), math.floor(y + h - t), math.floor(w), t)
  love.graphics.rectangle('fill', math.floor(x), math.floor(y), t, math.floor(h))
  love.graphics.rectangle('fill', math.floor(x + w - t), math.floor(y), t, math.floor(h))
end

function Draw.panel(x, y, w, h, opts)
  opts = opts or {}
  local fill = opts.fill or C.shade
  local border = opts.border or C.line
  local alpha = opts.alpha or 1
  Draw.rect(x, y, w, h, fill, (opts.fill_alpha or 1) * alpha)
  Draw.frame(x, y, w, h, border, alpha)
  if opts.ticks ~= false then
    Draw.set(border, alpha)
    local t = 3
    love.graphics.rectangle('fill', x - 1, y - 1, t, 1)
    love.graphics.rectangle('fill', x - 1, y - 1, 1, t)
    love.graphics.rectangle('fill', x + w - t + 1, y - 1, t, 1)
    love.graphics.rectangle('fill', x + w, y - 1, 1, t)
    love.graphics.rectangle('fill', x - 1, y + h, t, 1)
    love.graphics.rectangle('fill', x - 1, y + h - t + 1, 1, t)
    love.graphics.rectangle('fill', x + w - t + 1, y + h, t, 1)
    love.graphics.rectangle('fill', x + w, y + h - t + 1, 1, t)
  end
end

function Draw.hline(x, y, w, col, alpha, dash)
  if dash then
    Draw.set(col, alpha)
    for i = 0, math.floor(w / dash) - 1 do
      love.graphics.rectangle('fill', math.floor(x + i * dash), math.floor(y), math.floor(dash / 2), 1)
    end
  else
    Draw.rect(x, y, w, 1, col, alpha)
  end
end

function Draw.vline(x, y, h, col, alpha, dash)
  if dash then
    Draw.set(col, alpha)
    for i = 0, math.floor(h / dash) - 1 do
      love.graphics.rectangle('fill', math.floor(x), math.floor(y + i * dash), 1, math.floor(dash / 2))
    end
  else
    Draw.rect(x, y, 1, h, col, alpha)
  end
end

function Draw.unit(kind, cx, cy, scale, col, alpha)
  local sprite = Unit.sprite_key(kind)
  local idx = SpriteMap.unit[sprite]
  if not idx then
    return
  end
  scale = scale or 2
  Draw.set(col or C.paper, alpha)
  love.graphics.draw(Assets.unitImg, Assets.unitQuad[idx], math.floor(cx - 8 * scale), math.floor(cy - 8 * scale), 0, scale, scale)
end

function Draw.icon(name, cx, cy, scale, col, alpha)
  local idx = SpriteMap.icon[name]
  if not idx then
    return
  end
  scale = scale or 1
  Draw.set(col or C.paper, alpha)
  local x = math.floor(cx - 4 * scale)
  local y = math.floor(cy - 4 * scale)
  love.graphics.draw(Assets.iconImg, Assets.iconQuad[idx], x, y, 0, scale, scale)
end

function Draw.slot_marker(cx, y, empty, color, compact)
  if empty then
    local mark = color or C.line
    Draw.hline(cx - 5, y, 11, mark, 0.65)
    Draw.vline(cx, y - 1, 3, mark)
  end
  if color then
    local radius = compact and 12 or 20
    local left, right = cx - radius, cx + radius
    Draw.vline(left, y - 4, 5, color)
    Draw.vline(right, y - 4, 5, color)
    Draw.hline(left + 1, y, 4, color)
    Draw.hline(right - 4, y, 4, color)
  end
end

function Draw.unit_shadow(cx, foot_y, w, alpha)
  local sw = w or 18
  local sx = math.floor(cx - sw / 2)
  local y = math.floor(foot_y)
  local a = alpha or 0.6
  Draw.hline(sx, y, sw, C.line, a)
  Draw.hline(sx + 3, y + 1, sw - 6, C.line, a * 0.55)
end

function Draw.icon_text(icon, value, x, y, opts)
  opts = opts or {}
  local w = 9 + Text.width(value, 1, true)
  if opts.align == 'center' then
    x = x - w / 2
  elseif opts.align == 'right' then
    x = x - w
  end
  x = math.floor(x + 0.5)
  Draw.icon(icon, x + 4, y + 4, 1, opts.color, opts.alpha)
  Text.text(value, x + 9, y, { color = opts.color, alpha = opts.alpha, bitmap = true })
end

function Draw.unit_plate(cx, y, atk, def, opts)
  opts = opts or {}
  atk, def = atk or 0, def or 0
  local aw = 9 + Text.width(atk, 1, true)
  local dw = 9 + Text.width(def, 1, true)
  local left = math.floor(cx - (aw + dw + 4) / 2 + 0.5)
  Draw.icon_text('attack', atk, left, y, { color = opts.atk_color or C.paper, alpha = opts.alpha })
  Draw.icon_text('defense', def, left + aw + 4, y, { color = opts.def_color or C.blue, alpha = opts.alpha })
end

function Draw.button(x, y, w, h, label, state)
  state = state or {}
  local hot = (state.hover or state.focused) and not state.disabled
  local primary = state.primary and not state.disabled
  local border = (hot or primary) and C.amber or C.line
  local fill = C.shade
  if state.disabled then
    fill = C.ink
  elseif state.pressed then
    fill = C.dim
  elseif hot then
    fill = C.panel
  elseif primary then
    fill = Draw.mix(C.shade, C.amber, 0.10)
  end

  Draw.rect(x, y, w, h, fill)
  if state.progress and state.progress > 0 and not state.disabled then
    Draw.rect(x + 1, y + 1, (w - 2) * math.min(1, state.progress), h - 2, C.amber, 0.45)
  end
  Draw.frame(x, y, w, h, border)
  if hot then
    Draw.frame(x + 1, y + 1, w - 2, h - 2, border, 0.25)
  end

  local col = state.disabled and C.dim or state.color or ((hot or primary) and C.white or C.paper)
  local label_opts = { color = col, align = 'center' }
  if state.sub then
    Text.fit_text(label, x + w / 2, y + (Assets.cjk and 2 or 4), w - 8, label_opts)
    local sub = {
      color = state.disabled and C.dim or (state.sub_icon and state.color) or (hot and C.amber or C.dim),
      align = 'center',
      bitmap = true,
    }
    if state.sub_icon then
      Draw.icon_text(state.sub_icon, state.sub, x + w / 2, y + h - 9, sub)
    else
      Text.fit_text(state.sub, x + w / 2, y + h - 9, w - 8, sub)
    end
  else
    local ty = y + math.floor((h - Assets.text_h) / 2)
    Text.fit_text(label, x + w / 2, ty, w - 8, label_opts)
  end
end

function Draw.button_rect(r, label, opts, mouse)
  local state = {}
  for k, v in pairs(opts or {}) do
    state[k] = v
  end
  if mouse and state.hover == nil then
    state.hover = Draw.hit(r, mouse.x, mouse.y)
  end
  Draw.button(r.x, r.y, r.w, r.h, label, state)
end

function Draw.hearts(x, y, core, max, opts)
  opts = opts or {}
  local flash = opts.flash or 0
  local scale = opts.scale or 2
  local step = opts.step or 20
  for i = 1, max do
    local cx = x + (i - 1) * step + 8
    local cy = y + 8
    if i <= core then
      local col = C.red
      if flash > 0 and i == core then
        col = Draw.mix(C.white, C.red, 1 - flash)
      end
      Draw.icon('heart', cx, cy, scale, col)
    else
      Draw.icon('heart', cx, cy, scale, C.red_dk, 0.5)
    end
  end
end

function Draw.health_bar(x, y, w, h, hp, max, opts)
  opts = opts or {}
  max = math.max(1, math.ceil(max or 1))
  hp = math.max(0, math.min(max, hp or 0))
  if max > w * 2 then
    Text.fit_text(hp .. '/' .. max, x + w / 2, y, w, {
      color = C.red,
      alpha = opts.alpha,
      bitmap = true,
      align = 'center',
    })
    return
  end
  local per_row = math.max(1, math.floor((w + 1) / 4))
  local rows = math.min(2, math.ceil(max / per_row))
  local columns = math.ceil(max / rows)
  local height = rows > 1 and 3 or (h or 4)
  for i = 1, max do
    local col = (i - 1) % columns
    local row = math.floor((i - 1) / columns)
    local left = x + math.floor(col * w / columns)
    local right = x + math.floor((col + 1) * w / columns) - 1
    local width = math.max(1, right - left)
    if i <= hp then
      Draw.rect(left, y + row * (height + 1), width, height, C.red, opts.alpha)
    else
      Draw.frame(left, y + row * (height + 1), width, height, C.red_dk, opts.alpha)
    end
  end
end

function Draw.rarity_color(def)
  local rarity = type(def) == 'table' and def.rarity or def
  return ({ common = C.paper, rare = C.blue, epic = C.purple, legendary = C.amber })[rarity] or C.paper
end

function Draw.equipment_icon(def, x, y, scale, alpha)
  if not def then
    return
  end
  Draw.icon(def.icon or 'star', x, y, scale or 1, Draw.rarity_color(def), alpha or 1)
end

function Draw.footer(left, right)
  Draw.rect(0, Theme.FOOT_Y, Theme.W, Theme.H - Theme.FOOT_Y, C.shade, 0.55)
  Draw.hline(0, Theme.FOOT_Y, Theme.W, C.line, 0.75)
  local ty = Theme.FOOT_Y + math.floor((Theme.H - Theme.FOOT_Y - Assets.text_h) / 2)
  if left and right and Text.width(left) + Text.width(right) + 24 > Theme.W - 24 then
    Text.fit_text(left, 12, Theme.FOOT_Y + 5, Theme.W - 24, { color = C.dim })
    Text.fit_text(right, 12, Theme.FOOT_Y + (Assets.cjk and 20 or 19), Theme.W - 24, { color = C.dim })
  else
    if left then
      Text.text(left, 12, ty, { color = C.dim })
    end
    if right then
      Text.text(right, Theme.W - 12, ty, { color = C.dim, align = 'right' })
    end
  end
end

function Draw.wipe(alpha)
  Draw.rect(0, 0, Theme.W, Theme.H, C.ink, alpha)
end

function Draw.flash(alpha, col)
  Draw.rect(0, 0, Theme.W, Theme.H, col or C.white, alpha)
end

function Draw.draw_grid_bg(t, y, h)
  local slide = (t * 9) % Theme.COL_STEP
  y = y or 0
  h = h or Theme.H
  for i = -1, 7 do
    local x = Theme.COL_X0 + i * Theme.COL_STEP - slide
    Draw.vline(x, y, h, C.line, 0.05)
    Draw.vline(x + Theme.PANEL_W, y, h, C.line, 0.05)
  end
end

function Draw.ease_out(t)
  t = math.min(1, math.max(0, t))
  return 1 - (1 - t) * (1 - t)
end

return Draw
