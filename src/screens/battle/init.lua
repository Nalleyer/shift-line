-- Battle screen controller: combat phase orchestration, player input, item modals, and pause menu.
local Constants = require('data.constants')
local Items = require('data.items')
local Util = require('core.util')
local BattleRules = require('core.battle')
local App = require('app')
local Audio = require('platform.audio')
local Settings = require('platform.settings')
local I18n = require('i18n')
local Ui = require('ui')
local Fx = require('screens.battle.fx')
local Timeline = require('screens.battle.timeline')
local Render = require('screens.battle.render')

local T = Ui.theme

local Battle = {}

function Battle:ui_context()
  local interactive = (self.phase == 'choose' or self.phase == 'intervene') and not self.paused and not self.modal
  return {
    battle = self.state,
    can_use_actives = interactive,
    modal = self.modal ~= nil,
    allow_inspect = interactive,
    suppress_tooltips = self.paused or self.modal ~= nil or self.phase == 'playback' or self.phase == 'intro',
    tooltip_style = 'battle_dock',
  }
end

function Battle:enter()
  self.run = App.run
  self.t = 0
  self.phase = 'intro'
  self.intro_t = 0
  self.clock = 0
  self.frame_i = 1
  self.frames = {}
  self.total = 0
  self.result = nil
  self.state = self.run:start_battle(0)
  self.modal = nil
  self.battle_gold = 0
  self.message = nil

  local encounter = self.run:encounter()
  self.boss_max = type(encounter) == 'table' and encounter.boss and (encounter.boss_hp or 14) or nil
  self.boss_hp = self.boss_max
  self.paused = false
  self.quit_confirm = false
  self.hover = nil
  self.range_pulse = 0
  self.committed = false
  self.victory_flash = false

  self.line = Util.deep_copy(self.state.line)
  self.enemies = Util.deep_copy(self.state.enemies)
  self.core_view = self.run.core
  self.charge_view = self.state.charge or self.run.charge or 0
  self.pressure_view = 0
  self.round_no = 0
  self.fx = Fx.new()

  Audio.music(self.state.boss and 'boss' or 'battle')
  Audio.play('wave_start', 0.7)
end

function Battle:leave() end

function Battle:pattern()
  return self.run:pattern()
end

function Battle:toggle_language()
  Settings.set_locale(I18n.other_locale())
  Ui.set_locale(I18n.locale)
  Audio.play('ui_select')
end

function Battle:activate_pause(i)
  if i == 1 then
    self.paused = false
    Audio.play('ui_select')
  elseif i == 2 then
    self:toggle_language()
  else
    self.quit_confirm = true
    Audio.play('ui_select')
  end
end

function Battle:range_denied()
  self.range_pulse = 0.4
  Audio.play('ui_deny', 0.7)
end

function Battle:try_shift(dir)
  if self.modal or self.paused then
    return false
  end
  local kind = self.phase == 'choose' and 'deploy_shift'
    or self.phase == 'intervene' and (self.state.boss_shift and 'boss_shift' or self.state.navigator_available and 'navigator_shift')
  if not kind then
    return false
  end
  local ok = BattleRules.command(self.state, { type = kind, delta = dir })
  if ok then
    self.line, self.enemies = self.fx:begin_reposition(self.line, self.enemies, self.state.line, self.state.enemies, dir, 'player')
    Audio.play('shift', 0.85)
  else
    self:range_denied()
  end
  return ok
end

function Battle:try_charge_shift(dir)
  if self.modal or self.paused or self.phase ~= 'intervene' then
    return false
  end
  if not self.state or (self.state.charge or 0) < 1 then
    self:range_denied()
    return false
  end
  local ok = BattleRules.command(self.state, { type = 'charge_shift', delta = dir })
  if ok then
    self.line, self.enemies = self.fx:begin_reposition(self.line, self.enemies, self.state.line, self.state.enemies, dir, 'player')
    self.core_view = self.state.core
    self.charge_view = self.state.charge
    Audio.play('shift', 0.85)
  else
    self:range_denied()
  end
  return ok
end

function Battle:build_frames(events)
  return Timeline.build_frames(events)
end

function Battle:apply_frame(frame)
  Timeline.apply_frame(self, frame)
