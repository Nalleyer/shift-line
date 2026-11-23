-- Pure unit queries: data-driven growth/evolution, trait resolution, stats, and targeting.
local Constants = require('data.constants')
local Traits = require('data.traits')
local Units = require('data.units')
local Util = require('core.util')

local Unit = {}

function Unit.ally_def(kind)
  return Units.ALLIES[kind]
end

function Unit.enemy_def(kind)
  return Units.ENEMIES[kind]
end

function Unit.is_ally(kind)
  return Units.ALLIES[kind] ~= nil
end

function Unit.is_enemy(kind)
  return Units.ENEMIES[kind] ~= nil
end

function Unit.growth_def(u)
  local kind = type(u) == 'table' and u.kind or u
  local def = Units.ALLIES[kind]
  return def and def.growth or nil
end

function Unit.growth_target(u)
  local g = Unit.growth_def(u)
  return g and g.target_wins or nil
end

function Unit.growth_stage(u, level_override)
  local g = Unit.growth_def(u)
  if not g or not g.milestones then
    return nil
  end
  local stage = nil
  if level_override then
    for _, m in ipairs(g.milestones) do
      if level_override >= m.level then
        stage = m
      end
    end
    return stage
  end
  local wins = type(u) == 'table' and (u.growth_wins or 0) or 0
  for _, m in ipairs(g.milestones) do
    if wins >= m.wins then
      stage = m
    end
  end
  return stage
end

function Unit.level(u)
  local stage = Unit.growth_stage(u)
  return stage and stage.level or 1
end

function Unit.form(u)
  local stage = Unit.growth_stage(u)
  return stage and stage.form or nil
end

function Unit.is_drake(u)
  return Unit.form(u) == 'drake'
end

function Unit.is_mature(u)
  return Unit.form(u) == 'mature'
end

function Unit.sprite_key(u)
  if type(u) ~= 'table' then
    return u
  end
  local stage = Unit.growth_stage(u)
  return (stage and stage.sprite) or u.kind
end

function Unit.growth_hp_bonus(u)
  local stage = Unit.growth_stage(u)
  return stage and (stage.hp_bonus or 0) or 0
end

function Unit.growth_def_bonus(u)
  local stage = Unit.growth_stage(u)
  return stage and (stage.def_bonus or 0) or 0
end

