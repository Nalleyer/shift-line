-- Camp sub-views: main shop view, confirmation/swap, item use, and gear selling.
local Constants = require('data.constants')
local Traits = require('data.traits')
local Units = require('data.units')
local Items = require('data.items')
local Unit = require('core.unit')
local I18n = require('i18n')
local Ui = require('ui')
local Cards = require('screens.camp.cards')

local T = Ui.theme
local C = Ui.C
local Text = Ui.text

local Views = {}

Views.ROSTER_Y = 161
Views.CAMP_FOOT_Y = 278
Views.CAMP_BUTTON_Y = 250

Views.MAP_BTN = { x = 296, y = Cards.HEADER_Y, w = 80, h = Cards.HEADER_H }
Views.SELL_BTN = { x = 8, y = Views.CAMP_BUTTON_Y, w = 84, h = 20 }
Views.REROLL_BTN = { x = 96, y = Views.CAMP_BUTTON_Y, w = 62, h = 20 }
Views.ADJUST_BTN = { x = 161, y = Views.CAMP_BUTTON_Y, w = 62, h = 20 }
Views.TRIAGE_BTN = { x = 226, y = Views.CAMP_BUTTON_Y, w = 62, h = 20 }
Views.LEAVE_BTN = { x = 292, y = Views.CAMP_BUTTON_Y, w = 84, h = 20 }
Views.BACK_BTN = { x = 59, y = 227, w = 118, h = 22 }
Views.CONFIRM_BTN = { x = 207, y = 227, w = 118, h = 22 }

local function tr(key, ...)
  return I18n.t('shop.' .. key, ...)
end

function Views.roster_rect(i)
  return { x = T.col_x(i), y = Views.ROSTER_Y, w = T.PANEL_W, h = 62 }
end

function Views.gear_rect(i)
  return { x = 60 + (i - 1) * 90, y = 148, w = 80, h = 37 }
end

function Views.sell_slots(run)
  local slots = {}
  for i, group in ipairs(Ui.hud.relic_groups(run.relics)) do
    slots[#slots + 1] = {
      kind = 'relic',
      id = group.id,
      index = group.index,
      count = group.count,
      rect = { x = 22 + ((i - 1) % 4) * 86, y = 78 + math.floor((i - 1) / 4) * 39, w = 82, h = 34 },
    }
  end
  for i, id in ipairs(run.inventory) do
    slots[#slots + 1] = {
      kind = 'active',
      id = id,
      index = i,
      count = 1,
      rect = { x = 22 + (i - 1) * 116, y = 171, w = 108, h = 32 },
    }
  end
  return slots
end

local function hovered_target(targets, mouse)
  for _, slot in ipairs(targets or {}) do
    if slot ~= 'core' and Ui.hit(Views.roster_rect(slot), mouse.x, mouse.y) then
      return slot
    end
  end
  return nil
end

local function draw_swap_board(screen, mouse)
  local run = screen.run
  local highlights, ghost, hovered, preview_slot = {}, nil, nil, nil
  local moving = screen.drag or screen.swap_from
  for i = 1, Constants.SLOTS do
    if Ui.hit(Views.roster_rect(i), mouse.x, mouse.y) then
      hovered = i
    end
  end
  for i = 1, Constants.SLOTS do
    if moving == i then
      highlights[i] = C.amber
    elseif hovered == i and ((moving and i ~= moving) or (not moving and run.roster[i])) then
      highlights[i] = C.green
    else
      highlights[i] = C.dim
    end
  end

  preview_slot = moving and hovered and hovered ~= moving and hovered or nil
  local roster = run.roster
  if preview_slot and roster[moving] then
    roster = {}
    for i, unit in pairs(run.roster) do
      roster[i] = unit
    end
    roster[moving], roster[preview_slot] = roster[preview_slot], roster[moving]
    ghost = { [moving] = true, [preview_slot] = true }
  end

  Ui.roster.draw(roster, T.COL_X0, Views.ROSTER_Y, {
    ch = 62,
    highlight = highlights,
    selected = screen.swap_from or screen.target,
    ghost = ghost,
    relics = run.relics,
  })
  if screen.drag and not preview_slot and run.roster[screen.drag] then
    Ui.unit(run.roster[screen.drag], mouse.x, mouse.y, 2, C.amber, 0.8)
  end
end