end

function Battle:play_segment(events)
  self.phase = 'playback'
  self.frames, self.total = self:build_frames(events or {})
  self.clock, self.frame_i = 0, 1
end

function Battle:try_fight()
  if self.phase ~= 'choose' or self.modal then
    return
  end
  self:play_segment(BattleRules.step(self.state))
  Audio.play('fight')
end

function Battle:continue_round()
  if self.phase ~= 'intervene' or self.modal then
    return
  end
  self.message = nil
  self:play_segment(BattleRules.step(self.state))
end

function Battle:use_item(index)
  if self.modal or self.paused or (self.phase ~= 'choose' and self.phase ~= 'intervene') then
    return false
  end
  local ok, reason = BattleRules.can_use_item(self.state, index)
  local id = self.state.inventory[index]
  local def = Items.ACTIVES[id]
  if not ok then
    local message = I18n.reason(reason) or I18n.t('battle.cannot_use')
    if def and def.effect == 'shift' and reason == 'unavailable' and self.state.round_no == 0 then
      message = I18n.t('battle.shift_between_rounds')
    end
    App.show_toast(message)
    Audio.play('ui_deny', 0.7)
    return false
  end
  if def.effect == 'shift' and not BattleRules.command(self.state, { type = 'item', index = index }) then
    return false
  end
  self.modal = {
    kind = 'item',
    index = index,
    id = id,
    def = def,
    remaining = def.steps,
    delta = 0,
    targets = BattleRules.item_targets(self.state, index) or {},
  }
  return true
end

function Battle:shift_item_step(dir)
  local m = self.modal
  if self.paused or not m or not m.def or m.def.effect ~= 'shift' then
    return false
  end
  if not BattleRules.command(self.state, { type = 'shift_step', delta = dir }) then
    self:range_denied()
    return false
  end
  m.delta = self.state.shift_moves.delta
  m.remaining = self.state.shift_moves.remaining
  self.line, self.enemies = self.fx:begin_reposition(self.line, self.enemies, self.state.line, self.state.enemies, dir, 'player')
  Audio.play('shift', 0.85)
  return true
end

function Battle:close_modal(confirm)
  local m = self.modal
  if m and m.def and m.def.effect == 'shift' then
    if not BattleRules.command(self.state, { type = confirm and 'shift_finish' or 'shift_cancel' }) then
      return false
    end
    if not confirm then
      self.line, self.enemies = self.fx:begin_reposition(self.line, self.enemies, self.state.line, self.state.enemies, -m.delta, 'player')
    end
  end
  self.modal = nil
  return true
end

function Battle:modal_ready()
  local m = self.modal
  if not m then
    return false
  end
  local effect = m.def.effect
  if effect == 'swap' then
    return false
  end
  if effect == 'heal' or effect == 'attack' or effect == 'defense' then
    return m.target ~= nil
  end
  return true
end

function Battle:confirm_modal()
  local m = self.modal
  if not self:modal_ready() then
    return false
  end
  if m.def and m.def.effect == 'shift' then
    return self:close_modal(true)
  end
  local ok, events, reason = BattleRules.command(self.state, {
    type = 'item',
    index = m.index,
    target = m.target,
    delta = m.delta,
  })
  if not ok then
    self.message = I18n.reason(reason) or I18n.t('battle.cannot_use')
    return false
  end
  self.modal = nil
  self:play_segment(events)
  return true
end

function Battle:skip_playback()
  while self.frame_i <= #self.frames do
    self:apply_frame(self.frames[self.frame_i])
    self.frame_i = self.frame_i + 1
  end
  self.clock = self.total
end

function Battle:finish()
  if self.phase ~= 'playback' then
    return
  end
  self.message = nil
  self.line = Util.deep_copy(self.state.line)
  self.enemies = Util.deep_copy(self.state.enemies)
  self.core_view = self.state.core
  self.charge_view = self.state.charge or self.charge_view
  self.pressure_view = self.state.pressure or 0
  self.boss_hp, self.boss_max = self.state.boss_hp, self.state.boss_max
  if self.state.done then
    self.phase = 'done'
    if not self.committed then
      self.committed = true
      self.result = BattleRules.result(self.state)
      self.run:commit(self.result)
    end
    App.go('result')
  else
    self.phase = self.state.round_no == 0 and 'choose' or 'intervene'
  end
