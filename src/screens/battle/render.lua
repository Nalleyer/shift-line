-- Battle board, lanes, target buses, action buttons, modals, intro banner, and pause menu rendering.
local Constants = require('data.constants')
local Encounters = require('data.encounters')
local Unit = require('core.unit')
local App = require('app')
local I18n = require('i18n')
local Ui = require('ui')
local Fx = require('screens.battle.fx')

local T = Ui.theme
local C = Ui.C
local Text = Ui.text

local Render = {}

local CHOOSE_BTNS = {
  left  = { x = 40,  w = 88, key = 'battle.shift_left' },
  fight = { x = 148, w = 88, key = 'battle.fight' },
  right = { x = 256, w = 88, key = 'battle.shift_right' },
}

local function buttons_y()
  return T.BTN_Y + (Ui.cjk and 2 or 0)
end

local function buttons_h()
  return 26
end

function Render.intervene_rects(battle)
  local by, bh = buttons_y(), buttons_h()
  local state = battle.state or {}
  local out = {
    fight = { x = 152, y = by, w = 80, h = bh },
  }
  if state.boss_shift or state.navigator_available then
    out.left = { x = 74, y = by, w = 72, h = bh }
    out.right = { x = 238, y = by, w = 72, h = bh }
  end
  if (state.charge or 0) >= 1 then
    out.charge_left = { x = 8, y = by, w = 62, h = bh }
    out.charge_right = { x = 314, y = by, w = 62, h = bh }
  end
  return out
end

function Render.button_at(battle, x, y)
  if battle.phase == 'intervene' then
    for name, b in pairs(Render.intervene_rects(battle)) do
      if Ui.hit(b, x, y) then
        return name
      end
    end
    return nil
  end
  local by, bh = buttons_y(), buttons_h()
  for name, b in pairs(CHOOSE_BTNS) do
    if x >= b.x and x <= b.x + b.w and y >= by and y <= by + bh then
      return name
    end
  end
  return nil
end

function Render.pause_button_rect()
  return T.W - 92, T.FOOT_Y + 4, 80, T.H - T.FOOT_Y - 8
end

function Render.pause_button_hit(x, y)
  return x >= T.W - 100 and x <= T.W and y >= T.FOOT_Y and y <= T.H
end

function Render.pause_panel_rect()
  local w, h = Ui.cjk and 210 or 190, Ui.cjk and 132 or 120
  local x = T.W / 2 - w / 2
  local y = math.floor((T.H - h) / 2) - 10
  local first = y + (Ui.cjk and 50 or 48)
  local step = Ui.cjk and 22 or 20
  return x, y, w, h, first, step
end

function Render.pause_entries()
  return {
    I18n.t('battle.resume'),
    I18n.t('battle.language', I18n.language_name()),
    I18n.t('battle.quit_title'),
  }
end

function Render.pause_hover_index(mouse)
  local mx, my = mouse.x, mouse.y
  local px, _, pw, _, first, step = Render.pause_panel_rect()
  for i = 1, #Render.pause_entries() do
    local iy = first + (i - 1) * step
    if mx >= px + 6 and mx <= px + pw - 6 and my >= iy - 4 and my <= iy + step - 2 then
      return i
    end
  end
  return nil
end

local function hovered_ally_highlights(battle)
  local attack, support = {}, {}
  if not battle.modal and not battle.paused and battle.hover and battle.hover.side == 'player' then
    local source = battle.line[battle.hover.col]
    if source then
      for _, col in ipairs(Unit.attack_targets(source, battle.hover.col, battle.enemies)) do
        attack[col] = true
      end
      local guard = Unit.trait(source, 'guard')
      local heal = Unit.trait(source, 'heal')
      local charge_aura = Unit.trait(source, 'charge_aura')
      if guard or heal or charge_aura then
        local active_aura = charge_aura and (battle.state and battle.state.charge or 0) >= (charge_aura.aura_min or 2)
        local col_hl = guard and C.blue or (heal and C.green or (active_aura and C.amber or C.dim))
        for _, col in ipairs(Unit.support_targets(battle.line, battle.hover.col, battle.run.relics or {})) do
          if battle.line[col] then
            support[col] = col_hl
          end
        end
      end
    end
  end
  return attack, support
end