local function draw_header_bar(run, text_y, mouse)
  local fuse_on = (run.fuse or 0) > 0
  local fuse_rect = { x = 104, y = Cards.HEADER_Y, w = 48, h = Cards.HEADER_H }
  local fcol = fuse_on and C.green or C.dim
  Ui.rect(fuse_rect.x, fuse_rect.y, fuse_rect.w, fuse_rect.h, C.shade)
  Ui.frame(fuse_rect.x, fuse_rect.y, fuse_rect.w, fuse_rect.h, fuse_on and C.green or C.line)
  Ui.icon('insurance', fuse_rect.x + 6, fuse_rect.y + fuse_rect.h / 2, 1, fcol)
  Text.fit_text(tr(fuse_on and 'fuse_ready' or 'fuse_spent'), fuse_rect.x + 12, text_y, fuse_rect.w - 14, { color = fcol })
  Ui.tooltip.register(fuse_rect, tr('fuse_tip_title'), tr(fuse_on and 'fuse_tip_ready' or 'fuse_tip_spent'), {
    icon = fuse_on and 'insurance' or 'x',
    icon_color = fuse_on and C.green or C.dim,
    color = fuse_on and C.green or C.dim,
  })

  if run.boss_encounter then
    local boss = run:boss_encounter()
    if boss and boss.name then
      Text.fit_text(tr('boss_preview', I18n.wave_name(boss.name)), 290, text_y, 132, { align = 'right', color = C.red })
    end
  end
  Ui.button_rect(Views.MAP_BTN, tr('open_map'), { color = C.paper }, mouse)
end

function Views.draw_choose(screen, header_text_y, mouse)
  local run = screen.run
  draw_header_bar(run, header_text_y, mouse)

  local offers = run:node_offers()
  local rects = Cards.offer_rects(offers)
  for i, offer in ipairs(offers) do
    Cards.draw_offer(offer, rects[i], mouse)
  end

  Ui.hline(8, Cards.STOCK_Y - 5, T.W - 16, C.line, 0.8)
  local highlights = {}
  if screen.drag then
    for i = 1, Constants.SLOTS do
      local r = Views.roster_rect(i)
      highlights[i] = i == screen.drag and C.amber or (Ui.hit(r, mouse.x, mouse.y) and C.green or C.dim)
    end
  end
  Ui.roster.draw(run.roster, T.COL_X0, Views.ROSTER_Y, {
    ch = 62,
    highlight = highlights,
    relics = run.relics,
  })
  if screen.drag and run.roster[screen.drag] then
    Ui.unit(run.roster[screen.drag], mouse.x, mouse.y, 2, C.amber, 0.8)
  end

  Ui.button_rect(Views.SELL_BTN, tr('sell'), {}, mouse)
  local charge = run.charge or 0
  Cards.draw_charge_button(Views.REROLL_BTN, tr('charge_reroll'), 1, charge < 1, mouse, tr('charge_reroll_tip'))
  Cards.draw_charge_button(
    Views.ADJUST_BTN,
    tr('charge_adjust'),
    2,
    charge < 2 or run:alive_count() == 0,
    mouse,
    tr('charge_adjust_tip')
  )
  Cards.draw_charge_button(
    Views.TRIAGE_BTN,
    tr('charge_triage'),
    2,
    charge < 2 or #run:wounded_slots() == 0,
    mouse,
    tr('charge_triage_tip')
  )

  Ui.button_rect(Views.LEAVE_BTN, tr('leave'), { primary = true }, mouse)
end

function Views.draw_use(screen, mouse)
  local run = screen.run
  local def = Items.ACTIVES[screen.use_id]
  Ui.equipment_icon(def, 38, 59, 2, 1)
  Text.fit_text(I18n.active_name(screen.use_id), T.W / 2, 54, 220, { align = 'center', color = C.amber })
  Text.wrap_text(I18n.active_description(screen.use_id), 30, 75, 324, { color = C.paper, max_lines = 3 })

  local notice
  if screen.target == 'core' then
    local amount = math.min(def.amount, run.core_max - run.core)
    notice = tr('use_core_after', amount, run.core + amount)
  elseif screen.target then
    local unit = run.roster[screen.target]
    notice = tr('use_restore', math.min(def.amount, Unit.max_hp(unit) - unit.hp))
  else
    notice = tr('use_target')
  end
  Text.text(notice, T.W / 2, 135, { align = 'center', color = C.amber })

  if screen.targets[1] ~= 'core' then
    local hovered = hovered_target(screen.targets, mouse)
    local highlights = {}
    for _, i in ipairs(screen.targets) do
      highlights[i] = screen.target == i and C.amber or (hovered == i and C.green or C.dim)
    end
    Ui.roster.draw(run.roster, T.COL_X0, Views.ROSTER_Y, {
      ch = 62,
      highlight = highlights,
      selected = screen.target,
      relics = run.relics,
    })
  end

  Ui.button_rect(Views.BACK_BTN, I18n.t('common.back'), { color = C.paper }, mouse)
  Ui.button_rect(Views.CONFIRM_BTN, I18n.t('common.confirm'), {
    disabled = not screen.target,
    primary = screen.target ~= nil,
  }, mouse)