end

function Battle:update_hover()
  local mx, my = App.mouse.x, App.mouse.y
  self.hover = nil
  if self.paused or self.modal or self.phase == 'playback' or self.phase == 'intro' then
    return
  end
  if mx < T.COL_X0 or mx > T.COL_X0 + Constants.SLOTS * T.COL_STEP then
    return
  end
  local col = math.floor((mx - T.COL_X0) / T.COL_STEP) + 1
  if col < 1 or col > Constants.SLOTS or mx > T.col_x(col) + T.PANEL_W then
    return
  end
  if my >= T.ENEMY_Y and my < T.ENEMY_Y + T.PANEL_H and self.enemies[col] then
    self.hover = { side = 'enemy', col = col }
  elseif my >= T.PLAYER_Y and my < T.PLAYER_Y + T.PANEL_H and self.line[col] then
    self.hover = { side = 'player', col = col }
  end
end

local function intervene_shift(self, dir)
  if self.state.boss_shift or self.state.navigator_available then
    self:try_shift(dir)
  elseif (self.state.charge or 0) >= 1 then
    self:try_charge_shift(dir)
  else
    self:try_shift(dir)
  end
end

local function commit_swap_item(self, m, from, to)
  local ok, events, reason = BattleRules.command(self.state, {
    type = 'item',
    index = m.index,
    from = from,
    to = to,
  })
  if ok then
    self.modal = nil
    self:play_segment(events)
  else
    self.message = I18n.reason(reason) or I18n.t('battle.cannot_use')
    Audio.play('ui_deny')
  end
end

function Battle:keypressed(key)
  if self.paused then
    if self.quit_confirm then
      local action = Ui.dialogs.quit_confirm.keypressed(key)
      if action == 'confirm' then
        self.quit_confirm = false
        App.go('title')
      elseif action == 'cancel' then
        self.quit_confirm = false
      end
      return
    end
    if key == 'escape' then
      self.paused = false
    end
    return
  end

  if self.modal then
    local m = self.modal
    if m.def and m.def.effect == 'swap' then
      if key == 'escape' or key == 'backspace' then
        if m.swap_from then
          m.swap_from = nil
          Audio.play('ui_move')
        else
          self:close_modal()
        end
      end
      return
    end
    if key == 'escape' then
      self:close_modal()
    elseif key == 'return' or key == 'space' or key == 'kpenter' then
      self:confirm_modal()
    elseif m.def and m.def.effect == 'shift' and (key == 'left' or key == 'a' or key == 'right' or key == 'd') then
      self:shift_item_step((key == 'left' or key == 'a') and -1 or 1)
    end
    return
  end

  if key == 'escape' then
    self.paused = true
    Audio.play('ui_select', 0.7)
    return
  end

  if self.phase == 'intro' then
    if key == 'return' or key == 'space' or key == 'a' or key == 'd'
      or key == 'left' or key == 'right' or key == 'kpenter' then
      self.intro_t = 99
    end
    return
  end

  if self.phase == 'choose' then
    if key == '1' or key == '2' or key == '3' then
      self:use_item(tonumber(key))
    elseif key == 'a' or key == 'left' then
      self:try_shift(-1)
    elseif key == 'd' or key == 'right' then
      self:try_shift(1)
    elseif key == 'return' or key == 'space' or key == 'kpenter' then
      self:try_fight()
    end
  elseif self.phase == 'intervene' then
    if key == 'return' or key == 'space' or key == 'kpenter' then
      self:continue_round()
    elseif key == '1' or key == '2' or key == '3' then
      self:use_item(tonumber(key))
    elseif key == 'q' then
      self:try_charge_shift(-1)
    elseif key == 'e' then
      self:try_charge_shift(1)
    elseif key == 'a' or key == 'left' then
      intervene_shift(self, -1)
    elseif key == 'd' or key == 'right' then
      intervene_shift(self, 1)
    end
  elseif self.phase == 'playback' and (key == 's' or key == 'tab') then
    self:skip_playback()
  end
end