local function hovered_enemy_targets(battle)
  local targets = {}
  if battle.hover and battle.hover.side == 'enemy' and not battle.paused and not battle.modal then
    local col = battle.hover.col
    local enemy = battle.enemies[col]
    if enemy then
      local target = Unit.taunt_target(battle.line, col) or col
      targets[target] = C.red
      if (battle.line[col] or target ~= col) and Unit.trait(enemy, 'splash') then
        if col > 1 and battle.line[col - 1] then
          targets[col - 1] = C.red
        end
        if col < Constants.SLOTS and battle.line[col + 1] then
          targets[col + 1] = C.red
        end
      end
    end
  end
  return targets
end

local function modal_pad_highlights(battle, mouse)
  local hl = {}
  local m = battle.modal
  if not m then
    return hl
  end
  local hover_col
  if mouse.y >= T.PLAYER_Y and mouse.y < T.PLAYER_Y + T.PANEL_H then
    local col = math.floor((mouse.x - T.COL_X0) / T.COL_STEP) + 1
    if col >= 1 and col <= Constants.SLOTS and mouse.x <= T.col_x(col) + T.PANEL_W then
      hover_col = col
    end
  end
  for _, col in ipairs(m.targets or {}) do
    hl[col] = col == m.target and C.amber or (col == hover_col and C.white or C.green)
  end
  local effect = m.def and m.def.effect
  if effect == 'swap' then
    local active_from = m.drag_from or m.swap_from
    if active_from then
      hl[active_from] = C.amber
      if hover_col and hover_col ~= active_from then
        hl[hover_col] = C.green
      end
    elseif hover_col and battle.state.line[hover_col] then
      hl[hover_col] = C.green
    end
  end
  return hl
end

local function draw_breach_marker(x, cx, incoming, pulse)
  local p = pulse or 0.7
  Ui.rect(x + 3, T.PLAYER_Y + 8, T.PANEL_W - 6, T.PANEL_H - 18, C.amber, 0.05 * p)
  Ui.icon('arrowD', cx, T.PLAYER_Y + 18, 1, C.amber, 0.65 + 0.35 * p)
  Ui.icon_text('heart', '-' .. incoming, cx, T.PLAYER_Y + 28, { align = 'center', color = C.amber })
end

local function draw_target_bus(source_cx, targets, y, dir, col)
  local min_x, max_x, count = source_cx, source_cx, 0
  for i = 1, Constants.SLOTS do
    if targets[i] then
      local tx = T.col_cx(i)
      min_x = math.min(min_x, tx)
      max_x = math.max(max_x, tx)
      count = count + 1
    end
  end
  if count == 0 then
    return
  end
  Ui.vline(source_cx, dir < 0 and y or (y - 3), 4, col, 0.9)
  Ui.hline(min_x, y, max_x - min_x + 1, col, 0.85)
  for i = 1, Constants.SLOTS do
    if targets[i] then
      local tx = T.col_cx(i)
      Ui.vline(tx, dir < 0 and (y - 3) or y, 4, col, 0.95)
      Ui.rect(tx - 1, dir < 0 and (y - 3) or (y + 2), 3, 2, col, 0.95)
    end
  end
end

