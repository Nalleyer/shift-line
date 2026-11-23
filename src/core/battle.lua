-- Pure, deterministic combat state machine and round resolution.
local Constants = require('data.constants')
local Items = require('data.items')
local Util = require('core.util')
local Unit = require('core.unit')
local Encounter = require('core.encounter')

local Battle = {}

local function emit(s, ev)
  s.events[#s.events + 1] = ev
end

local function events_since(s, first)
  local out = {}
  for i = first, #s.events do
    out[#out + 1] = s.events[i]
  end
  return out
end

local function finish_battle(s, won, reason)
  s.done = true
  s.won = won
  s.reason = reason
  emit(s, won and { type = 'victory' } or { type = 'defeat', reason = reason })
end

local function emit_reposition(s, label, delta, side)
  emit(s, {
    type = 'reposition',
    line = Util.deep_copy(s.line),
    enemies = Util.deep_copy(s.enemies),
    label = label,
    delta = delta,
    side = side or 'player',
  })
end

local function emit_relic(s, id)
  emit(s, { type = 'relic', id = id, name = Items.RELICS[id].name })
end

local function award_bounty(s, kind)
  local amount = Constants.ENEMY_BOUNTIES[kind] or 0
  amount = amount + Util.relic_count(s.relics, 'bounty')
  s.gold_earned = s.gold_earned + amount
  emit(s, { type = 'gold', amount = amount, gold = s.gold_earned })
end

local function check_end(s)
  if s.core <= 0 then
    finish_battle(s, false, 'core')
    return true
  end
  if Util.count_slots(s.line) == 0 then
    finish_battle(s, false, 'wiped')
    return true
  end
  local enemies_cleared = (s.boss and s.boss_hp <= 0) or (not s.boss and Util.count_slots(s.enemies) == 0)
  if enemies_cleared then
    if s.boss then
      for i = 1, Constants.SLOTS do
        local e = s.enemies[i]
        if e then
          emit(s, { type = 'death', col = i, side = 'enemy', kind = e.kind })
          s.enemies[i] = nil
          s.enemy_killed = s.enemy_killed + 1
        end
      end
      local bounty_kind = (s.encounter and s.encounter.mini_boss) and 'mini_boss' or 'boss'
      award_bounty(s, bounty_kind)
    end
    finish_battle(s, true, 'victory')
    return true
  end
  return false
end

local function clear_combat_buffs(line)
  for _, unit in pairs(line) do
    unit.combat_atk = nil
    unit.combat_def = nil
  end
end

function Battle.new(roster, enc, offset, core, opts)
  opts = opts or {}
  enc = Util.deep_copy(enc or '......')
  local boss = type(enc) == 'table' and enc.boss or false
  local enemies = Encounter.parse_enemies(enc)

  local s = {
    line = Unit.build_line(roster, offset),
    enemies = enemies,
    core = core or Constants.CORE_MAX,
    core_max = opts.core_max or Constants.CORE_MAX,
    charge = opts.charge or 0,
    charge_max = opts.charge_max or Constants.CHARGE_MAX,
    charge_earned = 0,
    charge_spent = 0,
    shifted_this_round = false,
    pressure = 0,
    round_no = 0,
    events = {},
    done = false,
    won = false,
    relics = Util.deep_copy(opts.relics or {}),
    inventory = Util.deep_copy(opts.inventory or {}),
    items_used = {},
    encounter = enc,
    pattern = type(enc) == 'table' and enc.pattern or enc,
    offset = offset or 0,
    start_roster = Util.deep_copy(roster),
    initial_core = core or Constants.CORE_MAX,
    core_damage = 0,
    gold_earned = 0,
    ally_total = Util.count_slots(roster),
    enemy_total = Util.count_slots(enemies),
    casualties = 0,
    enemy_killed = 0,
    enemy_escaped = 0,
    boss = boss,
    boss_hp = boss and (enc.boss_hp or 14) or nil,
    boss_max = boss and (enc.boss_hp or 14) or nil,
    boss_shift = false,
    boss_next_pattern = boss and (enc.boss_motion ~= 'tide' and (enc.boss_alt_pattern or 'a..c.a') or nil) or nil,
    navigator_available = Util.has_relic(opts.relics, 'navigator'),
    navigator_delta = 0,
    navigator_limit = 3 * Util.relic_count(opts.relics, 'navigator'),
    insurance_available = Util.has_relic(opts.relics, 'insurance'),
    insurance_charges = Util.relic_count(opts.relics, 'insurance'),
    compensation_available = Util.has_relic(opts.relics, 'compensation'),
    compensation_charges = Util.relic_count(opts.relics, 'compensation'),
  }

  for i = 1, Constants.SLOTS do
    local u = s.line[i]
    if u then
      local ct = Unit.trait(u, 'charge_aura')
      if ct and ct.min_start_charge then
        local floor_charge = math.min(s.charge_max, ct.min_start_charge)
        if s.charge < floor_charge then
          s.charge = floor_charge
        end
      end
      local mt = Unit.trait(u, 'motion')
      if mt and mt.motion == 'right' then
        u.combat_atk = (u.combat_atk or 0) + 1
      end
    end
  end

  if s.ally_total == 0 then
    finish_battle(s, false, 'wiped')
  elseif s.core <= 0 then
    finish_battle(s, false, 'core')
  elseif not boss and s.enemy_total == 0 then
    finish_battle(s, true, 'victory')
  end

  return s
end

local function resolve_heals(s)
  for i = 1, Constants.SLOTS do
    local u = s.line[i]
    local heal = u and Unit.trait(u, 'heal')
    if heal then
      local heal_targets = {}
      local ward_targets = {}
      for _, j in ipairs(Unit.support_targets(s.line, i, s.relics)) do
        local t = s.line[j]
        if t and t.hp > 0 then
          if t.hp < t.max then
            heal_targets[#heal_targets + 1] = j
          else
            ward_targets[#ward_targets + 1] = j
          end
        end
      end
      if #heal_targets > 0 then
        emit(s, {
          type = 'action',
          kind = 'heal',
          side = 'player',
          from = i,
          targets = Util.deep_copy(heal_targets),
          n = s.round_no,
        })
        for _, j in ipairs(heal_targets) do
          local t = s.line[j]
          local amount = math.min(heal.amount, t.max - t.hp)
          t.hp = t.hp + amount
          emit(s, { type = 'heal', from = i, to = j, amount = amount, hp = t.hp, max = t.max })
        end
      end
      if #ward_targets > 0 then
        emit(s, {
          type = 'action',
          kind = 'guard',
          side = 'player',
          from = i,
          targets = Util.deep_copy(ward_targets),
          n = s.round_no,
        })
        for _, j in ipairs(ward_targets) do
          local t = s.line[j]
          t.combat_def = (t.combat_def or 0) + heal.amount
        end
      end
    end
  end
end

local function compute_enemy_guards(s)
  local guards = {}
  for j = 1, Constants.SLOTS do
    guards[j] = 0
  end
  for j = 1, Constants.SLOTS do
    local e = s.enemies[j]
    local gt = e and Unit.trait(e, 'guard')
    if gt then
      for _, target in ipairs(Unit.support_targets(s.enemies, j)) do
        guards[target] = guards[target] + gt.amount
      end
    end
  end
  return guards
end

local function resolve_player_attacks(s, enemy_guards)
  emit(s, { type = 'clash', side = 'player', n = s.round_no })

  for i = 1, Constants.SLOTS do
    local unit = s.line[i]
    if unit then
      local atk = Unit.attack(unit, s)
        + (s.round_no == 1 and Util.relic_count(s.relics, 'whetstone') or 0)
        + Unit.support_attack_bonus(s, i)
      local attack_trait = Unit.trait(unit, 'attack')
      local reach_trait = Unit.trait(unit, 'reach')
      local is_piercing = ((attack_trait or {}).piercing) or (Unit.trait(unit, 'pierce') ~= nil)

      local targets = {}
      for _, col in ipairs(Unit.attack_targets(unit, i, s.enemies)) do
        local enemy = s.enemies[col]
        if enemy and enemy.hp > 0 and (not s.boss or s.boss_hp > 0) then
          targets[#targets + 1] = col
        end
      end

      if #targets > 0 then
        emit(s, {
          type = 'action',
          kind = 'attack',
          side = 'player',
          from = i,
          targets = Util.deep_copy(targets),
          n = s.round_no,
        })
      end

      for _, col in ipairs(targets) do
        local enemy = s.enemies[col]
        if enemy and enemy.hp > 0 and (not s.boss or s.boss_hp > 0) then
          local penalty = (col == i) and 0
            or ((attack_trait and attack_trait.side_penalty) or (reach_trait and reach_trait.side_penalty) or 0)
          local amount = (col == i) and atk or math.max(1, atk - penalty)
          local defense = is_piercing and 0 or (Unit.defense(enemy) + enemy_guards[col])
          local dmg = math.max(0, amount - defense)
          if s.boss and attack_trait and col ~= i and dmg > 0 then
            dmg = math.max(1, math.floor(dmg / 2))
          end

          if s.boss then
            s.boss_hp = s.boss_hp - dmg
            for j = 1, Constants.SLOTS do
              if s.enemies[j] then
                s.enemies[j].hp = s.boss_hp
              end
            end
          else
            enemy.hp = enemy.hp - dmg
          end

          emit(s, {
            type = 'damage',
            clash = s.round_no,
            col = col,
            target = 'enemy',
            by = 'player',
            from = i,
            dmg = dmg,
            hp = enemy.hp,
            max = enemy.max,
          })

          if s.boss then
            emit(s, { type = 'boss', hp = s.boss_hp, max = s.boss_max })
          elseif enemy.hp <= 0 then
            s.enemy_killed = s.enemy_killed + 1
            emit(s, { type = 'death', col = col, side = 'enemy', kind = enemy.kind })
            s.enemies[col] = nil
            award_bounty(s, enemy.kind)
          end
        end
      end
    end
  end

  if s.shifted_this_round then
    for _, unit in pairs(s.line) do
      local mom = Unit.trait(unit, 'momentum')
      if mom and mom.def_bonus then
        unit.combat_def = (unit.combat_def or 0) + mom.def_bonus
      end
    end
  end
  s.shifted_this_round = false
end

local function resolve_breach(s, col, enemy, escape)
  local amount = enemy.brk or 0
  local blocked = amount > 0 and s.compensation_available
  emit(s, {
    type = 'break',
    col = col,
    kind = enemy.kind,
    amount = amount,
    compensated = not not blocked,
    escape = not not escape,
  })

  if blocked then
    s.compensation_charges = math.max(0, (s.compensation_charges or 1) - 1)
    s.compensation_available = s.compensation_charges > 0
    emit_relic(s, 'compensation')
  elseif amount > 0 then
    s.core = s.core - amount
    s.core_damage = s.core_damage + amount
    emit(s, { type = 'core', delta = -amount, core = s.core })

    local extra = 0
    if not s._k_breach_bonus_used then
      for j = 1, Constants.SLOTS do
        local u = s.line[j]
        if u and u.hp > 0 and Unit.trait(u, 'charge_aura') then
          extra = 1
          s._k_breach_bonus_used = true
          break
        end
      end
    end

    local battle_room = math.max(0, Constants.BATTLE_CHARGE_CAP - (s.charge_earned or 0))
    local cap_room = math.max(0, (s.charge_max or Constants.CHARGE_MAX) - (s.charge or 0))
    local gained = math.min(amount + extra, battle_room, cap_room)
    if gained > 0 then
      s.charge = (s.charge or 0) + gained
      s.charge_earned = (s.charge_earned or 0) + gained
      emit(s, { type = 'charge', delta = gained, charge = s.charge, col = col })
    end
  end

  if escape then
    s.enemies[col] = nil
    s.enemy_escaped = s.enemy_escaped + 1
  end
end

local function apply_player_damage(s, col, amount, guards, from, piercing)
  local u = s.line[col]
  if not u then
    return
  end
  local padding = s.round_no == 1 and Util.relic_count(s.relics, 'padding') or 0
  local defense = piercing and 0 or (Unit.defense(u) + (guards or 0) + padding)
  local dmg = math.max(0, amount - defense)
  local hp = u.hp - dmg

  if dmg > 0 and hp <= 0 and s.insurance_available then
    hp = 1
    s.insurance_charges = math.max(0, (s.insurance_charges or 1) - 1)
    s.insurance_available = s.insurance_charges > 0
    emit_relic(s, 'insurance')
  end

  u.hp = hp
  emit(s, {
    type = 'damage',
    col = col,
    target = 'player',
    by = 'enemy',
    from = from,
    dmg = dmg,
    hp = hp,
    max = u.max,
    protected = defense > 0,
    guards = defense,
    clash = s.round_no,
  })

  if hp <= 0 then
    s.casualties = s.casualties + 1
    emit(s, { type = 'death', col = col, side = 'player', kind = u.kind })
    s.line[col] = nil
  end
end

local function snapshot_player_defenses(s, occupied, guards)
  for i = 1, Constants.SLOTS do
    occupied[i] = s.line[i] ~= nil
    guards[i] = 0
  end
  for i = 1, Constants.SLOTS do
    local guard = s.line[i]
    local guard_trait = guard and Unit.trait(guard, 'guard')
    if guard_trait then
      for _, target in ipairs(Unit.support_targets(s.line, i, s.relics)) do
        guards[target] = guards[target] + guard_trait.amount
      end
    end
  end
end

local function try_intercept(s, col, amount, state, occupied, guards)
  if state.intercepted or not col or amount <= 0 or s.compensation_available then
    return false
  end
  local best, delta
  for i = 1, Constants.SLOTS do
    if s.line[i] and Unit.trait(s.line[i], 'intercept') then
      local d = (col - i) % Constants.SLOTS
      if d >= 3 then
        d = d - Constants.SLOTS
      end
      if not best or math.abs(d) < math.abs(delta) or (math.abs(d) == math.abs(delta) and d < delta) then
        best, delta = i, d
      end
    end
  end
  if not best then
    return false
  end

  state.intercepted = true
  local interceptor = s.line[best]
  local itrait = interceptor and Unit.trait(interceptor, 'intercept')
  if itrait and itrait.def_bonus then
    interceptor.combat_def = (interceptor.combat_def or 0) + itrait.def_bonus
  end

  emit(s, { type = 'action', kind = 'intercept', side = 'player', from = best, targets = { col }, n = s.round_no })
  if delta ~= 0 then
    s.line = Util.shift_line(s.line, delta)
    s.shifted_this_round = true
    emit_reposition(s, 'INTERCEPT', delta)
  end
  snapshot_player_defenses(s, occupied, guards)
  return true
end

local function resolve_enemy_phase(s)
  emit(s, { type = 'clash', side = 'enemy', n = s.round_no })

  -- Capture lane occupancy and guard strength once before retaliation resolves.
  local occupied, guards = {}, {}
  snapshot_player_defenses(s, occupied, guards)
  local intercept_state = { intercepted = false }

  for i = 1, Constants.SLOTS do
    local enemy = s.enemies[i]
    if enemy then
      local enemy_pierce = Unit.trait(enemy, 'pierce') ~= nil
      local target = Unit.taunt_target(s.line, i)
      if target and target ~= i then
        emit(s, { type = 'action', kind = 'taunt', side = 'player', from = target, targets = { i }, n = s.round_no })
      end

      if not target and not occupied[i] and try_intercept(s, i, enemy.brk or 0, intercept_state, occupied, guards) then
        target = i
      end

      if not target and not occupied[i] then
        if not s.boss or (enemy.brk or 0) > 0 then
          emit(s, { type = 'action', kind = 'breach', side = 'enemy', from = i, targets = {}, n = s.round_no })
        end
        resolve_breach(s, i, enemy, not s.boss)
      else
        target = target or i
        local targets = {}
        if s.line[target] then
          targets[#targets + 1] = target
        end
        local splash_trait = Unit.trait(enemy, 'splash')
        if splash_trait then
          if i > 1 and s.line[i - 1] then
            targets[#targets + 1] = i - 1
          end
          if i < Constants.SLOTS and s.line[i + 1] then
            targets[#targets + 1] = i + 1
          end
        end
        if #targets > 0 then
          emit(s, { type = 'action', kind = 'attack', side = 'enemy', from = i, targets = targets, n = s.round_no })
        end
        apply_player_damage(s, target, enemy.atk + (s.pressure or 0), guards[target], i, enemy_pierce)
        if splash_trait then
          local splash = splash_trait.amount
          if i > 1 then
            apply_player_damage(s, i - 1, splash, guards[i - 1], i, enemy_pierce)
          end
          if i < Constants.SLOTS then
            apply_player_damage(s, i + 1, splash, guards[i + 1], i, enemy_pierce)
          end
        end
      end
    end
  end
end

local function resolve_unit_motions(s)
  for i = Constants.SLOTS - 1, 1, -1 do
    local unit = s.line[i]
    if unit and Unit.motion(unit) == 'right' and not s.line[i + 1] and not s.enemies[i] then
      local mt = Unit.trait(unit, 'motion')
      if mt and mt.bonus then
        unit.combat_atk = (unit.combat_atk or 0) + mt.bonus
      end
      s.line[i + 1] = unit
      s.line[i] = nil
      s.shifted_this_round = true
      emit_reposition(s, 'RIDER', 1)
    end
  end

  for i = 2, Constants.SLOTS do
    local unit = s.line[i]
    if unit and Unit.motion(unit) == 'left' and not s.line[i - 1] and not s.enemies[i] then
      s.line[i - 1] = unit
      s.line[i] = nil
      s.shifted_this_round = true
      emit_reposition(s, 'PIKEMAN', -1)
    end
  end
end

local function resolve_enemy_motion(s)
  local motion
  for i = 1, Constants.SLOTS do
    local t = Unit.trait(s.enemies[i], 'motion')
    if t and t.scope == 'line' then
      motion = t
      break
    end
  end
  if not motion then
    return
  end

  local period = (s.encounter and s.encounter.boss_period) or motion.period or 2
  if s.boss and motion.motion == 'formation' and s.round_no % period == 0 then
    local pattern = s.boss_next_pattern
    s.boss_next_pattern = (pattern == s.pattern) and (s.encounter.boss_alt_pattern or 'a..c.a') or s.pattern
    s.enemies = Encounter.parse_enemies({
      pattern = pattern,
      boss = true,
      boss_id = s.encounter.boss_id,
      boss_hp = s.boss_max,
      atk = s.encounter.atk,
      def = s.encounter.def,
      unit_traits = s.encounter.unit_traits,
      boss_period = s.encounter.boss_period,
      boss_motion = s.encounter.boss_motion,
      boss_alt_pattern = s.encounter.boss_alt_pattern,
    })
    for i = 1, Constants.SLOTS do
      if s.enemies[i] then
        s.enemies[i].hp = s.boss_hp
      end
    end
    s.boss_shift = true
    emit_reposition(s, 'BOSS SHIFT', nil, 'enemy')
  elseif s.boss and motion.motion == 'tide' and s.round_no % period == 0 then
    s.enemies = Util.shift_line(s.enemies, 2)
    s.boss_shift = true
    emit_reposition(s, 'BOSS SHIFT', 2, 'enemy')
  elseif motion.motion == 'right' then
    s.enemies = Util.shift_line(s.enemies, 1)
    emit_reposition(s, 'ENEMY SHIFT', 1, 'enemy')
  end
end

local function total_line_hp(line)
  local sum = 0
  for i = 1, Constants.SLOTS do
    local u = line[i]
    if u and u.hp > 0 then
      sum = sum + u.hp
    end
  end
  return sum
end

local function total_enemy_hp(s)
  return s.boss and (s.boss_hp or 0) or total_line_hp(s.enemies)
end

local function resolve_stalemate(s, first, pre_ally_hp, pre_enemy_hp, pre_core)
  if s.done then
    return
  end
  local had_break = false
  for k = first, #s.events do
    if s.events[k].type == 'break' then
      had_break = true
      break
    end
  end
  -- Automatic or free-loop repositions (intercept, rolling enemies, boss shifts)
  -- and matched heal/damage trades must not mask a zero-progress stalemate.
  local enemy_changed = total_enemy_hp(s) < pre_enemy_hp
  local ally_changed = total_line_hp(s.line) ~= pre_ally_hp
  local core_changed = s.core < pre_core
  if enemy_changed or ally_changed or core_changed or had_break then
    return
  end
  s.pressure = (s.pressure or 0) + 1
  emit(s, { type = 'pressure', pressure = s.pressure })
end

function Battle.step(s)
  if s.done or s.shift_moves then
    return {}
  end

  local first = #s.events + 1
  local pre_ally_hp = total_line_hp(s.line)
  local pre_enemy_hp = total_enemy_hp(s)
  local pre_core = s.core
  s.boss_shift = false
  s.round_no = s.round_no + 1
  emit(s, { type = 'round', n = s.round_no })

  resolve_heals(s)
  local enemy_guards = compute_enemy_guards(s)
  resolve_player_attacks(s, enemy_guards)
  if check_end(s) then
    clear_combat_buffs(s.line)
    return events_since(s, first)
  end

  resolve_enemy_phase(s)
  clear_combat_buffs(s.line)
  if check_end(s) then
    return events_since(s, first)
  end

  if s.round_no >= Constants.MAX_ROUNDS then
    if s.boss then
      finish_battle(s, false, 'overrun')
    else
      for i = 1, Constants.SLOTS do
        local enemy = s.enemies[i]
        if enemy then
          resolve_breach(s, i, enemy, true)
        end
      end
      check_end(s)
    end
  else
    resolve_unit_motions(s)
    resolve_enemy_motion(s)
  end

  resolve_stalemate(s, first, pre_ally_hp, pre_enemy_hp, pre_core)
  s.navigator_available = Util.has_relic(s.relics, 'navigator')
  s.navigator_delta = 0
  return events_since(s, first)
end

function Battle.item_targets(s, index)
  local item = Items.ACTIVES[s.inventory[index] or '']
  local out = {}
  if not item then
    return out
  end
  if item.effect == 'heal' or item.effect == 'attack' or item.effect == 'defense' or item.effect == 'swap' then
    for i = 1, Constants.SLOTS do
      local u = s.line[i]
      if u and u.hp > 0 and (item.effect ~= 'heal' or u.hp < u.max) then
        out[#out + 1] = i
      end
    end
  end
  return out
end

function Battle.can_use_item(s, index)
  if s.done or s.shift_moves then
    return false, 'unavailable'
  end
  if type(index) ~= 'number' or index ~= math.floor(index) then
    return false, 'invalid item'
  end
  local item = Items.ACTIVES[s.inventory[index] or '']
  if not item then
    return false, 'invalid item'
  end
  if item.effect == 'core' then
    return s.core < s.core_max, 'core full'
  end
  if item.effect == 'shift' then
    return s.round_no > 0 and Util.count_slots(s.line) > 0, s.round_no == 0 and 'unavailable' or 'no target'
  end
  return #Battle.item_targets(s, index) > 0, 'no target'
end

local function handle_shift_modal(s, cmd, typ)
  if typ == 'shift_cancel' then
    local m = s.shift_moves
    if not m then
      return false, 'no shift'
    end
    s.line = Util.deep_copy(m.origin)
    s.shift_moves = nil
    emit_reposition(s, 'SHIFT PREVIEW', -m.delta)
    return true
  elseif typ == 'shift_finish' then
    local m = s.shift_moves
    if not m then
      return false, 'no shift'
    end
    if m.delta ~= 0 then
      if s.inventory[m.index] ~= m.id then
        return false, 'invalid item'
      end
      table.remove(s.inventory, m.index)
      s.items_used[#s.items_used + 1] = m.id
      s.shifted_this_round = true
      emit(s, { type = 'item', id = m.id, name = Items.ACTIVES[m.id].name })
    end
    s.shift_moves = nil
    return true
  else
    local m = s.shift_moves
    if not m or (cmd.delta ~= -1 and cmd.delta ~= 1) or math.abs(m.delta + cmd.delta) > m.total then
      return false, 'invalid shift'
    end
    m.delta = m.delta + cmd.delta
    m.remaining = m.total - math.abs(m.delta)
    s.line = Util.shift_line(m.origin, m.delta)
    emit_reposition(s, Items.ACTIVES[m.id].name, cmd.delta)
    return true
  end
end

local function handle_item(s, cmd)
  local ok, reason = Battle.can_use_item(s, cmd.index)
  if not ok then
    return false, reason
  end
  local id = s.inventory[cmd.index]
  local item = Items.ACTIVES[id]
  local effect = item.effect

  if effect == 'shift' then
    local delta = cmd.delta
    if delta ~= nil and delta ~= -1 and delta ~= 1 then
      return false, 'invalid direction'
    end
    s.shift_moves = {
      id = id,
      index = cmd.index,
      total = item.steps,
      remaining = item.steps,
      delta = 0,
      origin = Util.deep_copy(s.line),
    }
    if delta then
      s.shift_moves.delta = delta
      s.shift_moves.remaining = item.steps - 1
      s.line = Util.shift_line(s.line, delta)
      emit_reposition(s, item.name, delta)
    end
    return true
  elseif effect == 'core' then
    local amount = math.min(item.amount, s.core_max - s.core)
    s.core = s.core + amount
    emit(s, { type = 'core', delta = amount, core = s.core })
  elseif effect == 'swap' then
    if not Util.valid_slot(cmd.from) or not Util.valid_slot(cmd.to) or cmd.from == cmd.to or not s.line[cmd.from] then
      return false, 'invalid target'
    end
    s.line[cmd.from], s.line[cmd.to] = s.line[cmd.to], s.line[cmd.from]
    s.shifted_this_round = true
    emit_reposition(s, item.name)
  else
    local col = cmd.target
    if not Util.valid_slot(col) or not s.line[col] then
      return false, 'invalid target'
    end
    local unit = s.line[col]
    if effect == 'heal' then
      if unit.hp >= unit.max then
        return false, 'invalid target'
      end
      local amount = math.min(item.amount, unit.max - unit.hp)
      unit.hp = unit.hp + amount
      emit(s, { type = 'action', kind = 'heal', side = 'player', from = col, targets = { col }, n = s.round_no, item = true })
      emit(s, { type = 'heal', from = col, to = col, amount = amount, hp = unit.hp, max = unit.max })
    elseif effect == 'attack' then
      unit.combat_atk = (unit.combat_atk or 0) + item.amount
    elseif effect == 'defense' then
      unit.combat_def = (unit.combat_def or 0) + item.amount
    else
      return false, 'invalid item'
    end
  end

  table.remove(s.inventory, cmd.index)
  s.items_used[#s.items_used + 1] = id
  emit(s, { type = 'item', id = id, name = item.name })
  return true
end

function Battle.command(s, cmd)
  if s.done then
    return false, {}, 'unavailable'
  end
  local first = #s.events + 1
  local typ = cmd and cmd.type

  if s.shift_moves and typ ~= 'shift_step' and typ ~= 'shift_finish' and typ ~= 'shift_cancel' then
    return false, {}, 'finish shift first'
  end

  local ok, reason
  if typ == 'shift_cancel' or typ == 'shift_finish' or typ == 'shift_step' then
    ok, reason = handle_shift_modal(s, cmd, typ)
  elseif typ == 'deploy_shift' then
    local delta = cmd.delta
    if s.round_no ~= 0 or (delta ~= -1 and delta ~= 1) then
      return false, {}, 'invalid deploy shift'
    end
    s.line = Util.shift_line(s.line, delta)
    s.offset = (s.offset + delta) % Constants.SLOTS
    emit_reposition(s, 'DEPLOY', delta)
    ok = true
  elseif typ == 'boss_shift' or typ == 'navigator_shift' then
    local delta = cmd.delta
    local limit = typ == 'navigator_shift' and s.navigator_limit or 1
    if type(delta) ~= 'number' or delta ~= math.floor(delta) or delta == 0 or math.abs(delta) > limit then
      return false, {}, 'invalid shift'
    end
    if typ == 'boss_shift' and not s.boss_shift then
      return false, {}, 'no boss shift'
    end
    if typ == 'navigator_shift' and not s.navigator_available then
      return false, {}, 'no navigator shift'
    end
    if typ == 'navigator_shift' then
      local position = (s.navigator_delta or 0) + delta
      if math.abs(position) > limit then
        return false, {}, 'invalid shift'
      end
      s.navigator_delta = position
    end
    local label = typ == 'navigator_shift' and 'NAVIGATOR' or 'BOSS SHIFT'
    s.line = Util.shift_line(s.line, delta)
    s.shifted_this_round = true
    emit_reposition(s, label, delta)
    ok = true
  elseif typ == 'charge_shift' then
    local delta = cmd.delta
    if s.round_no <= 0 or (delta ~= -1 and delta ~= 1) or (s.charge or 0) < 1 or Util.count_slots(s.line) == 0 then
      return false, {}, 'unavailable'
    end
    s.charge = s.charge - 1
    s.charge_spent = (s.charge_spent or 0) + 1
    s.line = Util.shift_line(s.line, delta)
    s.shifted_this_round = true
    emit(s, { type = 'charge', delta = -1, charge = s.charge })
    emit_reposition(s, 'CHARGE SHIFT', delta)
    ok = true
  elseif typ == 'item' then
    ok, reason = handle_item(s, cmd)
  else
    return false, {}, 'invalid command'
  end

  if not ok then
    return false, {}, reason
  end
  return true, events_since(s, first)
end

function Battle.available_actions(s)
  local ready = not s.done and not s.shift_moves
  return {
    boss_shift = ready and s.boss_shift or false,
    navigator_shift = ready and s.navigator_available or false,
    charge = s.charge or 0,
    items = Util.deep_copy(s.inventory),
    shift_moves = Util.deep_copy(s.shift_moves),
  }
end

function Battle.can_intervene(s)
  if s.done then
    return false
  end
  if s.shift_moves or s.boss_shift or s.navigator_available or (s.round_no > 0 and (s.charge or 0) >= 1) then
    return true
  end
  for i in ipairs(s.inventory) do
    if Battle.can_use_item(s, i) then
      return true
    end
  end
  return false
end

function Battle.result(s)
  local ending = {}
  for i = 1, Constants.SLOTS do
    local u = s.line[i]
    if u then
      local copy = Util.deep_copy(u)
      copy.slot = nil
      copy.max = nil
      copy.combat_atk = nil
      copy.combat_def = nil
      ending[u.slot] = copy
    end
  end

  return {
    won = s.won,
    reason = s.reason,
    core_damage = s.core_damage,
    core_after = s.core,
    charge_after = s.charge,
    charge_earned = s.charge_earned,
    charge_spent = s.charge_spent,
    casualties = s.casualties,
    ally_total = s.ally_total,
    enemy_total = s.enemy_total,
    gold_earned = s.gold_earned,
    enemy_killed = s.enemy_killed,
    enemy_escaped = s.enemy_escaped,
    rounds = s.round_no,
    start_roster = Util.deep_copy(s.start_roster),
    end_roster = ending,
    line = Util.deep_copy(s.line),
    pattern = s.pattern,
    offset = s.offset,
    events = Util.deep_copy(s.events),
    inventory = Util.deep_copy(s.inventory),
    items_used = Util.deep_copy(s.items_used),
    boss_hp = s.boss_hp,
    boss_max = s.boss_max,
  }
end

function Battle.simulate(roster, enc, offset, core, opts)
  local s = Battle.new(roster, enc, offset, core, opts)
  while not s.done do
    Battle.step(s)
  end
  return Battle.result(s)
end

return Battle