end

function Views.draw_sell(screen, mouse)
  local run = screen.run
  Text.text(tr('sell_title'), T.W / 2, 46, { align = 'center', color = C.amber })
  Text.text(tr('passive'), 22, 63, { color = C.paper })
  Text.text(tr('active'), 22, 156, { color = C.paper })

  for _, slot in ipairs(Views.sell_slots(run)) do
    local kind, id, i, r = slot.kind, slot.id, slot.index, slot.rect
    local def = (kind == 'relic' and Items.RELICS or Items.ACTIVES)[id]
    local selected = screen.sell_kind == kind and screen.sell_index == i
    local hot = Ui.hit(r, mouse.x, mouse.y)
    Ui.rect(r.x, r.y, r.w, r.h, (selected or hot) and C.panel or C.shade)
    Cards.offer_frame(r, kind, true, hot, selected)
    if def then
      Ui.equipment_icon(def, r.x + 9, r.y + r.h - 6, 1, 1)
    end
    local name = kind == 'relic' and I18n.relic_name(id) or I18n.active_name(id)
    Text.wrap_text(name, r.x + 5, r.y + 4, r.w - 10, { color = C.paper, max_lines = 2 })
    local sell_val = '+' .. tostring(run:sell_value(kind, i) or 0)
    Text.text(sell_val, r.x + r.w - 14, r.y + r.h - 10, {
      align = 'right',
      color = C.amber,
      bitmap = true,
    })
    Ui.icon('coin', r.x + r.w - 8, r.y + r.h - 7, 1, C.amber)
    if slot.count > 1 then
      Text.text('x' .. slot.count, r.x + 20, r.y + r.h - 10, { color = C.paper, bitmap = true })
    end
    if def then
      Ui.tooltip.register(
        r,
        name,
        kind == 'relic' and I18n.relic_description(id, slot.count) or I18n.active_description(id)
      )
    end
  end

  local value = screen.sell_kind and run:sell_value(screen.sell_kind, screen.sell_index)
  if value then
    local msg = tr('sell_refund', value)
    local tw = Text.width(msg)
    local sx = math.floor((T.W - (tw + 11)) / 2)
    Text.text(msg, sx, 209, { color = C.amber })
    Ui.icon('coin', sx + tw + 6, 209 + (Ui.cjk and 5 or 3), 1, C.amber)
  else
    Text.text(tr('sell_prompt'), T.W / 2, 209, {
      align = 'center',
      color = C.amber,
    })
  end
  Ui.button_rect(Views.BACK_BTN, I18n.t('common.back'), { color = C.paper }, mouse)
  Ui.button_rect(Views.CONFIRM_BTN, I18n.t('common.confirm'), {
    disabled = not value,
    primary = value ~= nil,
  }, mouse)
end