function Render.draw_panel(battle, col, x, y, side, unit, extra)
  extra = extra or {}
  local w, h = T.PANEL_W, T.PANEL_H
  local cx = x + w / 2
  local enemy = side == 'enemy'
  local encounter = battle.run:encounter()
  local boss_part = enemy and type(encounter) == 'table' and encounter.boss
  local foot_y = y + (enemy and (boss_part and 43 or 41) or 35)
  local fx = battle.fx
  local flash = fx.hit_flash[side][col] or 0
  local alpha = extra.alpha or 1

  Ui.unit_shadow(cx, foot_y, 18, 0.6 * alpha)

  local bob = math.sin(battle.t * 2.2 + col * 0.9) > 0.6 and -1 or 0
  local colr = enemy and C.red or C.paper
  if flash > 0 then
    colr = (not enemy and (fx.heal_flash[col] or 0) > 0) and C.green or C.white
  end
  local actor = fx.actor
  local lunge = actor and actor.side == side and actor.col == col and math.sin(math.min(1, actor.t / 0.32) * math.pi) * 7 or 0
  if lunge > 0 then
    colr = actor.kind == 'heal' and C.green or C.white
  end
  local unit_cy = y + (enemy and (boss_part and 27 or 25) or 19) + bob + (enemy and lunge or -lunge)
  Ui.unit(unit, cx, unit_cy, 2, colr, alpha)

  local hp = unit.hp
  local max = unit.max or (not enemy and Unit.max_hp(unit)) or unit.max_hp or 1
  if boss_part then
    Text.text(I18n.t(unit.kind == 'c' and 'battle.core' or 'battle.arm'), cx, y - 1, {
      color = C.paper,
      align = 'center',
      alpha = alpha,
    })
  else
    local hp_y = y + (enemy and 1 or 41)
    Ui.health_bar(x + 5, hp_y, w - 10, 4, hp, max, { alpha = alpha })
  end

  local atk = enemy and ((unit.atk or 0) + (battle.pressure_view or 0))
    or (Unit.attack(unit, battle.state) + Unit.support_attack_bonus(battle.state, col))
  local def = Unit.defense(unit)
  Ui.unit_plate(cx, y + (enemy and (boss_part and 49 or 47) or 51), atk, def, { alpha = alpha })

  if not battle.modal and not battle.paused and battle.phase ~= 'playback' and battle.phase ~= 'intro' then
    Ui.tooltip.unit_tooltip({ x = x, y = y, w = w, h = h }, unit, {
      line = not enemy and battle.line or nil,
      state = battle.state,
      col = col,
      relics = battle.run.relics,
    })
  end
  Ui.tooltip.trait_icons(unit, cx, y + (enemy and (boss_part and 59 or 57) or 60), {
    align = 'center',
    relics = battle.run.relics,
  })
end

local function draw_moving_panel(battle, col, side, unit, extra)
  local y = side == 'enemy' and T.ENEMY_Y or T.PLAYER_Y
  local motion = battle.fx.motion
  local moving = motion and motion[side][Fx.actor_key(unit, col)]
  if not moving then
    Render.draw_panel(battle, col, T.col_x(col), y, side, unit, extra)
    return
  end

  local e = Ui.ease_out(motion.t / motion.duration)
  local x = moving.from + (moving.to - moving.from) * e
  local sx, sy, sw, sh = love.graphics.getScissor()
  local left, top = love.graphics.transformPoint(T.COL_X0, y - 1)
  love.graphics.intersectScissor(left, top, 6 * T.COL_STEP - 8, T.PANEL_H + 2)
  for _, offset in ipairs({ -6 * T.COL_STEP, 0, 6 * T.COL_STEP }) do
    local draw_x = x + offset
    if draw_x + T.PANEL_W > T.COL_X0 and draw_x < T.COL_X0 + 6 * T.COL_STEP - 8 then
      Render.draw_panel(battle, col, draw_x, y, side, unit, extra)
    end
  end
  if sx then
    love.graphics.setScissor(sx, sy, sw, sh)
  else
    love.graphics.setScissor()
  end
end

local function draw_front_line(battle)
  local y = T.FRONT_Y + 3
  Ui.hline(0, y, T.W, C.line, 0.14, 8)
  Ui.hline(T.COL_X0 - 4, y, 6 * T.COL_STEP, C.line, 0.35)

  for i = 1, Constants.SLOTS do
    local cx = T.col_cx(i)
    local breaking = battle.enemies[i]
      and not battle.line[i]
      and not Unit.taunt_target(battle.line, i)
      and Unit.breach_amount(battle.enemies[i]) > 0
    if breaking then
      local pulse = 0.5 + 0.35 * math.sin(battle.t * 6 + i)
      Ui.vline(cx, y - 3, 8, C.amber, pulse)
      Ui.hline(cx - 5, y, 11, C.amber, pulse)
      Ui.rect(cx - 1, y - 1, 3, 3, C.amber, pulse)
      Ui.vline(cx, y + 5, T.PLAYER_Y + 13 - (y + 5), C.amber, 0.35 * pulse, 4)
    else
      Ui.vline(cx, y - 2, 5, C.line, 0.45)
      Ui.hline(cx - 4, y, 9, C.line, 0.5)
    end
  end

  if battle.modal or battle.paused or not battle.hover then
    return
  end

  if battle.hover.side == 'player' then
    local attack, support = hovered_ally_highlights(battle)
    local sx = T.col_cx(battle.hover.col)
    draw_target_bus(sx, attack, y, -1, C.amber)

    local s_min, s_max, scol = sx, sx, nil
    for i = 1, Constants.SLOTS do
      if support[i] then
        local tx = T.col_cx(i)
        s_min = math.min(s_min, tx)
        s_max = math.max(s_max, tx)
        scol = support[i]
      end
    end
    if scol then
      local sy = T.PLAYER_Y - 2
      Ui.hline(s_min, sy, s_max - s_min + 1, scol, 0.85)
      Ui.vline(sx, sy, 3, scol, 0.9)
      for i = 1, Constants.SLOTS do
        if support[i] then
          local tx = T.col_cx(i)
          Ui.vline(tx, sy, 3, scol, 0.95)
          Ui.rect(tx - 1, sy + 1, 3, 2, scol, 0.95)
        end
      end
    end
  elseif battle.hover.side == 'enemy' then
    draw_target_bus(T.col_cx(battle.hover.col), hovered_enemy_targets(battle), y, 1, C.red)
  end
