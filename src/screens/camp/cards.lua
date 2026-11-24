-- Camp offer layout geometry and card/button drawing helpers.
local Traits = require('data.traits')
local Units = require('data.units')
local Items = require('data.items')
local Unit = require('core.unit')
local I18n = require('i18n')
local Ui = require('ui')

local T = Ui.theme
local C = Ui.C
local Text = Ui.text

local Cards = {}

Cards.HEADER_Y = T.TOP_H + 7
Cards.HEADER_H = 18
Cards.RECRUIT_Y = Cards.HEADER_Y + Cards.HEADER_H + 6
Cards.RECRUIT_H = 31
Cards.SERVICE_Y = Cards.RECRUIT_Y + Cards.RECRUIT_H + 4
Cards.SERVICE_H = 19
Cards.STOCK_Y = Cards.SERVICE_Y + Cards.SERVICE_H + 10
Cards.STOCK_H = 34

local CATEGORY_FRAMES = {
  recruit = { color = C.paper, pixels = { '###', '#..', '#..' } },
  active = { color = C.blue, pixels = { '..#', '.#.', '#..' } },
  relic = { color = C.green, pixels = { '##.', '##.', '...' } },
  trait = { color = C.purple, pixels = { '.#.', '###', '.#.' } },
  gold = { color = C.amber, pixels = { '.#.', '#.#', '.#.' } },
}

local function tr(key, ...)
  return I18n.t('shop.' .. key, ...)
end

function Cards.is_gear(o)
  return o.kind == 'relic' or o.kind == 'active'
end

function Cards.gear_defs(o)
  return o.kind == 'relic' and Items.RELICS or Items.ACTIVES
end

function Cards.offer_title(o)
  local active = o.kind == 'active' and Items.ACTIVES[o.id]
  if active and active.effect == 'shift' then
    return (I18n.is_zh() and '移位 ' or 'SHIFT ') .. active.steps
  end
  return I18n.offer_title(o)
end

function Cards.offer_row(o)
  if o.kind == 'recruit' then
    return 1
  end
  if Cards.is_gear(o) or o.kind == 'trait' then
    return 3
  end
  return 2
end

function Cards.is_rare_recruit(o)
  return o
    and o.kind == 'recruit'
    and (
      o.slot_kind == 'rare'
      or (o.slot_kind ~= 'common' and (o.rarity == 'rare' or (o.class and (Units.ALLIES[o.class] or {}).rarity == 'rare')))
    )
end

