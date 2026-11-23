-- Persistent run state across waves, forks, camps, and Act Fuse rewinds.
local Constants = require('data.constants')
local Units = require('data.units')
local Encounters = require('data.encounters')
local Util = require('core.util')
local Unit = require('core.unit')
local Encounter = require('core.encounter')
local Battle = require('core.battle')
local Camp = require('core.camp')

local Run = {}
Run.__index = Run

local function copy_roster(roster)
  local out = {}
  for i = 1, Constants.SLOTS do
    if roster[i] then
      out[i] = Util.deep_copy(roster[i])
    end
  end
  return out
end

function Run.new(seed, start_roster)
  local self = setmetatable({
    seed = seed or 1,
    wave = 1,
    core = Constants.CORE_MAX,
    core_max = Constants.CORE_MAX,
    charge = 0,
    charge_max = Constants.CHARGE_MAX,
    fuse = Constants.FUSE_MAX,
    fuse_max = Constants.FUSE_MAX,
    free_swaps = 0,
    pending_rewind = nil,
    roster = {},
    relics = {},
    inventory = Util.deep_copy(Constants.START_INVENTORY),
    gold = Constants.START_GOLD,
    phase = 'battle',
    last = nil,
    summary = nil,
    stats = {
      waves_cleared = 0,
      core_lost = 0,
      units_lost = 0,
      enemies_escaped = 0,
      rounds = 0,
      items_used = 0,
      charge_earned = 0,
      charge_spent = 0,
      fuses_used = 0,
      fuses_saved = 0,
      forks_taken = 0,
    },
  }, Run)

  if start_roster then
    for i = 1, Constants.SLOTS do
      local v = start_roster[i]
      local kind = type(v) == 'table' and v.kind or v
      if kind and Units.ALLIES[kind] then
        self.roster[i] = type(v) == 'table' and Util.deep_copy(v) or { kind = kind, hp = Units.ALLIES[kind].hp }
      end
    end
  else
    local starter_kind = Constants.START_UNIT
    self.roster[Constants.START_SLOT] = {
      kind = starter_kind,
      hp = Units.ALLIES[starter_kind].hp,
      starter = true,
    }
  end

  self.encounters = Encounter.generate_encounters(self.seed)
  self.standard_encounters = Util.deep_copy(self.encounters)
  self.fork_encounters = Encounter.generate_forks(self.seed)
  self.fork_choices = {}
  return self
end

function Run:act()
  return Encounter.act_of(self.wave)
end

function Run:encounter()
  return self.encounters[self.wave]
end

