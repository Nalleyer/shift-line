-- Run ending screen (victory / defeat): final stats, surviving line, and restart actions.
local Encounters = require('data.encounters')
local Unit = require('core.unit')
local App = require('app')
local Audio = require('platform.audio')
local I18n = require('i18n')
local Ui = require('ui')

local T = Ui.theme
local C = Ui.C
local Text = Ui.text

local Ending = { t = 0, mood = 'victory', motes = {} }

local ACTION_Y, ACTION_W, ACTION_H = 235, 100, 26
local ACTIONS = {
  { x = 32, label = 'ending.new_run', shortcut = 'ENTER', key = 'return' },
  { x = 142, label = 'ending.same_seed', shortcut = 'R', key = 'r' },
  { x = 252, label = 'battle.quit_title', shortcut = 'ESC', key = 'escape' },
}

local function action_rect(action)
  return { x = action.x, y = ACTION_Y, w = ACTION_W, h = ACTION_H }
end

function Ending:enter(mood)
  self.mood = mood or (App.run and App.run.phase) or 'defeat'
  self.t = 0
  self.run = App.run
  self.motes = {}
  Audio.stop_music()
  if self.mood == 'victory' then
    Audio.play('win', 1)
    for i = 1, 40 do
      self.motes[i] = {
        x = love.math.random() * T.W,
        y = love.math.random() * T.H - T.H,
        v = 8 + love.math.random() * 26,
        c = ({ C.amber, C.green, C.paper, C.red })[love.math.random(1, 4)],
      }
    end
  else
    Audio.play('lose', 1)
  end
end

function Ending:restart(new_seed)
  local seed = new_seed and App.new_seed() or (self.run and self.run.seed) or App.seed
  Audio.play('ui_select')
  App.start_run(seed)
end

function Ending:keypressed(key)
  if key == 'return' or key == 'space' or key == 'kpenter' then
    self:restart(true)
  elseif key == 'r' then
    self:restart(false)
  elseif key == 'escape' then
    App.go('title')
  end
end

function Ending:mousepressed(x, y, button)
  if button ~= 1 then
    return
  end
  for _, action in ipairs(ACTIONS) do
    if Ui.hit(action_rect(action), x, y) then
      self:keypressed(action.key)
      return
    end
  end
end

function Ending:update(dt)
  self.t = self.t + dt
  for _, m in ipairs(self.motes) do
    m.y = m.y + m.v * dt
    if m.y > T.H + 4 then
      m.y = -4
      m.x = love.math.random() * T.W
    end
  end
end

local function stat_row(y, label, value, col)
  Text.text(label, 96, y, { color = C.dim })
  Text.text(value, 292, y, { color = col or C.paper, align = 'right' })
end

function Ending:draw()
  Ui.wipe(1)
  local run = self.run
  local won = self.mood == 'victory'
  if run then
    App.draw_topbar()
  end

  if won then
    for _, m in ipairs(self.motes) do
      Ui.rect(m.x, m.y, 2, 2, m.c, 0.8)
    end
  end

  local band = won and C.amber or C.red
  Ui.hline(0, 0, T.W, band, 0.5)
  Ui.hline(0, 1, T.W, band, 0.2)

  local title = won and I18n.t('ending.win') or I18n.t('ending.lose')
  local title_y = Ui.cjk and 24 or 28
  Text.text(title, T.W / 2, title_y, { scale = 3, align = 'center', color = won and C.white or C.red })
  Text.text(I18n.t(won and 'ending.win_sub' or 'ending.lose_sub', run.wave), T.W / 2, Ui.cjk and 63 or 56, {
    color = won and C.amber or C.dim,
    align = 'center',
  })

  Ui.hline(72, Ui.cjk and 79 or 73, 240, C.line, 0.7)

  if not won then
    local reason
    if run.core <= 0 then
      reason = I18n.t('ending.reason_core')
    elseif run:alive_count() == 0 then
      reason = I18n.t('ending.reason_last')
    elseif run.last and run.last.reason == 'core' then
      reason = I18n.t('ending.reason_core_wave', run.wave)
    elseif run.last and run.last.reason == 'overrun' then
      reason = I18n.t('ending.reason_overrun')
    else
      reason = I18n.t('ending.reason_wiped')
    end
    Text.text(reason, T.W / 2, Ui.cjk and 83 or 79, { color = C.dim, align = 'center' })
  end

  local y0 = Ui.cjk and (won and 87 or 98) or (won and 84 or 94)
  local step = Ui.cjk and 15 or 13
  stat_row(y0, I18n.t('ending.waves'), run.stats.waves_cleared .. ' / ' .. #Encounters.WAVES)
  stat_row(y0 + step, I18n.t('ending.units'), tostring(run.stats.units_lost))
  stat_row(y0 + step * 2, I18n.t('ending.breaches'), tostring(run.stats.enemies_escaped))
  stat_row(y0 + step * 3, I18n.t('ending.items'), tostring(run.stats.items_used or 0))
  stat_row(y0 + step * 4, I18n.t('ending.fuses'), tostring(run.stats.fuses_used or 0))

  local ry = 176
  local foot_y = 207
  for i = 1, 6 do
    local u = run.roster[i]
    local x = T.col_x(i)
    local cx = T.col_cx(i)
    if u then
      Ui.unit_shadow(cx, foot_y)
      Ui.unit(u, cx, foot_y - 15, 2, C.paper)
      Ui.health_bar(x + 5, 212, T.PANEL_W - 10, 4, u.hp, Unit.max_hp(u))
      Ui.tooltip.unit_tooltip({ x = x, y = ry, w = T.PANEL_W, h = 50 }, u, { relics = run.relics })
      Ui.tooltip.trait_icons(u, cx, 221, { align = 'center', relics = run.relics })
    else
      Ui.slot_marker(cx, foot_y, true)
    end
  end

  for i, action in ipairs(ACTIONS) do
    Ui.button_rect(action_rect(action), I18n.t(action.label), {
      primary = i == 1,
      sub = action.shortcut,
    }, App.mouse)
  end
  Text.text(I18n.t('common.seed', run.seed), T.W / 2, 268, { color = C.dim, align = 'center' })
end

return Ending