end

local function draw_enemy_row(battle)
  local coverage = hovered_ally_highlights(battle)
  local inspecting_ally = battle.hover and battle.hover.side == 'player'
  local enc = battle.run:encounter()
  local foot_y = T.ENEMY_Y + (type(enc) == 'table' and enc.boss and 43 or 41)

  for i = 1, Constants.SLOTS do
    local u = battle.enemies[i]
    local cx = T.col_cx(i)
    local hovered = not battle.modal and not battle.paused and battle.hover and battle.hover.side == 'enemy' and battle.hover.col == i
    local breaking = not inspecting_ally and u and not battle.line[i] and not Unit.taunt_target(battle.line, i) and Unit.breach_amount(u) > 0
    local color = hovered and C.white or ((coverage[i] or breaking) and C.amber or nil)
    Ui.slot_marker(cx, foot_y, not u, color)
  end

  for i = 1, Constants.SLOTS do
    local u = battle.enemies[i]
    if u then
      draw_moving_panel(battle, i, 'enemy', u)
    end
  end
end

local function draw_boss_bar(battle)
  local enc = battle.run:encounter()
  if type(enc) ~= 'table' or not enc.boss then
    return
  end
  local max = battle.boss_max or enc.boss_hp or 14
  local hp = battle.boss_hp or max
  Ui.health_bar(T.COL_X0, 101, 6 * T.COL_STEP - 8, 4, hp, max)
end

local function draw_player_row(battle, mouse)
  local _, support = hovered_ally_highlights(battle)
  for col, color in pairs(hovered_enemy_targets(battle)) do
    support[col] = color
  end
  local modal_hl = modal_pad_highlights(battle, mouse)
  local foot_y = T.PLAYER_Y + 35

  for i = 1, Constants.SLOTS do
    local lf = battle.fx.lane_flashes[i]
    if lf then
      local a = math.max(0, 1 - lf.t / lf.life)
      local lx = T.col_x(i)
      Ui.rect(lx + 1, T.PLAYER_Y + 1, T.PANEL_W - 2, T.PANEL_H - 2, lf.col, 0.22 * a)
      Ui.frame(lx, T.PLAYER_Y, T.PANEL_W, T.PANEL_H, lf.col, 0.85 * a)
    end

    local u = battle.line[i]
    local cx = T.col_cx(i)
    local hl = modal_hl[i] or support[i]
    if not u then
      local incoming = Unit.breach_amount(battle.enemies[i])
      local taunted = battle.enemies[i] and Unit.taunt_target(battle.line, i)
      Ui.slot_marker(cx, foot_y, incoming <= 0 and not taunted, hl)
      if taunted then
        Ui.icon('taunt', cx, T.PLAYER_Y + 31, 1, C.blue)
        if not battle.modal and not battle.paused then
          Ui.tooltip.register(
            { x = T.col_x(i), y = T.PLAYER_Y, w = T.PANEL_W, h = T.PANEL_H },
            I18n.t('trait.taunt.name'),
            I18n.t('battle.taunt_cover', taunted),
            { icon = 'taunt', icon_color = C.blue, color = C.blue }
          )
        end
      elseif incoming > 0 then
        local pulse = 0.55 + 0.45 * math.sin(battle.t * 5 + i)
        draw_breach_marker(T.col_x(i), cx, incoming, pulse)
        if not battle.modal and not battle.paused and battle.phase ~= 'playback' and battle.phase ~= 'intro' then
          local redirected = battle.state.compensation_available
          local key = redirected and 'battle.empty_breach_redirect_tip' or 'battle.empty_breach_tip'
          Ui.tooltip.register(
            { x = T.col_x(i), y = T.PLAYER_Y, w = T.PANEL_W, h = T.PANEL_H },
            I18n.t('battle.to_core'),
            I18n.t(key, incoming),
            {
              icon = redirected and 'compensation' or 'heart',
              icon_color = redirected and C.blue or C.red,
              color = redirected and C.blue or C.red,
            }
          )
        end
      end
    else
      local hovered = not battle.modal and not battle.paused and battle.hover and battle.hover.side == 'player' and battle.hover.col == i
      Ui.slot_marker(cx, foot_y, false, hovered and C.white or hl)
    end
  end

  for i = 1, Constants.SLOTS do
    local u = battle.line[i]
    if u then
      local alpha = (battle.modal and (battle.modal.drag_from == i or battle.modal.swap_from == i)) and 0.35 or 1
      draw_moving_panel(battle, i, 'player', u, { alpha = alpha })
    end
  end
