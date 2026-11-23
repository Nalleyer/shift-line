-- Post-battle result screen: summary stats, survivor updates, and continuation routing.
local Encounters = require('data.encounters')
local Unit = require('core.unit')
local App = require('app')
local Audio = require('platform.audio')
local I18n = require('i18n')
local Ui = require('ui')

local T = Ui.theme
local C = Ui.C
local Text = Ui.text

local Result = { t = 0 }
local CONTINUE = { x = 132, y = 226, w = 120, h = 26 }
local STATS_Y, STAT_STEP, NOTES_Y = 60, 16, 125

function Result:enter()
  self.t = 0
  self.run = App.run
  self.res = self.run.last
  self.sum = self.run.summary
  Audio.music(self.res and self.res.boss_max and 'boss' or 'battle')
end

function Result:continue()
  Audio.play('ui_select')
  local prev_wave = self.run.wave
  local rewound = self.run.pending_rewind
  self.run:after_result()

  if self.run.phase == 'camp' or (not rewound and self.run.phase == 'battle') then
    if not rewound and App.screens.map then
      App.go('map', { from_wave = prev_wave })
    else
      App.go(self.run.phase == 'camp' and 'camp' or 'battle')
    end
  elseif self.run.phase == 'victory' then
    App.go('ending', 'victory')
  elseif self.run.phase == 'defeat' then
    App.go('ending', 'defeat')
  else
    App.go('battle')
  end
end

function Result:update(dt)
  self.t = self.t + dt
end

function Result:keypressed(key)
  if key == 'return' or key == 'space' or key == 'kpenter' then
    self:continue()
  end
end

function Result:mousepressed(x, y, button)
  if button == 1 and Ui.hit(CONTINUE, x, y) then
    self:continue()
  end
end

local function stat_row(y, label, value, col)
  Text.text(label, 92, y, { color = C.dim })
  Text.text(value, 300, y, { color = col or C.paper, align = 'right' })
  Ui.hline(92, y + (Ui.cjk and 13 or 10), 208, C.line, 0.35, 6)
end

function Result:draw()
  Ui.wipe(1)
  local run = self.run
  local res = self.res
  local sum = self.sum
  local won = res and res.won
  local fuse_rewound = sum and sum.fuse_triggered

  App.draw_topbar()

  local title = fuse_rewound and I18n.t('result.fuse_title') or (won and I18n.t('result.win') or I18n.t('result.lose'))
  local tcol = fuse_rewound and C.amber or (won and C.green or C.red)
  Text.text(title, T.W / 2, 30, { color = tcol, scale = 2, align = 'center' })

  if res then
    local cleared = res.enemy_killed + res.enemy_escaped
    stat_row(STATS_Y, I18n.t('result.enemies'), cleared .. ' / ' .. res.enemy_total)
    stat_row(
      STATS_Y + STAT_STEP,
      I18n.t('result.core_damage'),
      res.core_damage > 0 and ('-' .. res.core_damage) or '0',
      res.core_damage > 0 and C.red or C.paper
    )
    stat_row(
      STATS_Y + 2 * STAT_STEP,
      I18n.t('result.units_lost'),
      tostring(res.casualties),
      res.casualties > 0 and C.red or C.paper
    )
    local gold_earned = (sum and sum.gold_earned) or res.gold_earned or 0
    stat_row(STATS_Y + 3 * STAT_STEP, I18n.t('result.gold'), '+' .. tostring(gold_earned), C.amber)
  end

  if fuse_rewound then
    Text.fit_text(I18n.t('result.fuse_sub'), T.W / 2, NOTES_Y, 340, { align = 'center', color = C.green })
  elseif sum then
    local notes = {}
    if (sum.bonus_core or 0) > 0 then
      notes[#notes + 1] = I18n.t('result.bonus_core', sum.bonus_core)
    end
    if (sum.bonus_charge or 0) > 0 then
      notes[#notes + 1] = I18n.t('result.bonus_charge', sum.bonus_charge)
    end
    if (sum.fuse_bonus or 0) > 0 then
      notes[#notes + 1] = I18n.t('result.fuse_bonus', sum.fuse_bonus)
    elseif sum.fuse_refreshed then
      notes[#notes + 1] = I18n.t('result.fuse_refreshed')
    end
    if #notes > 0 then
      Text.fit_text(table.concat(notes, I18n.is_zh() and ' · ' or ' / '), T.W / 2, NOTES_Y, 356, {
        align = 'center',
        color = C.blue,
      })
    end
  end

  Text.text(I18n.t('result.survivors'), T.COL_X0, 140, { color = C.dim })
  local changed = {}
  if sum then
    for _, s in ipairs(sum.survivors) do
      changed[s.slot] = s
    end
    for _, f in ipairs(sum.fallen) do
      changed[f.slot] = { fallen = true, kind = f.kind }
    end
  end

  for i = 1, 6 do
    local u = run.roster[i]
    local x = T.col_x(i)
    local cx = T.col_cx(i)
    local y = 154
    local foot_y = y + 31
    local ch = changed[i]
    if u then
      local healed = ch and ch.from and ch.from ~= u.hp
      Ui.slot_marker(cx, foot_y, false, healed and C.green or nil)
      Ui.unit_shadow(cx, foot_y)
      Ui.unit(u, cx, foot_y - 15, 2, C.paper)
      Ui.health_bar(x + 5, y + 36, T.PANEL_W - 10, 4, u.hp, Unit.max_hp(u))
      local level = Unit.level(u)
      local promoted = ch and (ch.level_before or level) < level
      Ui.tooltip.unit_tooltip({ x = x, y = y, w = T.PANEL_W, h = 70 }, u, { width = 248, relics = run.relics })
      if Unit.growth_target(u) then
        local label = Unit.is_mature(u) and I18n.t('ui.mature') or ((u.growth_wins or 0) .. '/' .. Unit.growth_target(u))
        Text.fit_text(label, cx, y + 45, T.PANEL_W - 2, {
          color = promoted and C.green or C.amber,
          align = 'center',
        })
      else
        Ui.unit_plate(cx, y + 45, Unit.attack(u), Unit.defense(u))
      end
      Ui.tooltip.trait_icons(u, cx, y + 59, { align = 'center', relics = run.relics })
    else
      if ch and ch.fallen then
        Ui.icon('x', cx, foot_y - 4, 1, C.red)
        Text.fit_text(I18n.t('common.lost'), cx, y + 45, T.PANEL_W, { color = C.red, align = 'center' })
      else
        Ui.slot_marker(cx, foot_y, true)
      end
    end
  end

  local cont_label = fuse_rewound and I18n.t('result.fuse_continue') or I18n.t('common.continue')
  Ui.button_rect(CONTINUE, cont_label, { primary = true, color = C.white, sub = 'ENTER' }, App.mouse)
  Ui.footer(I18n.t('result.footer', run.wave, #Encounters.WAVES, run.seed), I18n.t('result.hint'))
end

return Result