function Cards.offer_rects(offers, is_draft)
  if is_draft then
    local rects = {}
    local n = math.max(1, #offers)
    local margin, gap = 14, 8
    local w = math.floor((T.W - 2 * margin - gap * (n - 1)) / n)
    for i = 1, #offers do
      rects[i] = { x = margin + (i - 1) * (w + gap), y = 74, w = w, h = 68 }
    end
    return rects
  end
  local common_recs, rare_rec, services, stock = {}, nil, {}, {}
  local stock_widths, stock_total = {}, 0
  for i, offer in ipairs(offers) do
    local row = Cards.offer_row(offer)
    if row == 1 then
      if Cards.is_rare_recruit(offer) and not rare_rec then
        rare_rec = i
      else
        common_recs[#common_recs + 1] = i
      end
    elseif row == 2 then
      services[#services + 1] = i
    else
      stock[#stock + 1] = i
      local title = Cards.offer_title(offer)
      local widest = Ui.cjk and Text.width(title) or 0
      for word in title:gmatch('%S+') do
        widest = math.max(widest, Text.width(word))
      end
      stock_widths[i] = math.max(44, widest + 10)
      stock_total = stock_total + stock_widths[i]
    end
  end

  local margin, gap = 8, 4
  local rects = {}
  local recruits = {}
  for _, idx in ipairs(common_recs) do
    recruits[#recruits + 1] = idx
  end
  if rare_rec then
    recruits[#recruits + 1] = rare_rec
  end
  local rw = math.floor((T.W - 2 * margin + gap) / math.max(1, #recruits)) - gap
  for slot, idx in ipairs(recruits) do
    rects[idx] = { x = margin + (slot - 1) * (rw + gap), y = Cards.RECRUIT_Y, w = rw, h = Cards.RECRUIT_H }
  end

  local sw = math.floor((T.W - 2 * margin + gap) / math.max(1, #services)) - gap
  for pos, idx in ipairs(services) do
    rects[idx] = { x = margin + (pos - 1) * (sw + gap), y = Cards.SERVICE_Y, w = sw, h = Cards.SERVICE_H }
  end

  local kw = math.min(120, math.floor((T.W - 2 * margin + gap) / math.max(1, #stock)) - gap)
  local extra = (T.W - 2 * margin - gap * math.max(0, #stock - 1)) - stock_total
  local kx = margin
  for _, idx in ipairs(stock) do
    local w = kw
    if #stock > 4 and extra >= 0 then
      w = stock_widths[idx] + math.floor(extra / #stock)
    end
    rects[idx] = { x = kx, y = Cards.STOCK_Y, w = w, h = Cards.STOCK_H }
    kx = kx + w + gap
  end

  return rects
end

function Cards.offer_frame(r, kind, available, hot, selected)
  local style = CATEGORY_FRAMES[kind]
  local base = (available and style) and Ui.mix(C.line, style.color, 0.48) or C.line
  Ui.frame(r.x, r.y, r.w, r.h, (hot or selected) and C.amber or base)
  if not style then
    return
  end

  for _, dx in ipairs({ 1, -1 }) do
    for _, dy in ipairs({ 1, -1 }) do
      local x = dx == 1 and r.x - 1 or r.x + r.w
      local y = dy == 1 and r.y - 1 or r.y + r.h
      for row, pixels in ipairs(style.pixels) do
        for col = 1, #pixels do
          if pixels:sub(col, col) == '#' then
            Ui.rect(x + (col - 1) * dx, y + (row - 1) * dy, 1, 1, style.color, available and 0.9 or 0.35)
          end
        end
      end
    end
  end
end

local function draw_recruit_card(o, r, mouse)
  local d = Units.ALLIES[o.class] or {}
  local is_rare = Cards.is_rare_recruit(o)
  local rcol = is_rare and Ui.rarity_color('rare') or nil
  local hot = o.available and Ui.hit(r, mouse.x, mouse.y)
  local fill = C.shade
  if rcol and o.available then
    fill = Ui.mix(hot and C.panel or C.shade, rcol, hot and 0.22 or 0.10)
  elseif hot then
    fill = C.panel
  end
  Ui.rect(r.x, r.y, r.w, r.h, fill)
  Cards.offer_frame(r, o.kind, o.available, hot)
  if is_rare and o.available then
    Ui.rect(r.x + 1, r.y + 1, r.w - 2, 2, rcol, 0.9)
  end

  local a = o.available and 1 or 0.35
  Ui.unit_shadow(r.x + 11, r.y + 26, 10, o.available and 0.45 or 0.2)
  Ui.unit(o.class, r.x + 11, r.y + 16, 1, o.available and C.paper or C.dim, a)
  local title_y = r.y + (Ui.cjk and 5 or 6)
  Text.fit_text(I18n.unit_name(o.class), r.x + 21, title_y, r.w - 25, { color = o.available and C.white or C.dim })

  local price_x = r.x + r.w - 4
  local price_label = o.available and tostring(o.price) or tr('sold')
  local stat_right = price_x - Text.width(price_label, 1, o.available) - 4
  if is_rare then
    Ui.icon('star', stat_right - 3, r.y + 24, 1, o.available and C.blue or C.dim, a)
    stat_right = stat_right - 10
  end

  local traits = Unit.traits({ kind = o.class })
  local sx = r.x + 21
  if traits[1] then
    Ui.icon(traits[1].icon, r.x + 25, r.y + 24, 1, o.available and C.amber or C.dim, a)
    sx = r.x + 31
  end
  local stat = (d.def and d.def > 0) and (d.hp .. '/' .. d.atk .. '/' .. d.def) or ((d.hp or 0) .. '/' .. (d.atk or 0))
  if o.available then
    Text.fit_text(stat, sx, r.y + 20, stat_right - sx, { color = C.dim, bitmap = true })
  end

  local price_y = r.y + (Ui.cjk and not o.available and 18 or 20)
  Text.text(price_label, price_x, price_y, {
    align = 'right',
    color = o.available and C.amber or C.dim,
    bitmap = o.available,
  })

  local sep = I18n.is_zh() and ' · ' or ' / '
  local rlabel = is_rare and tr('rarity_rare') or tr('rarity_common')
  local stats_line = I18n.t('shop.recruit_stats', d.hp or 0, d.atk or 0, d.def or 0)
  Ui.tooltip.register(r, I18n.offer_title(o), { rlabel .. sep .. stats_line, I18n.unit_blurb({ kind = o.class, hp = d.hp }) })
end

function Cards.draw_draft_offer(o, r, mouse)
  local def = Cards.is_gear(o) and Cards.gear_defs(o)[o.id]
  local trait = o.kind == 'trait' and Traits.definitions[o.id]
  local rarity = def or o.rarity
  local rcol = (rarity and Ui.rarity_color(rarity))
    or (o.kind == 'gold' and C.amber)
    or (o.kind == 'upgrade' and C.blue)
    or nil
  local hot = o.available and Ui.hit(r, mouse.x, mouse.y)
  local fill = C.shade
  if rcol and o.available then
    fill = Ui.mix(hot and C.panel or C.shade, rcol, hot and 0.16 or 0.08)
  elseif hot then
    fill = C.panel
  end

  Ui.rect(r.x, r.y, r.w, r.h, fill)
  Cards.offer_frame(r, o.kind, o.available, hot)
  if rcol then
    Ui.rect(r.x + 1, r.y + 1, r.w - 2, 3, rcol, o.available and 0.92 or 0.25)
    Ui.hline(r.x + 1, r.y + 4, r.w - 2, C.ink, 0.75)
  end

  local a = o.available and 1 or 0.35
  local cx = r.x + r.w / 2
  if o.kind == 'recruit' then
    Ui.unit_shadow(cx, r.y + 27, 12, o.available and 0.45 or 0.2)
    Ui.unit(o.class, cx, r.y + 17, 1, o.available and C.paper or C.dim, a)
  elseif def then
    Ui.equipment_icon(def, cx, r.y + 18, 1, a)
  elseif trait then
    Ui.icon(trait.icon, cx, r.y + 18, 1, C.amber, a)
  elseif o.kind == 'gold' then
    Ui.icon('coin', cx, r.y + 18, 1, C.amber, a)
  elseif o.kind == 'upgrade' then
    local ic = o.mode == 'atk' and 'attack' or (o.mode == 'hp' and 'heart' or 'guard')
    Ui.icon(ic, cx, r.y + 18, 1, C.blue, a)
  end

  local title = Cards.offer_title(o)
  local detail = I18n.offer_detail(o)
  Text.fit_text(title, cx, r.y + 29, r.w - 10, { align = 'center', color = o.available and C.white or C.dim })
  Text.wrap_text(detail, r.x + 6, r.y + 42, r.w - 12, {
    color = o.available and C.paper or C.dim,
    max_lines = 2,
    line_h = Ui.cjk and 11 or 8,
  })
  Ui.tooltip.register(r, title, detail)
end

function Cards.draw_offer(o, r, mouse)
  if o.kind == 'recruit' then
    draw_recruit_card(o, r, mouse)
    return
  end

  local def = Cards.is_gear(o) and Cards.gear_defs(o)[o.id]
  local trait = o.kind == 'trait' and Traits.definitions[o.id]
  local rarity = def or o.rarity
  local rcol = rarity and Ui.rarity_color(rarity)
  local hot = o.available and Ui.hit(r, mouse.x, mouse.y)
  local fill = C.shade
  if rcol and o.available then
    fill = Ui.mix(hot and C.panel or C.shade, rcol, hot and 0.14 or 0.06)
  elseif hot then
    fill = C.panel
  end

  Ui.rect(r.x, r.y, r.w, r.h, fill)
  Cards.offer_frame(r, o.kind, o.available, hot)
  if rcol then
    local bar_a = o.available and 0.92 or 0.25
    Ui.rect(r.x + 1, r.y + 1, r.w - 2, 3, rcol, bar_a)
    if o.available then
      Ui.hline(r.x + 1, r.y + 1, r.w - 2, Ui.mix(rcol, C.white, 0.28), 0.9)
    end
    Ui.hline(r.x + 1, r.y + 4, r.w - 2, C.ink, 0.75)
  end

  local title = Cards.offer_title(o)
  local detail = I18n.offer_detail(o)

  if Cards.offer_row(o) == 2 then
    local stat = o.kind == 'upgrade' and (({ atk = 'ATK+1', hp = 'HP+3', def = 'DEF+1' })[o.mode] or '')
      or (o.kind == 'swap' and (o.free and 'FREE' or (not I18n.is_zh() and 'MOVE' or '')))
      or (o.kind == 'dismiss' and (not I18n.is_zh() and '-1 UNIT' or ''))
      or ''
    local label = o.available and (o.price < 0 and '+1' or tostring(o.price)) or tr('sold')
    local label_x = r.x + r.w - 4
    local label_color = o.available and (o.free and C.green or C.amber) or C.dim
    local title_y = r.y + math.floor((r.h - Ui.text_h) / 2)
    local detail_x = label_x - Text.width(label, 1, o.available) - 4
    if o.available and stat ~= '' and Text.width(title) + Text.width(stat, 1, true) + 8 <= detail_x - r.x then
      Text.text(stat, detail_x, r.y + 6, { align = 'right', color = C.dim, bitmap = true })
      detail_x = detail_x - Text.width(stat, 1, true) - 4
    end
    Text.fit_text(title, r.x + 4, title_y, detail_x - r.x - 4, { color = o.available and C.white or C.dim })
    Text.text(label, label_x, o.available and r.y + 6 or title_y, {
      align = 'right',
      color = label_color,
      bitmap = o.available,
    })
    Ui.tooltip.register(r, I18n.offer_title(o), detail)
    return
  end

  local line_h = Ui.cjk and 11 or 8
  local lines = Ui.cjk and 1 or 2
  Text.wrap_text(title, r.x + 5, r.y + 6, r.w - 10, {
    color = o.available and C.white or C.dim,
    max_lines = lines,
    line_h = line_h,
  })

  local sep = I18n.is_zh() and ' · ' or ' / '
  if def then
    detail = { tr(o.kind == 'relic' and 'passive' or 'active') .. sep .. tr('rarity_' .. (def.rarity or 'common')), detail }
    Ui.equipment_icon(def, r.x + 9, r.y + r.h - 6, 1, o.available and 1 or 0.35)
  elseif trait then
    detail = { tr('trait') .. sep .. tr('rarity_' .. (o.rarity or trait.rarity or 'common')), detail }
    Ui.icon(trait.icon, r.x + 9, r.y + r.h - 6, 1, C.amber, o.available and 1 or 0.35)
  end
  Ui.tooltip.register(r, I18n.offer_title(o), detail)

  if o.available then
    local price_label = o.price < 0 and '+1' or (o.free and '0' or o.price)
    local price_col = o.free and C.green or C.amber
    Text.text(price_label, r.x + r.w - 5, r.y + r.h - 10, { align = 'right', color = price_col, bitmap = true })
  else
    Text.text(tr('sold'), r.x + r.w - 5, r.y + r.h - Ui.text_h - 3, { align = 'right', color = C.dim })
  end
end

function Cards.draw_charge_button(r, label, cost, disabled, mouse, tip_body)
  local hot = not disabled and Ui.hit(r, mouse.x, mouse.y)
  Ui.button(r.x, r.y, r.w, r.h, '', { disabled = disabled, hover = hot })
  local lcol = disabled and C.dim or (hot and C.white or C.paper)
  local bcol = disabled and C.dim or C.blue
  Text.fit_text(label, r.x + 4, r.y + math.floor((r.h - Ui.text_h) / 2), r.w - 24, { color = lcol })
  Ui.icon_text('charge', cost, r.x + r.w - 4, r.y + 7, { align = 'right', color = bcol })
  if tip_body then
    Ui.tooltip.register(r, label, tip_body, { icon = 'charge', icon_color = C.blue, color = C.blue })
  end
end

return Cards
