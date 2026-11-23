-- Shared 6-slot roster bar renderer for Camp and non-battle overview screens.
local Constants = require('data.constants')
local Unit = require('core.unit')
local Theme = require('ui.theme')
local Draw = require('ui.draw')
local Tooltip = require('ui.tooltip')

local C = Theme.C
local Roster = {}

function Roster.draw(slots, x, y, opts)
  opts = opts or {}
  local cw = opts.cw or Theme.PANEL_W
  local ch = opts.ch or 58
  local step = opts.step or Theme.COL_STEP
  local compact = opts.compact or ch < 54
  local foot_y = y + (compact and 18 or 30)
  local relics = opts.relics
  local out = {}

  for i = 1, Constants.SLOTS do
    local u = slots[i]
    local bx = x + (i - 1) * step
    local cx = bx + cw / 2
    local is_ghost = opts.ghost and opts.ghost[i]
    local selected = opts.selected == i
    local hl = opts.highlight and opts.highlight[i]

    Draw.slot_marker(cx, foot_y, not u and not is_ghost, selected and C.amber or hl, compact)

    if u then
      local col = C.paper
      if u.fresh then
        col = C.amber
      end
      if opts.dim then
        col = C.dim
      end
      if is_ghost then
        col = C.blue
      end
      local alpha = is_ghost and 0.75 or 1

      Draw.unit_shadow(cx, foot_y, compact and 10 or 18, is_ghost and 0.35 or nil)
      Draw.unit(u, cx, foot_y - (compact and 8 or 15), compact and 1 or 2, col, alpha)
      Draw.health_bar(bx + 5, y + (compact and 21 or 33), cw - 10, compact and 3 or 4, u.hp, Unit.max_hp(u), {
        alpha = is_ghost and 0.7 or 1,
      })
      Draw.unit_plate(cx, y + (compact and 29 or 41), Unit.attack(u), Unit.defense(u), {
        alpha = is_ghost and 0.7 or 1,
        atk_color = opts.dim and C.dim or C.paper,
        def_color = opts.dim and C.dim or C.blue,
      })
      if not is_ghost then
        Tooltip.unit_tooltip({ x = bx, y = y, w = cw, h = ch }, u, {
          line = slots,
          col = i,
          relics = relics,
        })
      end
      Tooltip.trait_icons(u, cx, y + (compact and 39 or 50), {
        align = 'center',
        relics = relics,
      })
    end

    out[i] = { x = bx, y = y, w = cw, h = ch }
  end

  return out
end

return Roster