function Run:boss_encounter()
  return self.encounters[#Encounters.WAVES]
end

function Run:act_boss_encounter(act)
  local a = act or self:act()
  local w = math.min(#Encounters.WAVES, a * Constants.ACT_SIZE)
  return self.encounters[w]
end

function Run:has_fork(wave)
  local w = wave or self.wave
  return self.fork_encounters and self.fork_encounters[w] ~= nil
end

function Run:fork_pair(wave)
  local w = wave or self.wave
  return (self.standard_encounters and self.standard_encounters[w]) or self.encounters[w],
    self.fork_encounters and self.fork_encounters[w]
end

function Run:fork_choice(wave)
  return (self.fork_choices and self.fork_choices[wave or self.wave]) or 1
end

function Run:choose_fork(choice, wave)
  local w = wave or self.wave
  if not self:has_fork(w) or (choice ~= 1 and choice ~= 2) then
    return false
  end
  self.fork_choices[w] = choice
  local std, alt = self:fork_pair(w)
  self.encounters[w] = Util.deep_copy(choice == 2 and alt or std)
  return true
end

function Run:is_gauntlet_wave(wave)
  local prev = (wave or self.wave) - 1
  return prev >= 1 and self:has_fork(prev) and self:fork_choice(prev) == 2
end

function Run:pattern()
  local e = self:encounter()
  return type(e) == 'table' and e.pattern or e
end

function Run:is_last_wave()
  return self.wave >= #Encounters.WAVES
end

function Run:alive_slots()
  local out = {}
  for i = 1, Constants.SLOTS do
    if self.roster[i] then
      out[#out + 1] = i
    end
  end
  return out
end

function Run:alive_count()
  return #self:alive_slots()
end

function Run:empty_slots()
  local out = {}
  for i = 1, Constants.SLOTS do
    if not self.roster[i] then
      out[#out + 1] = i
    end
  end
  return out
end

function Run:wounded_slots()
  local out = {}
  for i = 1, Constants.SLOTS do
    local u = self.roster[i]
    if u and u.hp > 0 and u.hp < Unit.max_hp(u) then
      out[#out + 1] = i
    end
  end
  return out
end

function Run:total_hp()
  local total = 0
  for _, i in ipairs(self:alive_slots()) do
    total = total + self.roster[i].hp
  end
  return total
end

function Run:max_total_hp()
  local total = 0
  for _, i in ipairs(self:alive_slots()) do
    total = total + Unit.max_hp(self.roster[i])
  end
  return total
end

function Run:apply_core(amount)
  local prev = self.core
  self.core = math.min(self.core_max, self.core + amount)
  return self.core - prev
end

function Run:apply_heal(slot, amount)
  local u = self.roster[slot]
  if not u then
    return 0
  end
  local prev = u.hp
  u.hp = math.min(Unit.max_hp(u), u.hp + amount)
  return u.hp - prev
end

function Run:apply_recruit_at(kind, slot)
  if not Util.valid_slot(slot) or self.roster[slot] or not Units.ALLIES[kind] then
    return nil
  end
  self.roster[slot] = { kind = kind, hp = Units.ALLIES[kind].hp }
  return slot
end

function Run:save_battle_snapshot()
  self.battle_snapshot = {
    wave = self.wave,
    roster = copy_roster(self.roster),
    core = self.core,
    gold = self.gold,
    charge = self.charge,
    relics = Util.deep_copy(self.relics),
    inventory = Util.deep_copy(self.inventory),
  }
end

function Run:fight(offset)
  return Battle.simulate(self.roster, self:encounter(), offset, self.core, {
    relics = self.relics,
    inventory = self.inventory,
    core_max = self.core_max,
    charge = self.charge,
    charge_max = self.charge_max,
  })
end

function Run:start_battle(offset)
  if self.wave > 1 and (not self.battle_snapshot or self.battle_snapshot.wave ~= self.wave) then
    self:save_battle_snapshot()
  end
  return Battle.new(self.roster, self:encounter(), offset, self.core, {
    relics = self.relics,
    inventory = self.inventory,
    core_max = self.core_max,
    charge = self.charge,
    charge_max = self.charge_max,
  })
end

function Run:commit(result)
  if self.committed_wave == self.wave then
    return self.summary
  end
  self.committed_wave = self.wave
  self.last = result

  local enc = self:encounter()
  local is_boss = (type(enc) == 'table' and enc.boss) or self:is_last_wave()
  local bonus_gold = (result.won and type(enc) == 'table' and enc.bonus_gold) or 0
  local bonus_core = (result.won and type(enc) == 'table' and enc.bonus_core) or 0
  local bonus_charge = (result.won and type(enc) == 'table' and enc.bonus_charge) or 0

  if result.won and self:has_fork() and self:fork_choice() == 2 then
    self.stats.forks_taken = (self.stats.forks_taken or 0) + 1
  end

  self.gold = self.gold + (result.gold_earned or 0) + bonus_gold
  self.core = result.core_after
  local gained_core = bonus_core > 0 and self:apply_core(bonus_core) or 0
  if result.charge_after ~= nil then
    self.charge = result.charge_after
  end

  if bonus_charge > 0 then
    local room = math.max(0, (self.charge_max or Constants.CHARGE_MAX) - self.charge)
    local add_c = math.min(bonus_charge, room)
    self.charge = self.charge + add_c
    self.stats.charge_earned = (self.stats.charge_earned or 0) + add_c
    bonus_charge = add_c
  end

  self.stats.charge_earned = (self.stats.charge_earned or 0) + (result.charge_earned or 0)
  self.stats.charge_spent = (self.stats.charge_spent or 0) + (result.charge_spent or 0)

  if result.inventory then
    self.inventory = {}
    for i, item in ipairs(result.inventory) do
      self.inventory[i] = item
    end
  end
  self.stats.items_used = self.stats.items_used + #(result.items_used or {})

  local summary = {
    survivors = {},
    fallen = {},
    core_damage = result.core_damage,
    gold_earned = (result.gold_earned or 0) + bonus_gold,
    bonus_gold = bonus_gold,
    bonus_core = gained_core,
    bonus_charge = bonus_charge,
  }

  local next_roster = {}
  for i = 1, Constants.SLOTS do
    local a, b = result.start_roster[i], result.end_roster[i]
    if b then
      local unit = Util.deep_copy(b)
      next_roster[i] = unit
      local old_level = Unit.level(b)
      local old_hp_bonus = Unit.growth_hp_bonus(b)
      local target = Unit.growth_target(b)
      local prev_wins = b.growth_wins or 0

      if result.won and target then
        unit.growth_wins = math.min(target, prev_wins + 1)
      elseif not target then
        unit.growth_wins = nil
      end

      local max_hp = Unit.max_hp(unit)
      local growth_heal = result.won and math.max(0, Unit.growth_hp_bonus(unit) - old_hp_bonus) or 0
      local heal = 1 + Util.relic_count(self.relics, 'field_rations') + growth_heal
      local hp = result.won and math.min(max_hp, b.hp + heal) or b.hp
      unit.hp = hp

      summary.survivors[#summary.survivors + 1] = {
        slot = i,
        kind = b.kind,
        from = a and a.hp or b.hp,
        end_hp = b.hp,
        to = hp,
        max = max_hp,
        level_before = old_level,
        level_after = Unit.level(unit),
        wins = unit.growth_wins or 0,
      }
    elseif a then
      summary.fallen[#summary.fallen + 1] = { slot = i, kind = a.kind }
    end
  end

  if result.won then
    for i = 1, Constants.SLOTS do
      local u = next_roster[i]
      local cm = u and Unit.trait(u, 'core_mend')
      if cm then
        local mended = self:apply_core(cm.amount or 1)
        gained_core = gained_core + mended
        summary.bonus_core = gained_core
      end
    end
  end

  self.roster = next_roster

  if result.won then
    self.stats.waves_cleared = self.wave
    if Encounter.is_act_boss(self.wave) and not self:is_last_wave() then
      if (self.fuse or 0) > 0 then
        self.gold = self.gold + Constants.FUSE_BONUS_GOLD
        summary.fuse_bonus = Constants.FUSE_BONUS_GOLD
        self.stats.fuses_saved = (self.stats.fuses_saved or 0) + 1
      else
        summary.fuse_refreshed = true
      end
      self.fuse = self.fuse_max or Constants.FUSE_MAX
    end
  elseif self.wave > 1 and not is_boss and (self.fuse or 0) > 0 then
    self.fuse = self.fuse - 1
    self.stats.fuses_used = (self.stats.fuses_used or 0) + 1
    self.pending_rewind = true
    summary.fuse_triggered = true
    summary.fuse_reason = result.reason
    result.fuse_triggered = true
  end

  self.stats.core_lost = self.stats.core_lost + (result.core_damage or 0)
  self.stats.units_lost = self.stats.units_lost + (result.casualties or 0)
  self.stats.enemies_escaped = self.stats.enemies_escaped + (result.enemy_escaped or 0)
  self.stats.rounds = self.stats.rounds + (result.rounds or 0)

  self.summary = summary
  self.phase = 'result'
  return summary
end

function Run:after_result()
  if self.phase ~= 'result' then
    return
  end
  if self.pending_rewind then
    self.pending_rewind = nil
    local snap = self.battle_snapshot
    if snap and snap.wave == self.wave then
      self.roster = copy_roster(snap.roster)
      self.core = math.max(math.min(Constants.FUSE_MIN_CORE, self.core_max), snap.core)
      self.gold = snap.gold
      self.charge = snap.charge
      self.relics = Util.deep_copy(snap.relics)
      self.inventory = Util.deep_copy(snap.inventory)
    else
      self.core = math.max(math.min(Constants.FUSE_MIN_CORE, self.core_max), self.core)
    end
    self.free_swaps = (self.free_swaps or 0) + 1
    self.committed_wave = nil
    self.battle_snapshot = nil
    self:open_camp(0, false)
    return
  end

  if self.last and not self.last.won then
    self.phase = 'defeat'
  elseif self:is_last_wave() then
    self.phase = 'victory'
  else
    local prev_wave = self.wave
    self.wave = self.wave + 1
    if self:has_fork(prev_wave) and self:fork_choice(prev_wave) == 2 then
      self.camp = nil
      self.phase = 'battle'
      self:save_battle_snapshot()
    else
      self:open_camp()
    end
  end
end

function Run:finish_node()
  self:save_battle_snapshot()
  self.camp = nil
  self.phase = 'battle'
end

function Run:open_camp(reroll_count, swap_bought)
  self.phase = 'camp'
  self.camp = {
    kind = 'camp',
    reroll_count = reroll_count or 0,
    offers = Camp.generate_offers(self, reroll_count, swap_bought),
  }
end

function Run:node_offers()
  return self.camp and self.camp.offers or {}
end

function Run:offer_targets(offer)
  return Camp.offer_targets(self, offer)
end

function Run:can_buy(index, slot, to)
  return Camp.can_buy(self, index, slot, to)
end

function Run:apply_offer(index, slot, to)
  return Camp.apply_offer(self, index, slot, to)
end

function Run:shop_item_targets(index)
  return Camp.item_targets(self, index)
end

function Run:can_use_shop_item(index)
  return Camp.can_use_item(self, index)
end

function Run:use_shop_item(index, target, expected_id)
  return Camp.use_item(self, index, target, expected_id)
end

function Run:sell_value(kind, index)
  return Camp.sell_value(self, kind, index)
end

function Run:sell_gear(kind, index, expected_id)
  return Camp.sell_gear(self, kind, index, expected_id)
end

function Run:use_charge(action, slot, to)
  return Camp.use_charge(self, action, slot, to)
end

return Run