end

local function draw_topbar(battle)
  local charge = battle.charge_view or (battle.state and battle.state.charge) or battle.run.charge
  local charge_max = (battle.state and battle.state.charge_max) or battle.run.charge_max
  App.draw_topbar({
    core = battle.core_view,
    flash = battle.fx.heart_flash,
    gold = (battle.run.gold or 0) + battle.battle_gold,
    charge = charge,
    charge_max = charge_max,
  })
  battle.fx:draw_topbar_overlay(charge, charge_max)
end

local function draw_buttons(battle, mouse)
  local by, bh = buttons_y(), buttons_h()
  local hovered = Render.button_at(battle, mouse.x, mouse.y)
  if battle.phase == 'choose' or battle.phase == 'intervene' then
    local label = I18n.t('battle.next_round', battle.state.round_no + 1)
    if (battle.pressure_view or 0) > 0 then
      label = label .. (I18n.is_zh() and ' · ' or ' / ') .. I18n.t('battle.pressure_tag', battle.pressure_view)
    end
    Text.fit_text(label, T.W / 2, 187, 300, { color = C.amber, align = 'center' })
  end

  if battle.phase == 'intervene' then
    local rects = Render.intervene_rects(battle)
    local boss = battle.state.boss_shift
    local nav = boss or battle.state.navigator_available
    if rects.left and rects.right then
      local limit, position = battle.state.navigator_limit, battle.state.navigator_delta or 0
      Ui.button(rects.left.x, by, rects.left.w, bh, I18n.t('battle.shift_a'), {
        hover = hovered == 'left',
        disabled = not boss and position <= -limit,
      })
      Ui.button(rects.right.x, by, rects.right.w, bh, I18n.t('battle.shift_d'), {
        hover = hovered == 'right',
        disabled = not boss and position >= limit,
      })
    end
    if rects.charge_left and rects.charge_right then
      local lk = (nav and 'Q' or 'A') .. ' <'
      local rk = '> ' .. (nav and 'E' or 'D')
      Ui.button(rects.charge_left.x, by, rects.charge_left.w, bh, lk, {
        hover = hovered == 'charge_left',
        color = C.blue,
        sub = '1',
        sub_icon = 'charge',
      })
      Ui.button(rects.charge_right.x, by, rects.charge_right.w, bh, rk, {
        hover = hovered == 'charge_right',
        color = C.blue,
        sub = '1',
        sub_icon = 'charge',
      })
      if hovered == 'charge_left' then
        Ui.tooltip.register(rects.charge_left, I18n.t('battle.charge_shift'), I18n.t('battle.charge_shift_tip'), {
          icon = 'charge',
          icon_color = C.blue,
          color = C.blue,
        })
      elseif hovered == 'charge_right' then
        Ui.tooltip.register(rects.charge_right, I18n.t('battle.charge_shift'), I18n.t('battle.charge_shift_tip'), {
          icon = 'charge',
          icon_color = C.blue,
          color = C.blue,
        })
      end
    end
    Ui.button(rects.fight.x, by, rects.fight.w, bh, I18n.t('battle.continue'), {
      hover = hovered == 'fight',
      primary = true,
    })
    return
  end

  local avail = battle.phase == 'choose'
  if avail then
    Ui.button(CHOOSE_BTNS.left.x, by, CHOOSE_BTNS.left.w, bh, I18n.t(CHOOSE_BTNS.left.key), {
      hover = hovered == 'left',
    })
    Ui.button(CHOOSE_BTNS.right.x, by, CHOOSE_BTNS.right.w, bh, I18n.t(CHOOSE_BTNS.right.key), {
      hover = hovered == 'right',
    })
  end
  Ui.button(CHOOSE_BTNS.fight.x, by, CHOOSE_BTNS.fight.w, bh, I18n.t(CHOOSE_BTNS.fight.key), {
    hover = hovered == 'fight',
    disabled = not avail,
    primary = true,
  })
