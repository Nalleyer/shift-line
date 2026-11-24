-- Act/node topology, pattern parsing, deterministic encounter generation, and threat summaries.
local Constants = require('data.constants')
local Encounters = require('data.encounters')
local Units = require('data.units')
local Rng = require('core.rng')
local Util = require('core.util')

local Encounter = {}

local MOTION_TRAIT_BY_MODE = {
  formation = 'boss_formation',
  tide = 'boss_tide',
  right = 'line_right',
}

function Encounter.act_of(wave)
  return math.max(1, math.ceil((wave or 1) / Constants.ACT_SIZE))
end

function Encounter.is_act_boss(wave)
  return wave ~= nil and wave % Constants.ACT_SIZE == 0
end

function Encounter.act_nodes(act)
  local a = math.max(1, math.min(Constants.ACTS, act or 1))
  local base = (a - 1) * Constants.ACT_SIZE
  if a == 1 then
    return {
      { col = 1, kind = 'battle', wave = 1, branch = 1 },
      { col = 2, kind = 'camp', wave = 2 },
      { col = 3, kind = 'battle', wave = 2, branch = 1 },
      { col = 4, kind = 'camp', wave = 3 },
      { col = 5, kind = 'battle', wave = 3, branch = 1, fork = true },
      { col = 5, kind = 'battle', wave = 3, branch = 2, fork = true, gauntlet = true },
      { col = 6, kind = 'camp', wave = 4, branch = 1 },
      { col = 6, kind = 'draft', wave = 4, branch = 2 },
      { col = 7, kind = 'battle', wave = 4, branch = 1 },
      { col = 8, kind = 'camp', wave = 5 },
      { col = 9, kind = 'boss', wave = 5, branch = 1 },
    }
  end
  return {
    { col = 1, kind = 'camp', wave = base + 1 },
    { col = 2, kind = 'battle', wave = base + 1, branch = 1 },
    { col = 3, kind = 'camp', wave = base + 2 },
    { col = 4, kind = 'battle', wave = base + 2, branch = 1 },
    { col = 5, kind = 'camp', wave = base + 3 },
    { col = 6, kind = 'battle', wave = base + 3, branch = 1, fork = true },
    { col = 6, kind = 'battle', wave = base + 3, branch = 2, fork = true, gauntlet = true },
    { col = 7, kind = 'camp', wave = base + 4, branch = 1 },
    { col = 7, kind = 'draft', wave = base + 4, branch = 2 },
    { col = 8, kind = 'battle', wave = base + 4, branch = 1 },
    { col = 9, kind = 'camp', wave = base + 5 },
    { col = 10, kind = 'boss', wave = base + 5, branch = 1 },
  }
end

function Encounter.mirror(pattern)
  return pattern:reverse()
end

function Encounter.rotate(pattern, n)
  n = n % Constants.SLOTS
  return pattern:sub(n + 1) .. pattern:sub(1, n)
end

