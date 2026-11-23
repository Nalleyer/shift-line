-- Per-frame tooltip and hover-region registry plus battle-dock / floating tooltip rendering.
local Unit = require('core.unit')
local Util = require('core.util')
local I18n = require('i18n')
local Theme = require('ui.theme')
local Assets = require('ui.assets')
local Text = require('ui.text')
local Draw = require('ui.draw')

local C = Theme.C
local Tooltip = {
  mouse = { x = -100, y = -100 },
  pending = nil,
  loadout_tip = nil,
  unit_regions = {},
  trait_regions = {},
}

function Tooltip.begin_frame(mouse)
  Tooltip.mouse = mouse or { x = -100, y = -100 }
  Tooltip.pending = nil
  Tooltip.loadout_tip = nil
  Tooltip.unit_regions = {}
  Tooltip.trait_regions = {}
end

function Tooltip.register(rect, title, body, opts)
  local mouse = Tooltip.mouse
  if not rect or not mouse or not Draw.inside(rect, mouse.x, mouse.y) then
    return false
  end
  Tooltip.pending = { rect = rect, title = title, body = body, opts = opts or {} }
  return true
end

function Tooltip.live_atk(u, opts)
  local state = opts and opts.state
  local atk = Unit.attack(u, state)
  if state and opts and opts.col and not Unit.is_enemy(u.kind) then
    atk = atk + Unit.support_attack_bonus(state, opts.col)
  end
  return atk
end

function Tooltip.trait_detail(unit, trait, opts)
  opts = opts or {}
  if trait.family == 'growth' then
    return I18n.t('trait.' .. trait.id .. '.detail') .. ' ' .. I18n.t('ui.growth', unit.growth_wins or 0, trait.wins)
  end
  if trait.family == 'guard' or trait.family == 'heal' or trait.family == 'charge_aura' then
    local reach = 1 + (Util.relic_count(opts.relics, 'far_lens') > 0 and 1 or 0)
    if reach > 1 then
      if trait.family == 'charge_aura' then
        return I18n.t('ui.charge_range', math.min(5, reach))
      end
      return I18n.t('ui.' .. trait.family .. '_range', trait.amount, math.min(5, reach))
    end
  end
  return I18n.t('trait.' .. trait.id .. '.detail')
end

function Tooltip.unit_details(u, opts)
  return I18n.unit_name(u), {
    I18n.t('ui.health_full') .. ' ' .. u.hp .. '/' .. (u.max or Unit.max_hp(u)),
    I18n.t('ui.attack_full') .. ' ' .. Tooltip.live_atk(u, opts) .. '  ' .. I18n.t('ui.defense_full') .. ' ' .. Unit.defense(u),
    I18n.unit_blurb(u),
  }
end