end

local function draw_range(battle, text, x, y, width)
  local color = (battle.range_pulse or 0) > 0 and C.red or C.amber
  Text.fit_text(text, x, y, width, { align = 'center', color = color })
end

local function draw_hint(battle)
  if battle.phase == 'intervene' and battle.state.navigator_available and not battle.state.boss_shift then
    draw_range(
      battle,
      I18n.t(
        'battle.navigator_range',
        battle.state.navigator_limit - math.abs(battle.state.navigator_delta or 0),
        battle.state.navigator_limit
      ),
      T.W / 2,
      T.HINT_Y,
      360
    )
    return
  end

  local txt
  local col = C.dim
  if battle.phase == 'intro' then
    txt = I18n.t('battle.get_ready')
  elseif battle.phase == 'choose' then
    txt = I18n.t('battle.hint_choose')
  elseif battle.phase == 'intervene' then
    if battle.state.boss_shift then
      txt = battle.message or I18n.t('battle.hint_boss_shift')
      if not battle.message then
        col = C.amber
      end
    elseif (battle.state.charge or 0) >= 1 then
      txt = battle.message or I18n.t('battle.hint_charge_shift')
    else
      txt = battle.message or I18n.t('battle.hint_intervene')
    end
  elseif battle.phase == 'playback' then
    txt = battle.message or I18n.t('battle.hint_playback')
  else
    txt = I18n.t('battle.report')
  end
  Text.fit_text(txt, T.W / 2, T.HINT_Y, 360, { color = col, align = 'center' })
end