function Battle:mousepressed(x, y, button)
  if button ~= 1 then
    return
  end

  if self.paused then
    if self.quit_confirm then
      local action = Ui.dialogs.quit_confirm.mousepressed(x, y, button)
      if action == 'confirm' then
        self.quit_confirm = false
        Audio.play('ui_select')
        App.go('title')
      elseif action == 'cancel' then
        self.quit_confirm = false
        Audio.play('ui_move')
      end
      return
    end
    local hit_i = Render.pause_hover_index(App.mouse)
    if hit_i then
      self:activate_pause(hit_i)
    end
    return
  end

  if self.modal then
    local m = self.modal
    if y >= T.PLAYER_Y and y < T.PLAYER_Y + T.PANEL_H then
      local col = math.floor((x - T.COL_X0) / T.COL_STEP) + 1
      if col >= 1 and col <= Constants.SLOTS and x <= T.col_x(col) + T.PANEL_W then
        if m.def and m.def.effect == 'swap' then
          if m.swap_from then
            if col == m.swap_from then
              m.swap_from = nil
              Audio.play('ui_move')
            else
              commit_swap_item(self, m, m.swap_from, col)
            end
          elseif self.state.line[col] then
            m.drag_from = col
          end
        else
          for _, target in ipairs(m.targets or {}) do
            if target == col then
              m.target = col
            end
          end
        end
      end
    elseif y >= 207 and y <= 228 and m.def and m.def.effect == 'shift' then
      if x >= 26 and x <= 128 then
        self:shift_item_step(-1)
      elseif x >= 256 and x <= 358 then
        self:shift_item_step(1)
      end
    elseif y >= 231 and y <= 253 then
      if x >= 205 and x <= 337 then
        self:confirm_modal()
      elseif x >= 47 and x <= 179 then
        self:close_modal()
      end
    end
    return
  end

  if Render.pause_button_hit(x, y) then
    self.paused = true
    Audio.play('ui_select', 0.7)
    return
  end

  if self.phase == 'playback' then
    self:skip_playback()
    return
  end
  if self.phase == 'intro' then
    self.intro_t = 99
    return
  end

  local name = Render.button_at(self, x, y)
  if self.phase == 'intervene' then
    if name == 'fight' then
      self:continue_round()
    elseif name == 'left' then
      self:try_shift(-1)
    elseif name == 'right' then
      self:try_shift(1)
    elseif name == 'charge_left' then
      self:try_charge_shift(-1)
    elseif name == 'charge_right' then
      self:try_charge_shift(1)
    end
    return
  end

  if self.phase == 'choose' then
    if name == 'fight' then
      self:try_fight()
    elseif name == 'left' then
      self:try_shift(-1)
    elseif name == 'right' then
      self:try_shift(1)
    end
  end
end

function Battle:mousereleased(x, y, button)
  local m = self.modal
  if button ~= 1 or not m or not m.drag_from then
    return
  end
  local from = m.drag_from
  m.drag_from = nil
  local to = math.floor((x - T.COL_X0) / T.COL_STEP) + 1
  if y < T.PLAYER_Y or y >= T.PLAYER_Y + T.PANEL_H or to < 1 or to > Constants.SLOTS or x > T.col_x(to) + T.PANEL_W then
    return
  end
  if to == from then
    m.swap_from = from
    Audio.play('ui_select')
    return
  end
  commit_swap_item(self, m, from, to)
end

function Battle:update(dt)
  self.t = self.t + dt
  if self.paused then
    return
  end

  if self.phase == 'intro' then
    self.intro_t = self.intro_t + dt
    if self.intro_t > 1.15 then
      self.phase = 'choose'
    end
  end

  self.range_pulse = math.max(0, (self.range_pulse or 0) - dt)

  if self.phase == 'playback' then
    local speed = love.keyboard.isDown('space') and 3 or 1
    self.clock = self.clock + dt * speed
    while self.frame_i <= #self.frames and self.frames[self.frame_i].t <= self.clock do
      self:apply_frame(self.frames[self.frame_i])
      self.frame_i = self.frame_i + 1
    end
    if self.clock >= self.total then
      self:finish()
      return
    end
  end

  self.fx:update(dt)
  self:update_hover()
end

function Battle:draw()
  Render.draw(self, App.mouse)
end

return Battle