function Unit.traits(u, level_override)
  if not u then
    return {}
  end
  if type(u) == 'string' then
    u = { kind = u }
  end
  local def = Units.ALLIES[u.kind] or Units.ENEMIES[u.kind] or {}
  local growth = Unit.growth_def(u)
  local stage = Unit.growth_stage(u, level_override)

  local out, indices = {}, {}
  local function add(id)
    local trait = Traits.definitions[id]
    if not trait then
      return
    end
    local idx = indices[trait.family]
    if idx then
      out[idx] = trait
    else
      out[#out + 1] = trait
      indices[trait.family] = #out
    end
  end

  for _, id in ipairs(def.traits or {}) do
    if growth and id == growth.trait_id and stage then
      add(stage.trait)
    else
      add(id)
    end
  end
  for _, id in ipairs(u.learned_traits or {}) do
    add(id)
  end
  for _, id in ipairs(u.unit_traits or {}) do
    add(id)
  end
  return out
end

function Unit.trait(u, family)
  for _, t in ipairs(Unit.traits(u)) do
    if t.family == family then
      return t
    end
  end
  return nil
end

function Unit.can_learn_trait(u, trait_id)
  local def = u and Units.ALLIES[u.kind]
  local trait = Traits.definitions[trait_id]
  if not def or not trait or not Traits.shop[trait_id] then
    return false
  end
  if #Unit.traits(u) >= Constants.MAX_TRAITS then
    return false
  end
  if Unit.trait(u, trait.family) then
    return false
  end
  -- Reserve the family of an immature growth unit's eventual signature ability.
  local growth = Unit.growth_def(u)
  if growth and growth.mature_trait then
    local mature_def = Traits.definitions[growth.mature_trait]
    if mature_def and mature_def.family == trait.family then
      return false
    end
  end
  return true
end

function Unit.max_hp(u)
  if type(u) == 'table' then
    if u.max then
      return u.max
    end
    local def = Units.ALLIES[u.kind] or Units.ENEMIES[u.kind] or {}
    return (u.max_hp or def.hp or 0) + Unit.growth_hp_bonus(u)
  end
  local def = Units.ALLIES[u] or Units.ENEMIES[u]
  return def and def.hp or 0
end

function Unit.attack(u, battle_state)
  local def = Units.ALLIES[u.kind] or Units.ENEMIES[u.kind] or {}
  local bonus = 0
  if battle_state then
    local momentum = battle_state.shifted_this_round and Unit.trait(u, 'momentum')
    if momentum then
      bonus = bonus + (momentum.amount or 2)
    end
    if Unit.trait(u, 'charge_aura') then
      bonus = bonus + math.floor((battle_state.charge or 0) / 2)
    end
    bonus = bonus + (battle_state.pressure or 0)
  end
  local atk_trait = Unit.trait(u, 'attack')
  return (u.atk or def.atk or 0) + (atk_trait and atk_trait.bonus or 0) + (u.combat_atk or 0) + bonus
end

function Unit.support_attack_bonus(battle_state, col)
  if not battle_state or not battle_state.line then
    return 0
  end
  local charge = battle_state.charge or 0
  local bonus = 0
  for j = 1, Constants.SLOTS do
    local u = battle_state.line[j]
    local ct = u and Unit.trait(u, 'charge_aura')
    if ct and charge >= (ct.aura_min or 2) then
      local amount = charge >= (ct.high_min or 5) and 2 or 1
      for _, target in ipairs(Unit.support_targets(battle_state.line, j, battle_state.relics)) do
        if target == col then
          bonus = bonus + amount
        end
      end
    end
  end
  return bonus
end

function Unit.defense(u)
  local def = Units.ALLIES[u.kind] or Units.ENEMIES[u.kind] or {}
  local armor = Unit.trait(u, 'armor')
  return (u.def or def.def or 0) + (armor and armor.amount or 0) + (u.combat_def or 0) + Unit.growth_def_bonus(u)
end

function Unit.motion(u)
  local trait = Unit.trait(u, 'motion')
  return trait and trait.motion or nil
end

function Unit.breach_amount(u)
  if not u then
    return 0
  end
  local def = Units.ENEMIES[u.kind]
  return u.brk or (def and def.brk) or 0
end

function Unit.support_targets(line, col, relics)
  local u = line[col]
  if not u then
    return {}
  end
  local reach = 1 + (Util.has_relic(relics, 'far_lens') and 1 or 0)
  local out = {}
  for distance = 1, reach do
    if col - distance >= 1 then
      out[#out + 1] = col - distance
    end
    if col + distance <= Constants.SLOTS then
      out[#out + 1] = col + distance
    end
  end
  return out
end

function Unit.taunt_target(line, col)
  if line[col] and Unit.trait(line[col], 'taunt') then
    return col
  end
  for _, j in ipairs({ col - 1, col + 1 }) do
    if line[j] and Unit.trait(line[j], 'taunt') then
      return j
    end
  end
  return nil
end

function Unit.attack_targets(u, col, enemies)
  local out = { col }
  local atk_trait = Unit.trait(u, 'attack')
  for _, offset in ipairs(atk_trait and atk_trait.offsets or {}) do
    local target = col + offset
    if target >= 1 and target <= Constants.SLOTS then
      out[#out + 1] = target
    end
  end

  local reach = Unit.trait(u, 'reach')
  if reach and (not enemies or not (enemies[col] and enemies[col].hp > 0)) then
    local target = col + reach.offset
    if enemies then
      local primary_valid = target >= 1 and target <= Constants.SLOTS and enemies[target] and enemies[target].hp > 0
      if not primary_valid then
        local alt = col - reach.offset
        if alt >= 1 and alt <= Constants.SLOTS and enemies[alt] and enemies[alt].hp > 0 then
          target = alt
        end
      end
    end
    if target >= 1 and target <= Constants.SLOTS and not Util.contains(out, target) then
      out[#out + 1] = target
    end
  end

  return out
end

function Unit.build_line(roster, offset)
  local line = {}
  local slots = Constants.SLOTS
  offset = offset or 0
  for i = 1, slots do
    local src = ((i - offset - 1) % slots) + 1
    local u = roster[src]
    if u then
      line[i] = Util.deep_copy(u)
      line[i].slot = src
      line[i].max = Unit.max_hp(u)
    end
  end
  return line
end

return Unit
