-- Facade for the decoupled UI toolkit (zero dependency on app or screen internals).
local Theme = require('ui.theme')
local Assets = require('ui.assets')
local Text = require('ui.text')
local Draw = require('ui.draw')
local Tooltip = require('ui.tooltip')
local Inspector = require('ui.inspector')
local Hud = require('ui.hud')
local Roster = require('ui.roster')
local Dialogs = require('ui.dialogs')

local Ui = {
  T = Theme,
  C = Theme.C,
  theme = Theme,
  assets = Assets,
  text = Text,
  draw = Draw,
  tooltip = Tooltip,
  inspector = Inspector,
  hud = Hud,
  roster = Roster,
  dialogs = Dialogs,
  cjk = Assets.cjk,
  line_h = Assets.line_h,
  text_h = Assets.text_h,
}

local function sync_metrics()
  Ui.cjk = Assets.cjk
  Ui.line_h = Assets.line_h
  Ui.text_h = Assets.text_h
end

function Ui.load()
  Assets.load()
  sync_metrics()
end

function Ui.set_locale(locale)
  Assets.set_locale(locale)
  sync_metrics()
end

function Ui.set_cjk(enabled)
  Assets.set_cjk(enabled)
  sync_metrics()
end

function Ui.begin_frame(mouse)
  Tooltip.begin_frame(mouse)
end

function Ui.draw_overlay(ctx)
  if Inspector.active then
    Inspector.draw(ctx and ctx.mouse)
    Tooltip.pending = nil
    Tooltip.loadout_tip = nil
    return
  end
  Tooltip.draw(ctx)
end

function Ui.draw_toast(message)
  Tooltip.draw_toast(message)
end

-- Convenience direct aliases for primitives and layout helpers.
Ui.set = Draw.set
Ui.mix = Draw.mix
Ui.hit = Draw.hit
Ui.inside = Draw.inside
Ui.rect = Draw.rect
Ui.frame = Draw.frame
Ui.panel = Draw.panel
Ui.hline = Draw.hline
Ui.vline = Draw.vline
Ui.unit = Draw.unit
Ui.icon = Draw.icon
Ui.slot_marker = Draw.slot_marker
Ui.unit_shadow = Draw.unit_shadow
Ui.icon_text = Draw.icon_text
Ui.unit_plate = Draw.unit_plate
Ui.button = Draw.button
Ui.button_rect = Draw.button_rect
Ui.hearts = Draw.hearts
Ui.health_bar = Draw.health_bar
Ui.rarity_color = Draw.rarity_color
Ui.equipment_icon = Draw.equipment_icon
Ui.footer = Draw.footer
Ui.wipe = Draw.wipe
Ui.flash = Draw.flash
Ui.draw_grid_bg = Draw.draw_grid_bg
Ui.ease_out = Draw.ease_out

return Ui