function Views.draw_confirm(screen, mouse)
  local run = screen.run
  if screen.charge_swap then
    local ok = (run.charge or 0) >= 2
    Text.fit_text(tr('swap_title'), T.W / 2, 54, 300, { align = 'center', color = C.amber })
    Ui.icon_text('charge', 2, T.W - 28, 54, { align = 'right', color = C.blue })
    Text.fit_text(tr('swap_drag'), T.W / 2, 114, 324, { align = 'center', color = ok and C.paper or C.amber })
    draw_swap_board(screen, mouse)
    Ui.button_rect(Views.BACK_BTN, I18n.t('common.back'), { color = C.paper }, mouse)
    return
  end

  local o = run:node_offers()[screen.sel]
  local targeted = screen:needs_target(o)
  local ok, reason = run:can_buy(screen.sel, screen.target)
  local def = Cards.is_gear(o) and Cards.gear_defs(o)[o.id]
  local title_y = o.kind == 'recruit' and 50 or 54

  if def then
    Ui.equipment_icon(def, 38, 59, 2, 1)
  end
  if o.kind == 'trait' then
    Ui.icon(Traits.definitions[o.id].icon, 38, 59, 2, C.amber)
  end
  Text.fit_text(I18n.offer_title(o), T.W / 2, title_y, 272, { align = 'center', color = C.amber })

  if o.kind ~= 'recruit' and o.kind ~= 'swap' then
    Text.wrap_text(I18n.offer_detail(o), 30, 73, 324, { color = C.paper, max_lines = o.kind == 'trait' and 4 or 3 })
  end

  if o.kind == 'recruit' then
    local unit = { kind = o.class, hp = Units.ALLIES[o.class].hp }
    local _, lines = Ui.tooltip.unit_details(unit)
    local rtier = o.rarity or Units.ALLIES[o.class].rarity or 'common'
    Ui.unit_shadow(38, 95)
    Ui.unit(o.class, 38, 80, 2, C.paper)
    Text.fit_text(lines[1] .. '   ' .. lines[2], 65, 66, 290, { color = C.paper })
    Text.text(tr('rarity_' .. rtier), 65, 81, { color = Ui.rarity_color(rtier) })
    Text.wrap_text(I18n.unit_blurb(unit), 65, 97, 290, { color = C.paper, max_lines = 2 })
    Ui.tooltip.trait_icons(unit, 65, 123, { preview = true, align = 'left', relics = run.relics })
  end

  Ui.icon_text('coin', o.price < 0 and '+1' or o.price, T.W - 28, title_y, { align = 'right', color = C.amber })

  local reason_key = ({ ['NOT ENOUGH GOLD'] = 'funds', ['INVALID TARGET'] = 'target' })[reason]
  local notice = reason == 'NOT ENOUGH GOLD' and tr('funds')
    or o.kind == 'swap' and tr('swap_drag')
    or reason_key and tr(reason_key)
    or (targeted and tr('select_target') or tr('confirm_purchase'))

  if o.kind == 'trait' and reason ~= 'NOT ENOUGH GOLD' and #screen.targets > 0 then
    notice = screen.target and tr('trait_confirm', I18n.unit_name(run.roster[screen.target])) or tr('trait_target')
  end
  if o.kind ~= 'swap' and reason == 'INVALID TARGET' and #screen.targets == 0 then
    if o.kind == 'dismiss' then
      notice = tr('last_unit')
    elseif o.kind == 'recruit' then
      notice = tr('board_full')
    elseif o.kind == 'upgrade' then
      notice = tr('upgrade_cap')
    elseif o.kind == 'trait' then
      notice = tr('trait_no_target')
    else
      notice = tr('unavailable')
    end
  end

  Text.fit_text(
    notice,
    T.W / 2,
    o.kind == 'recruit' and 138 or (o.kind == 'swap' and 114 or 127),
    340,
    { align = 'center', color = ok and C.paper or C.amber }
  )

  if Cards.is_gear(o) and targeted then
    local defs = Cards.gear_defs(o)
    local list = o.kind == 'relic' and run.relics or run.inventory
    for i, id in ipairs(list) do
      local r = Views.gear_rect(i)
      local item = defs[id]
      local hot = Ui.hit(r, mouse.x, mouse.y)
      Ui.rect(r.x, r.y, r.w, r.h, (screen.target == i or hot) and C.panel or C.shade)
      Cards.offer_frame(r, o.kind, true, hot, screen.target == i)
      Ui.equipment_icon(item, r.x + 10, r.y + 12, 1, 1)
      local label = o.kind == 'relic' and I18n.relic_name(id) or I18n.active_name(id)
      Text.wrap_text(label, r.x + 18, r.y + 6, r.w - 22, { color = C.paper, max_lines = 2 })
    end
  elseif o.kind == 'swap' then
    draw_swap_board(screen, mouse)
  else
    local hovered = hovered_target(screen.targets, mouse)
    local hot_col = o.kind == 'dismiss' and C.red or C.green
    local highlights, ghost, preview_slot = {}, nil, nil
    for _, i in ipairs(screen.targets) do
      highlights[i] = screen.target == i and C.amber or (hovered == i and hot_col or C.dim)
    end
    if o.kind == 'recruit' then
      preview_slot = hovered or screen.target
      if preview_slot then
        ghost = { [preview_slot] = true }
      end
    end
    Ui.roster.draw(run.roster, T.COL_X0, Views.ROSTER_Y, {
      ch = 62,
      highlight = highlights,
      selected = screen.target,
      ghost = ghost,
      relics = run.relics,
    })
    if o.kind == 'recruit' and preview_slot then
      local cx = T.col_cx(preview_slot)
      Ui.unit_shadow(cx, Views.ROSTER_Y + 30, 18, 0.35)
      Ui.unit(o.class, cx, Views.ROSTER_Y + 15, 2, hovered == preview_slot and C.green or C.amber, 0.55)
    end
  end

  Ui.button_rect(Views.BACK_BTN, I18n.t('common.back'), { color = C.paper }, mouse)
  if o.kind ~= 'swap' then
    Ui.button_rect(Views.CONFIRM_BTN, I18n.t('common.confirm'), { disabled = not ok, primary = ok }, mouse)
  end
end

return Views
