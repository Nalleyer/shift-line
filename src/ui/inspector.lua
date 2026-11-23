-- Full-screen Unit Inspector modal showing unit stats and selectable trait descriptions.
local Unit = require('core.unit')
local I18n = require('i18n')
local Theme = require('ui.theme')
local Draw = require('ui.draw')
local Text = require('ui.text')
local Tooltip = require('ui.tooltip')

local C = Theme.C
local Inspector = {
  active = nil,
}

local CLOSE_RECT = { x = 332, y = 43, w = 22, h = 19 }

function Inspector.open(unit, opts, trait_id)
  local selected = 1
  for j, t in ipairs(Unit.traits(unit)) do
    if t.id == trait_id then
      selected = j
      break
    end
  end
  Inspector.active = {
    unit = unit,
    opts = opts or {},
    selected = selected,
  }
end

function Inspector.close()
  Inspector.active = nil
end

function Inspector.keypressed(key)
  local m = Inspector.active
  if not m then
    return false
  end
  if key == 'escape' or key == 'return' or key == 'backspace' then
    Inspector.active = nil
  elseif key == 'left' or key == 'up' or key == 'a' then
    m.selected = math.max(1, m.selected - 1)
  elseif key == 'right' or key == 'down' or key == 'd' then
    m.selected = math.min(#Unit.traits(m.unit), m.selected + 1)
  end
  return true
end

function Inspector.mousepressed(x, y, button, ctx)
  if button ~= 1 then
    return false
  end
  local m = Inspector.active
  if m then
    if (x >= 332 and x <= 354 and y >= 43 and y <= 62) or x < 24 or x > 360 or y < 38 or y > 248 then
      Inspector.active = nil
      return true
    end
    local traits = Unit.traits(m.unit)
    for i in ipairs(traits) do
      if Draw.inside({ x = 34, y = 88 + (i - 1) * 25, w = 126, h = 22 }, x, y) then
        m.selected = i
      end
    end
    return true
  end

  ctx = ctx or {}
  if ctx.allow_inspect == false then
    return false
  end
  local preview_only = ctx.inspect_preview_only
  for _, regions in ipairs({ Tooltip.trait_regions, Tooltip.unit_regions }) do
    for i = #regions, 1, -1 do
      local region = regions[i]
      if Draw.inside(region.rect, x, y) and (not preview_only or region.opts.preview) then
        Inspector.open(region.unit, region.opts, region.trait)
        return true
      end
    end
  end
  return false
end

function Inspector.draw(mouse)
  local m = Inspector.active
  if not m then
    return
  end
  mouse = mouse or { x = -100, y = -100 }
  Draw.rect(0, 0, Theme.W, Theme.H, C.ink, 0.8)
  Draw.panel(24, 38, 336, 210, { border = C.amber, fill = C.panel })

  local u = m.unit
  local enemy = Unit.is_enemy(u.kind)
  Draw.unit_shadow(54, 74)
  Draw.unit(u, 54, 59, 2, enemy and C.red or C.paper)
  Text.fit_text(I18n.unit_name(u), 84, 46, 240, { color = C.amber })
  Draw.button_rect(CLOSE_RECT, 'X', {}, mouse)

  local stats = I18n.t('ui.health_full') .. ' ' .. u.hp .. '/' .. (u.max or Unit.max_hp(u))
    .. '   ' .. I18n.t('ui.attack_full') .. ' ' .. Tooltip.live_atk(u, m.opts)
    .. '   ' .. I18n.t('ui.defense_full') .. ' ' .. Unit.defense(u)
  Text.fit_text(stats, 84, 65, 242, { color = C.paper })

  local traits = Unit.traits(u)
  for i, t in ipairs(traits) do
    local y = 88 + (i - 1) * 25
    local hot = Draw.inside({ x = 34, y = y, w = 126, h = 22 }, mouse.x, mouse.y)
    Draw.button(34, y, 126, 22, '', { hover = hot, primary = i == m.selected })
    Draw.icon(t.icon, 43, y + 11, 1, C.amber)
    Text.fit_text(I18n.t('trait.' .. t.id .. '.name'), 52, y + 5, 102, { color = C.paper })
  end

  local trait = traits[m.selected]
  if trait then
    Text.fit_text(I18n.t('trait.' .. trait.id .. '.name'), 174, 91, 174, { color = C.amber })
    Text.wrap_text(Tooltip.trait_detail(u, trait, m.opts), 174, 112, 174, { color = C.paper, max_lines = 9 })
  else
    Text.wrap_text(I18n.unit_blurb(u), 174, 99, 174, { color = C.paper, max_lines = 8 })
  end
end

return Inspector