function Encounter.parse_enemies(enc)
  local pattern = type(enc) == 'table' and enc.pattern or enc or ''
  local is_table = type(enc) == 'table'
  local motion = is_table and (enc.boss and (enc.boss_motion or 'formation') or enc.motion) or nil
  local motion_trait = motion and MOTION_TRAIT_BY_MODE[motion] or nil
  local out = {}
  local ids = {}

  for i = 1, Constants.SLOTS do
    local k = pattern:sub(i, i)
    local def = Units.ENEMIES[k]
    if def then
      ids[k] = (ids[k] or 0) + 1
      local hp = (is_table and enc.hp and enc.hp[k])
        or (is_table and enc.boss and enc.boss_hp)
        or def.hp
      local ut = is_table and enc.unit_traits and Util.deep_copy(enc.unit_traits[k]) or nil

      if motion_trait then
        ut = ut or {}
        table.insert(ut, 1, motion_trait)
      end
      if is_table and enc.boss and not (def.traits and Util.contains(def.traits, 'linked_core')) then
        ut = ut or {}
        if not Util.contains(ut, 'linked_core') then
          ut[#ut + 1] = 'linked_core'
        end
      end

      out[i] = {
        kind = k,
        uid = k .. ids[k],
        hp = hp,
        max = hp,
        max_hp = hp,
        atk = (is_table and enc.atk and enc.atk[k]) or def.atk,
        def = (is_table and enc.def and enc.def[k]) or def.def,
        brk = (is_table and enc.brk and enc.brk[k]) or def.brk,
        unit_traits = ut,
      }
    end
  end

  return out
end

local function transform_encounter(enc, should_mirror, phase, allow_rotate)
  if enc.boss and enc.boss_alt_pattern then
    if should_mirror then
      enc.boss_alt_pattern = Encounter.mirror(enc.boss_alt_pattern)
    end
    enc.boss_alt_pattern = Encounter.rotate(enc.boss_alt_pattern, phase)
  end
  if allow_rotate then
    if should_mirror then
      enc.pattern = Encounter.mirror(enc.pattern)
    end
    enc.pattern = Encounter.rotate(enc.pattern, phase)
  end
  return enc
end

function Encounter.generate_encounters(seed)
  local out = {}
  for w = 1, #Encounters.WAVES do
    local rng = Rng.stream(seed, w, 1)
    local enc = Util.deep_copy(rng:pick(Encounters.WAVES[w]))
    out[w] = transform_encounter(enc, rng:chance(0.5), rng:int(0, 5), w ~= 1)
  end
  return out
end

local function roll_draft_slots(wave, rng)
  local act = Encounter.act_of(wave)
  if act == 1 then
    local slot2 = rng:chance(0.65) and 'relic' or 'recruit'
    local slot3 = rng:chance(0.60) and 'gold' or 'upgrade'
    return { 'trait', slot2, slot3 }
  elseif act == 2 then
    local slot3 = rng:chance(0.55) and 'gold' or 'upgrade'
    return { 'trait', 'relic', slot3 }
  else
    local slot2 = rng:chance(0.60) and 'relic' or 'upgrade'
    local slot3 = slot2 == 'upgrade' and 'gold' or (rng:chance(0.55) and 'gold' or 'upgrade')
    return { 'trait', slot2, slot3 }
  end
end

function Encounter.generate_forks(seed)
  local out = {}
  for w, pool in pairs(Encounters.FORKS) do
    local rng = Rng.stream(seed, w, 4)
    local draft_rng = Rng.stream(seed, w, 5)
    local enc = Util.deep_copy(rng:pick(pool))
    enc.draft_slots = roll_draft_slots(w, draft_rng)
    out[w] = transform_encounter(enc, rng:chance(0.5), rng:int(0, 5), true)
  end
  return out
end

function Encounter.pattern_counts(pattern)
  if type(pattern) == 'table' then
    pattern = pattern.pattern
  end
  pattern = pattern or ''
  local counts = {}
  for _, k in ipairs(Units.ENEMY_ORDER) do
    counts[k] = 0
  end
  for i = 1, #pattern do
    local ch = pattern:sub(i, i)
    if counts[ch] ~= nil then
      counts[ch] = counts[ch] + 1
    end
  end
  return counts
end

function Encounter.threats(enc)
  local pattern = type(enc) == 'table' and enc.pattern or enc or ''
  local counts = Encounter.pattern_counts(pattern)
  local out = {}
  if type(enc) == 'table' and enc.boss then
    out[#out + 1] = 'boss'
  end
  if counts.l > 0 then
    out[#out + 1] = 'pierce'
  end
  if counts.x > 0 then
    out[#out + 1] = 'cleave'
  end
  if counts.b > 0 then
    out[#out + 1] = 'heavy'
  end
  if counts.s > 0 then
    out[#out + 1] = 'guard'
  end
  if type(enc) == 'table' and (enc.motion == 'right' or enc.boss_motion) then
    out[#out + 1] = 'mobile'
  end
  return out
end

return Encounter
