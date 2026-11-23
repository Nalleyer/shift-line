-- Top bar HUD: Core integrity, Gold, Charge, passive relics, and consumable slots.
local Constants = require('data.constants')
local Items = require('data.items')
local Battle = require('core.battle')
local Camp = require('core.camp')
local I18n = require('i18n')
local Theme = require('ui.theme')
local Draw = require('ui.draw')
local Text = require('ui.text')
local Tooltip = require('ui.tooltip')

local C = Theme.C
local Hud = {}

function Hud.relic_groups(ids)
  local out, by_id = {}, {}
  for index, id in ipairs(ids or {}) do
    if by_id[id] then
      by_id[id].count = by_id[id].count + 1
    else
      local group = { id = id, count = 1, index = index }
      by_id[id] = group
      out[#out + 1] = group
    end
  end
  return out
end

function Hud.loadout_slots(ctx)
  ctx = ctx or {}
  local run = ctx.run
  if not run or ctx.show_loadout == false then
    return {}
  end

  local battle = ctx.battle
  local relics = ctx.relics or (battle and battle.relics) or run.relics or {}
  local inventory = (battle and battle.inventory) or run.inventory or {}
  local groups = Hud.relic_groups(relics)
  local compact = #groups > 3
  local slots = {}

  for i = 1, math.max(#groups, compact and 0 or 3) do
    local group = groups[i]
    local id = group and group.id
    slots[#slots + 1] = {
      kind = 'relic',
      index = group and group.index or i,
      id = id,
      count = group and group.count or 0,
      definition = id and Items.RELICS[id],
      x = 180 + (compact and ((i - 1) % 4) * 21 or (i - 1) * 28),
      y = compact and (1 + math.floor((i - 1) / 4) * 10) or 2,
      w = compact and 21 or 26,
      h = compact and 10 or 18,
      compact = compact,
      can_use = false,
    }
  end

  for i = 1, Constants.INVENTORY_MAX do
    local id = inventory[i]
    local can_use, reason = false, nil
    if battle then
      if ctx.can_use_actives and not ctx.modal then
        can_use, reason = Battle.can_use_item(battle, i)
      end
    elseif run.phase == 'camp' then
      can_use, reason = Camp.can_use_item(run, i)
      if not ctx.can_use_actives then
        can_use = false
        reason = ctx.active_block_reason or reason
      end
    end

    slots[#slots + 1] = {
      kind = 'active',
      index = i,
      id = id,
      definition = id and Items.ACTIVES[id],
      x = 284 + (i - 1) * 28,
      y = 2,
      w = 24,
      h = 18,
      can_use = can_use,
      reason = reason,
    }
  end

  return slots
end

function Hud.mousepressed(x, y, button, ctx)
  if button ~= 1 or not ctx or ctx.modal then
    return false
  end
  for _, slot in ipairs(Hud.loadout_slots(ctx)) do
    if Draw.inside(slot, x, y) then
      if slot.kind == 'active' and (slot.can_use or (ctx.battle and slot.id)) and ctx.on_use_item then
        ctx.on_use_item(slot.index)
      end
      return true
    end
  end
  return false
end

function Hud.topbar(core, core_max, ctx)
  ctx = ctx or {}
  local run = ctx.run
  local battle = ctx.battle
  local mouse = ctx.mouse or Tooltip.mouse or { x = -100, y = -100 }

  Draw.rect(0, 0, Theme.W, Theme.TOP_H, C.shade)
  Draw.hline(0, Theme.TOP_H - 1, Theme.W, C.line)
  Draw.hearts(3, 3, core, core_max, { flash = ctx.flash or 0, step = 10, scale = 1 })

  local gold = ctx.gold or (run and run.gold) or 0
  local charge = ctx.charge
  if charge == nil then
    charge = (battle and battle.charge) or (run and run.charge) or 0
  end
  local charge_max = ctx.charge_max or (battle and battle.charge_max) or (run and run.charge_max) or Constants.CHARGE_MAX

  if run then
    Draw.vline(105, 5, 12, C.line)
    Draw.vline(174, 5, 12, C.line)
    Draw.icon_text('coin', gold, 112, 8, { color = C.amber })
    Draw.icon_text('charge', charge .. '/' .. charge_max, 145, 8, { color = C.blue })
  end

  Tooltip.loadout_tip = nil
  Tooltip.register({ x = 4, y = 2, w = 100, h = 18 }, I18n.t('ui.core'), I18n.t('ui.core_current', core, core_max), {
    icon = 'heart',
    icon_color = C.red,
    color = C.red,
  })
  if run then
    Tooltip.register({ x = 108, y = 2, w = 34, h = 18 }, I18n.t('result.gold'), I18n.t('ui.gold_current', gold), {
      icon = 'coin',
      icon_color = C.amber,
      color = C.amber,
    })
    Tooltip.register({ x = 142, y = 2, w = 31, h = 18 }, I18n.t('ui.charge'), I18n.t('ui.charge_current', charge, charge_max), {
      icon = 'charge',
      icon_color = C.blue,
      color = C.blue,
    })
  end

  if not run or ctx.show_loadout == false then
    return
  end

  Draw.vline(276, 5, 12, C.line)
  for _, slot in ipairs(Hud.loadout_slots(ctx)) do
    local d = slot.definition
    local hot = Draw.inside(slot, mouse.x, mouse.y)
    local col = Draw.rarity_color(d)
    Draw.rect(slot.x, slot.y, slot.w, slot.h, d and C.panel or C.ink, 0.8)
    Draw.frame(
      slot.x,
      slot.y,
      slot.w,
      slot.h,
      hot and d and C.amber or (d and col or C.line),
      d and (slot.compact and not hot and 0.55 or 1) or 0.25
    )

    local count = slot.count or 0
    local numbered = slot.kind == 'relic' and count > 1
    if numbered then
      local label = count > 99 and '+' or tostring(count)
      Text.text(label, slot.x + slot.w - (slot.compact and 1 or 2), slot.y + math.floor((slot.h - 7) / 2), {
        align = 'right',
        color = C.amber,
        bitmap = true,
      })
    end

    if d then
      local alpha = slot.kind == 'active' and not slot.can_use and 0.6 or 1
      local scale = (slot.compact or numbered) and 1 or 2
      local icon_x = slot.x + (numbered and 5 or slot.w / 2)
      Draw.equipment_icon(d, icon_x, slot.y + slot.h / 2, scale, alpha)
      if hot then
        local name, description
        if slot.kind == 'relic' then
          name = I18n.relic_name(slot.id) .. (count > 1 and (' x' .. count) or '')
          description = I18n.relic_description(slot.id, count)
        else
          name = I18n.active_name(slot.id)
          description = I18n.active_description(slot.id)
        end
        Tooltip.loadout_tip = {
          x = slot.x,
          name = name,
          description = description,
          definition = d,
          kind = slot.kind,
          index = slot.index,
          can_use = slot.can_use,
          reason = slot.reason,
          rarity = d.rarity or 'common',
        }
      end
    end
  end
end

return Hud
