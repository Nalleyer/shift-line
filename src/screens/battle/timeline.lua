-- Battle event-to-frame timeline builder and frame-to-view/FX dispatcher.
local Items = require('data.items')
local Audio = require('platform.audio')
local I18n = require('i18n')
local Ui = require('ui')

local T = Ui.theme
local C = Ui.C

local Timeline = {}

function Timeline.build_frames(events)
  local frames = {}
  local t = 0
  for _, e in ipairs(events or {}) do
    if e.type == 'round' then
      t = t + 0.34
      frames[#frames + 1] = { t = t, kind = 'round', n = e.n }
    elseif e.type == 'break' then
      t = t + 0.62
      frames[#frames + 1] = { t = t, kind = 'break', ev = e }
    elseif e.type == 'core' then
      t = t + 0.22
      frames[#frames + 1] = { t = t, kind = 'core', ev = e }
    elseif e.type == 'heal' then
      t = t + 0.10
      frames[#frames + 1] = { t = t, kind = 'heal', ev = e }
    elseif e.type == 'gold' then
      frames[#frames + 1] = { t = t, kind = 'gold', ev = e }
    elseif e.type == 'charge' then
      if e.delta and e.delta > 0 then
        t = t + 0.18
      end
      frames[#frames + 1] = { t = t, kind = 'charge', ev = e }
    elseif e.type == 'clash' then
      frames[#frames + 1] = { t = t, kind = 'clash', side = e.side }
    elseif e.type == 'action' then
      t = t + 0.12
      frames[#frames + 1] = { t = t, kind = 'action', ev = e }
      t = t + 0.10
    elseif e.type == 'death' then
      t = t + 0.12
      frames[#frames + 1] = { t = t, kind = 'death', ev = e }
    elseif e.type == 'victory' then
      t = t + 0.55
      frames[#frames + 1] = { t = t, kind = 'victory' }
    elseif e.type == 'defeat' then
      t = t + 0.9
      frames[#frames + 1] = { t = t, kind = 'defeat', ev = e }
    elseif e.type == 'reposition' or e.type == 'boss' or e.type == 'item' or e.type == 'relic' or e.type == 'pressure' then
      t = t + 0.22
      frames[#frames + 1] = { t = t, kind = e.type, ev = e }
      if e.type == 'reposition' then
        t = t + 0.32
      end
    elseif e.type == 'damage' then
      t = t + 0.10
      frames[#frames + 1] = { t = t, kind = 'hit', dmgs = { e }, n = e.clash or 0, side = e.by }
    end
  end
  return frames, t + 0.45
end

function Timeline.apply_frame(battle, f)
  local fx = battle.fx

  if f.kind == 'gold' then
    battle.battle_gold = battle.battle_gold + (f.ev.amount or 0)
  elseif f.kind == 'charge' then
    if f.ev.charge ~= nil then
      battle.charge_view = f.ev.charge
    end
    if f.ev.delta and f.ev.delta > 0 then
      fx.charge_flash = 1
      fx.charge_delta = f.ev.delta
      fx.charge_delta_t = 0
      fx.flash = math.max(fx.flash, 0.14)
      local sx = f.ev.col and T.col_cx(f.ev.col) or (T.W / 2)
      local sy = f.ev.col and (T.PLAYER_Y + 28) or (T.FRONT_Y + 3)
      fx:add_charge_bolts(sx, sy)
      if f.ev.col then
        fx:add_shards(sx, sy, C.blue, 8)
        fx:add_number(sx + 12, T.PLAYER_Y - 4, '+' .. f.ev.delta, C.blue, 2)
      end
      Audio.play('node', 0.65, 1.35)
    end
  elseif f.kind == 'clash' then
    battle.message = I18n.t(f.side == 'enemy' and 'battle.enemy_phase' or 'battle.ally_phase')
  elseif f.kind == 'action' then
    fx.actor = { side = f.ev.side, col = f.ev.from, kind = f.ev.kind, t = 0 }
    if f.ev.kind == 'taunt' or f.ev.kind == 'intercept' then
      battle.message = I18n.t('trait.' .. f.ev.kind .. '.name')
    end
  elseif f.kind == 'round' then
    battle.round_no = f.n
  elseif f.kind == 'break' then
    local ev = f.ev
    local cx = T.col_cx(ev.col)
    local enemy_unit = battle.enemies[ev.col]
    if ev.escape then
      battle.enemies[ev.col] = nil
    end
    if ev.compensated then
      fx.lane_flashes[ev.col] = { t = 0, life = 0.45, col = C.blue }
      fx:add_shards(cx, T.PLAYER_Y + 26, C.blue, 8)
      fx:add_number(cx, T.PLAYER_Y + 12, I18n.t('battle.block'), C.blue, 1)
      Audio.play('ui_select', 0.7, 1.2)
    elseif ev.amount > 0 then
      fx:add_streak(ev.col, ev.amount)
      fx.lane_flashes[ev.col] = { t = 0, life = 0.55, col = C.red }
      fx:add_breach_ghost(ev.col, ev.kind or (enemy_unit and enemy_unit.kind), ev.escape)
      fx:add_shards(cx, T.FRONT_Y + 3, C.amber, 7)
      fx:add_shards(cx, T.PLAYER_Y + 32, C.red, 10)
      fx:add_number(cx - 10, T.PLAYER_Y + 20, '-' .. ev.amount, C.red, 2)
      Audio.play('break', 0.9)
      fx.shake = math.max(fx.shake, 4.2)
    end
  elseif f.kind == 'core' then
    battle.core_view = f.ev.core
    fx.core_delta = f.ev.delta
    fx.core_delta_t = 0
    fx.heart_flash = 1
    Audio.play(f.ev.delta > 0 and 'heal' or 'core_hit', 0.9)
    if f.ev.delta < 0 then
      fx.shake = math.max(fx.shake, 5)
      fx.flash = math.max(fx.flash, 0.35)
    end
  elseif f.kind == 'heal' then
    local ev = f.ev
    local u = battle.line[ev.to]
    if u then
      u.hp = ev.hp
      fx.hit_flash.player[ev.to] = 0.22
      fx.heal_flash[ev.to] = 0.22
      fx:add_number(T.col_cx(ev.to), T.PLAYER_Y + 26, '+' .. (ev.amount or 1), C.green, 1)
    end
    Audio.play('heal', 0.55)
  elseif f.kind == 'hit' then
    battle.message = I18n.t(f.side == 'enemy' and 'battle.enemy_phase' or 'battle.ally_phase')
    local maxdmg = 0
    for _, d in ipairs(f.dmgs) do
      if d.target == 'player' then
        local u = battle.line[d.col]
        if u then
          u.hp = d.hp
        end
        fx.hit_flash.player[d.col] = 0.16
        local blocked = (d.dmg == 0)
        fx:add_number(
          T.col_cx(d.col),
          blocked and (T.PLAYER_Y - 9) or (T.PLAYER_Y + 20),
          blocked and I18n.t('battle.block') or ('-' .. d.dmg),
          blocked and C.blue or C.red,
          blocked and 1 or 2
        )
      else
        local e = battle.enemies[d.col]
        if e then
          e.hp = d.hp
        end
        fx.hit_flash.enemy[d.col] = 0.16
        fx:add_number(T.col_cx(d.col), T.ENEMY_Y + 20, '-' .. d.dmg, C.white, 2)
      end
      maxdmg = math.max(maxdmg, d.dmg)
    end
    if #f.dmgs > 0 then
      Audio.play(maxdmg >= 2 and 'hit_big' or 'hit', 0.8, 0.94 + love.math.random() * 0.12)
      fx.shake = math.max(fx.shake, maxdmg >= 2 and 3 or 1.6)
    end
  elseif f.kind == 'death' then
    local ev = f.ev
    if ev.side == 'player' then
      if battle.line[ev.col] then
        fx:add_shards(T.col_cx(ev.col), T.PLAYER_Y + 35, C.paper, 9)
        battle.line[ev.col] = nil
      end
    elseif battle.enemies[ev.col] then
      fx:add_shards(T.col_cx(ev.col), T.ENEMY_Y + 35, C.red, 9)
      battle.enemies[ev.col] = nil
    end
    Audio.play('death', 0.85)
    fx.shake = math.max(fx.shake, 3)
  elseif f.kind == 'reposition' then
    local side = f.ev.side or ((f.ev.label == 'ENEMY SHIFT' or f.ev.label == 'BOSS SHIFT') and 'enemy' or 'player')
    battle.line, battle.enemies = fx:begin_reposition(battle.line, battle.enemies, f.ev.line, f.ev.enemies, f.ev.delta, side)
    Audio.play('shift', 0.75)
    battle.message = I18n.label(f.ev.label)
  elseif f.kind == 'boss' then
    battle.boss_hp, battle.boss_max = f.ev.hp, f.ev.max
    for i = 1, 6 do
      if battle.enemies[i] then
        battle.enemies[i].hp = f.ev.hp
      end
    end
  elseif f.kind == 'item' or f.kind == 'relic' then
    local name
    if Items.RELICS[f.ev.id] then
      name = I18n.relic_name(f.ev.id)
    elseif Items.ACTIVES[f.ev.id] then
      name = I18n.active_name(f.ev.id)
    else
      name = I18n.label(f.ev.name)
    end
    battle.message = name or f.ev.id
  elseif f.kind == 'pressure' then
    battle.pressure_view = f.ev.pressure or battle.pressure_view or 0
    battle.message = I18n.t('battle.pressure_up', battle.pressure_view)
    Audio.play('shift', 0.85)
  elseif f.kind == 'victory' then
    Audio.play('win', 0.9)
    battle.victory_flash = true
  elseif f.kind == 'defeat' then
    Audio.play('lose', 0.9)
    fx.flash = 0.5
  end
end

return Timeline