local function draw_footer(battle, mouse)
  local m = battle.modal
  local hint = m and m.def and m.def.effect == 'shift' and I18n.t('battle.shift_cancel_hint') or I18n.t('battle.menu')
  local right = (battle.paused or battle.modal) and hint or nil
  Ui.footer(I18n.t('battle.footer', battle.run.wave, #Encounters.WAVES, battle.round_no), right)
  if battle.paused or battle.modal then
    return
  end
  local bx, by, bw, bh = Render.pause_button_rect()
  local label = (I18n.t('battle.menu'):gsub('%[ESC%]%s*', ''))
  Ui.button(bx, by, bw, bh, label, {
    hover = Ui.hit({ x = bx, y = by, w = bw, h = bh }, mouse.x, mouse.y),
    color = C.paper,
  })
end

local function draw_modal(battle, mouse)
  local m = battle.modal
  if not m then
    return
  end
  local name = I18n.active_name(m.id or battle.state.inventory[m.index])
  local effect = m.def and m.def.effect
  if m.def and (effect == 'attack' or effect == 'defense' or effect == 'heal') then
    name = name .. ' +' .. tostring(m.def.amount or 0)
  end

  local hint = I18n.t('battle.select_confirm')
  if effect == 'swap' then
    hint = I18n.t('battle.drag_swap')
  elseif effect == 'heal' or effect == 'attack' or effect == 'defense' then
    hint = I18n.t('battle.select_target')
  elseif effect == 'shift' then
    hint = I18n.t('battle.shift_mode')
  end

  Ui.rect(0, 187, T.W, 67, C.ink, 0.96)
  Text.fit_text(name .. '  ' .. hint, T.W / 2, 188, 370, { color = C.amber, align = 'center' })

  if effect == 'shift' then
    Ui.button(26, 207, 102, 21, I18n.t('battle.shift_a'), {
      disabled = m.delta <= -m.def.steps,
      hover = Ui.hit({ x = 26, y = 207, w = 102, h = 21 }, mouse.x, mouse.y),
    })
    Ui.button(256, 207, 102, 21, I18n.t('battle.shift_d'), {
      disabled = m.delta >= m.def.steps,
      hover = Ui.hit({ x = 256, y = 207, w = 102, h = 21 }, mouse.x, mouse.y),
    })
    draw_range(battle, I18n.t('battle.shift_remaining', m.remaining, m.def.steps), 192, 212, 120)
  end

  Ui.button(47, 231, 132, 22, I18n.t('common.back'), {
    hover = Ui.hit({ x = 47, y = 231, w = 132, h = 22 }, mouse.x, mouse.y),
  })
  if effect ~= 'swap' then
    Ui.button(205, 231, 132, 22, I18n.t('battle.confirm'), {
      disabled = not battle:modal_ready(),
      primary = true,
      hover = Ui.hit({ x = 205, y = 231, w = 132, h = 22 }, mouse.x, mouse.y),
    })
  end

  if m.drag_from then
    local u = battle.state.line[m.drag_from]
    if u then
      Ui.unit_shadow(mouse.x, mouse.y + 16, 18, 0.45)
      Ui.unit(u, mouse.x, mouse.y, 2, C.white, 0.85)
    end
  end
end

local function draw_intro(battle)
  local out = battle.intro_t > 0.82 and math.min(1, (battle.intro_t - 0.82) / 0.33) or 0
  local alpha = 1 - out
  if alpha <= 0 then
    return
  end
  local rise = (1 - Ui.ease_out(math.min(1, battle.intro_t / 0.24))) * 22

  Ui.rect(0, 0, T.W, T.H, C.ink, 0.62 * alpha)
  local w, h = 284, Ui.cjk and 46 or 40
  local x = T.W / 2 - w / 2
  local y = 116 - rise
  Ui.rect(x, y, w, h, C.ink, 0.97 * alpha)
  Ui.hline(x, y, w, C.amber, alpha)
  Ui.hline(x, y + h - 1, w, C.amber, alpha)

  Text.text(I18n.t('battle.wave', battle.run.wave), T.W / 2, y + (Ui.cjk and 4 or 6), {
    color = C.white,
    scale = 2,
    align = 'center',
    alpha = alpha,
  })
  local encounter = battle.run:encounter()
  local name = type(encounter) == 'table' and encounter.name or nil
  Text.text(name and I18n.wave_name(name) or I18n.pattern_desc(battle:pattern()), T.W / 2, y + (Ui.cjk and 28 or 27), {
    color = C.amber,
    align = 'center',
    alpha = alpha,
  })
end

local function draw_pause(battle, mouse)
  if battle.quit_confirm then
    Ui.dialogs.quit_confirm.draw(mouse)
    return
  end

  Ui.rect(0, 0, T.W, T.H, C.ink, 0.78)
  local x, y, w, h, first, step = Render.pause_panel_rect()
  Ui.panel(x, y, w, h, { fill = C.shade, border = C.amber })
  Text.text(I18n.t('battle.paused'), T.W / 2, y + 8, { color = C.white, scale = 2, align = 'center' })
  Text.text(I18n.t('common.seed', battle.run.seed), T.W / 2, y + (Ui.cjk and 34 or 30), {
    color = C.dim,
    align = 'center',
  })

  local hover_i = Render.pause_hover_index(mouse)
  for i, label in ipairs(Render.pause_entries()) do
    local iy = first + (i - 1) * step
    local hot = hover_i == i
    if hot then
      Ui.rect(x + 12, iy - 3, w - 24, step - 2, C.panel, 0.85)
      Ui.frame(x + 12, iy - 3, w - 24, step - 2, C.amber, 0.5)
    end
    Text.text(label, T.W / 2, iy, { color = hot and C.amber or C.paper, align = 'center' })
  end
end

function Render.draw(battle, mouse)
  Ui.wipe(1)

  local shake = battle.fx.shake
  local sx = shake > 0 and (love.math.random() * 2 - 1) * shake or 0
  local sy = shake > 0 and (love.math.random() * 2 - 1) * shake or 0
  love.graphics.push()
  love.graphics.translate(math.floor(sx), math.floor(sy))

  draw_front_line(battle)
  draw_enemy_row(battle)
  draw_boss_bar(battle)
  draw_player_row(battle, mouse)
  battle.fx:draw_world()
  love.graphics.pop()

  draw_topbar(battle)
  if not battle.modal then
    draw_buttons(battle, mouse)
    draw_hint(battle)
  end
  draw_footer(battle, mouse)
  draw_modal(battle, mouse)

  if battle.phase == 'intro' then
    draw_intro(battle)
  end
  if battle.fx.flash > 0 then
    Ui.flash(battle.fx.flash * 0.5, C.white)
  end
  if battle.paused then
    draw_pause(battle, mouse)
  end
end

return Render