function Tooltip.trait_icons(unit, x, y, opts)
  opts = opts or {}
  local traits = Unit.traits(unit)
  local columns = opts.columns or 5
  if opts.align == 'center' then
    local count = math.min(#traits, columns)
    x = math.floor(x - (count * 9 - 1) / 2 + 0.5)
  elseif opts.align ~= 'left' then
    x = x + (2 - math.min(#traits, 5)) * 9
  end

  for i, trait in ipairs(traits) do
    local bx = x + ((i - 1) % columns) * 9
    local by = y + math.floor((i - 1) / columns) * 9
    Draw.rect(bx, by, 8, 8, C.ink, 0.9)
    Draw.icon(trait.icon, bx + 4, by + 4, 1, C.amber)
    local rect = { x = bx, y = by, w = 8, h = 8 }
    Tooltip.trait_regions[#Tooltip.trait_regions + 1] = {
      rect = rect,
      unit = unit,
      opts = opts,
      trait = trait.id,
    }
    Tooltip.register(rect, I18n.t('trait.' .. trait.id .. '.name'), Tooltip.trait_detail(unit, trait, opts), {
      trait = trait,
      icon = trait.icon,
      icon_color = C.amber,
    })
  end
end

function Tooltip.unit_tooltip(rect, u, opts)
  local region_opts = {}
  for k, v in pairs(opts or {}) do
    region_opts[k] = v
  end
  local title, lines = Tooltip.unit_details(u, region_opts)
  Tooltip.unit_regions[#Tooltip.unit_regions + 1] = { rect = rect, unit = u, opts = region_opts }
  region_opts.unit = u
  return Tooltip.register(rect, title, lines, region_opts)
end

local function draw_battle_dock(generic, tip)
  local x, y, w, h = 8, 230, Theme.W - 112, 56
  local tx, ty, tw = x + 6, y + 3, w - 12
  Draw.rect(0, y - 1, Theme.W, Theme.FOOT_Y - y + 1, C.ink)
  Draw.rect(0, Theme.FOOT_Y, x + w + 2, Theme.H - Theme.FOOT_Y, C.ink)
  Draw.panel(x, y, w, h, { border = C.amber, fill = C.panel })

  if generic then
    local unit = generic.opts.unit
    local icon = generic.opts.icon
    local title_x = icon and (tx + 11) or tx
    local title_w = icon and (tw - 11) or tw
    local title_col = generic.opts.color or C.amber
    if icon then
      Draw.icon(icon, tx + 4, ty + (Assets.cjk and 5 or 3), 1, generic.opts.icon_color or title_col)
    end
    Text.fit_text(generic.title or '', title_x, ty, title_w, { color = title_col })
    ty = ty + Assets.line_h
    if unit then
      local hp_str = unit.hp .. '/' .. (unit.max or Unit.max_hp(unit))
      local atk_str = tostring(Tooltip.live_atk(unit, generic.opts))
      local def_str = tostring(Unit.defense(unit))
      local sx = tx
      Draw.icon_text('heart', hp_str, sx, ty, { color = C.paper, icon_color = C.red, bitmap = true })
      sx = sx + 10 + Text.width(hp_str, 1, true) + 10
      Draw.icon_text('attack', atk_str, sx, ty, { color = C.paper, icon_color = C.amber, bitmap = true })
      sx = sx + 10 + Text.width(atk_str, 1, true) + 10
      Draw.icon_text('defense', def_str, sx, ty, { color = C.paper, icon_color = C.blue, bitmap = true })
      ty = ty + Assets.line_h
    end
    local bodies = type(generic.body) == 'table' and generic.body or { generic.body or '' }
    local start = unit and not generic.opts.trait and 3 or 1
    Text.wrap_text(table.concat(bodies, '\n', start), tx, ty, tw, { color = C.paper, max_lines = unit and 2 or 3 })
  else
    local kind = (tip.kind == 'active' and I18n.t('ui.consumable') or I18n.t('ui.passive'))
      .. ' / ' .. I18n.t('shop.rarity_' .. tip.rarity)
    local has_hint = tip.kind == 'active'
    local title_x = tip.definition and (tx + 11) or tx
    local title_w = tip.definition and (tw - 11) or tw
    if tip.definition then
      Draw.equipment_icon(tip.definition, tx + 4, ty + (Assets.cjk and 5 or 3), 1, 1)
    end
    Text.fit_text(tip.name .. '  ' .. kind, title_x, ty, title_w, { color = Draw.rarity_color(tip.rarity) })
    local next_y = Text.wrap_text(tip.description, tx, ty + Assets.line_h, tw, {
      color = C.paper,
      max_lines = has_hint and 2 or 3,
    })
    if has_hint then
      local hint = tip.can_use and I18n.t('ui.use', tip.index)
        or I18n.reason(tip.reason)
        or I18n.t('ui.use_locked', tip.index)
      Text.fit_text(hint, tx, next_y, tw, { color = tip.can_use and C.green or C.dim })
    end
  end
end

local function draw_floating_generic(generic)
  local r, opts = generic.rect, generic.opts
  local width = math.min(opts.width or 220, Theme.W - 16)
  local bodies = type(generic.body) == 'table' and generic.body or { generic.body or '' }
  local lines = {}
  for _, body in ipairs(bodies) do
    for _, line in ipairs(Text.wrap_lines(body, width - 16)) do
      lines[#lines + 1] = line
    end
  end
  local height = 18 + (#lines + 1) * Assets.line_h
  local x = math.max(4, math.min(Theme.W - width - 4, r.x + r.w + 5))
  if x < r.x + r.w and r.x >= width + 5 then
    x = r.x - width - 5
  end
  local y = math.max(3, math.min(Theme.H - height - 3, r.y))
  if r.y >= Theme.H / 3 then
    y = math.max(3, r.y - height - 4)
  end

  Draw.rect(x + 2, y + 2, width, height, C.ink, 0.8)
  Draw.panel(x, y, width, height, { border = opts.color or C.amber, fill = C.panel })
  local title_x = opts.icon and (x + 19) or (x + 8)
  local title_w = opts.icon and (width - 27) or (width - 16)
  if opts.icon then
    Draw.icon(opts.icon, x + 12, y + 5 + (Assets.cjk and 5 or 3), 1, opts.icon_color or opts.color or C.amber)
  end
  Text.fit_text(generic.title or '', title_x, y + 5, title_w, { color = opts.color or C.amber })
  for i, line in ipairs(lines) do
    Text.text(line, x + 8, y + 5 + i * Assets.line_h, { color = C.paper })
  end
end

local function draw_floating_loadout(tip)
  local width, x, y = 248, math.min(tip.x, Theme.W - 258), Theme.TOP_H + 3
  local lines = Text.wrap_lines(tip.description, width - 16, { max_lines = 7 })
  local line_h = Assets.line_h
  local kind = (tip.kind == 'active' and I18n.t('ui.consumable') or I18n.t('ui.passive'))
    .. ' / ' .. I18n.t('shop.rarity_' .. tip.rarity)
  local has_hint = tip.kind == 'active'
  local title_y = y + (Assets.cjk and 6 or 7)
  local kind_y = y + 19
  local desc_y = y + (Assets.cjk and 32 or 33)
  local hint_y = Assets.cjk and (desc_y + #lines * line_h + 3) or (y + 36 + #lines * 10)
  local height = Assets.cjk
    and ((hint_y - y) + (has_hint and 17 or 0) + 4)
    or (34 + #lines * 10 + (has_hint and 14 or 0))

  Draw.rect(x + 3, y + 3, width, height, C.ink, 0.8)
  Draw.panel(x, y, width, height, { border = Draw.rarity_color(tip.rarity), fill = C.panel })
  local title_x = tip.definition and (x + 19) or (x + 8)
  local title_w = tip.definition and (width - 27) or (width - 16)
  if tip.definition then
    Draw.equipment_icon(tip.definition, x + 12, title_y + (Assets.cjk and 5 or 3), 1, 1)
  end
  Text.fit_text(tip.name, title_x, title_y, title_w, { color = Draw.rarity_color(tip.rarity) })
  Text.text(kind, x + 8, kind_y, { color = C.dim })
  Text.wrap_text(tip.description, x + 8, desc_y, width - 16, { color = C.paper, max_lines = 7 })
  if has_hint then
    local hint = tip.can_use and I18n.t('ui.use', tip.index)
      or I18n.reason(tip.reason)
      or I18n.t('ui.use_locked', tip.index)
    Text.fit_text(hint, x + 8, hint_y, width - 16, { color = tip.can_use and C.green or C.dim })
  end
end

function Tooltip.draw(ctx)
  ctx = ctx or {}
  local generic = Tooltip.pending
  local tip = Tooltip.loadout_tip
  Tooltip.pending = nil

  if ctx.tooltip_style == 'battle_dock' then
    if ctx.suppress_tooltips or (not generic and not tip) then
      return
    end
    draw_battle_dock(generic, tip)
    return
  end

  if generic then
    draw_floating_generic(generic)
  elseif tip then
    draw_floating_loadout(tip)
  end
end

function Tooltip.draw_toast(message)
  local w = math.min(Theme.W - 32, Text.width(message) + 20)
  local h = Assets.text_h + 10
  local x, y = math.floor((Theme.W - w) / 2), 72
  Draw.rect(x, y, w, h, C.ink, 0.95)
  Draw.frame(x, y, w, h, C.amber, 0.8)
  Text.fit_text(message, Theme.W / 2, y + 5, w - 20, { align = 'center', color = C.white })
end

return Tooltip
