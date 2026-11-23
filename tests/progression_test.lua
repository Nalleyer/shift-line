package.path = './src/?.lua;./src/?/init.lua;' .. package.path

local Constants = require('data.constants')
local Units = require('data.units')
local Items = require('data.items')
local Traits = require('data.traits')
local Unit = require('core.unit')
local Encounter = require('core.encounter')
local Camp = require('core.camp')
local Run = require('core.run')

local function assert_eq(a, b, msg)
  if a ~= b then
    error((msg or 'assert_eq failed') .. ': got ' .. tostring(a) .. ', expected ' .. tostring(b), 2)
  end
end

local function assert_true(v, msg)
  if not v then
    error(msg or 'assert_true failed', 2)
  end
end

-- 1. Initialization defaults
local r0 = Run.new(777)
assert_eq(r0.wave, 1, 'starts on wave 1')
assert_eq(r0.phase, 'battle', 'starts in battle phase')
assert_eq(r0.gold, Constants.START_GOLD, 'starts with START_GOLD')
assert_eq(r0.core, Constants.CORE_MAX, 'starts with full core')
assert_eq(r0.fuse, Constants.FUSE_MAX, 'starts with full fuse')
assert_eq(r0.roster[Constants.START_SLOT].kind, Constants.START_UNIT, 'starter S at slot 3')
assert_eq(r0.inventory[1], 'shift_both', 'starts with shift_both')
assert_eq(r0.inventory[2], 'medkit', 'starts with medkit')

-- 2. Full 15-wave victory flow & gauntlet fork skip
local strong = Run.new(42, {
  [1] = { kind = 'S', hp = 12, max_hp = 12, atk = 6, def = 2 },
  [2] = { kind = 'B', hp = 10, max_hp = 10, atk = 6, def = 2 },
  [3] = { kind = 'T', hp = 14, max_hp = 14, atk = 5, def = 3 },
  [4] = { kind = 'M', hp = 10, max_hp = 10, atk = 4, def = 2 },
  [5] = { kind = 'S', hp = 12, max_hp = 12, atk = 6, def = 2 },
  [6] = { kind = 'B', hp = 10, max_hp = 10, atk = 6, def = 2 },
})
for w = 1, 15 do
  assert_eq(strong.wave, w, 'wave counter matches step ' .. w)
  assert_eq(strong.phase, 'battle', 'in battle phase at wave ' .. w)
  if strong:has_fork() then
    assert_true(w == 3 or w == 8 or w == 13, 'forks only on waves 3, 8, 13')
    if w == 3 then
      strong:choose_fork(2) -- gauntlet skips camp after wave 3
    else
      strong:choose_fork(1)
    end
  end
  local res = strong:fight(0)
  assert_true(res.won, 'strong roster wins wave ' .. w)
  strong:commit(res)
  assert_eq(strong.phase, 'result', 'commit enters result phase')
  strong:after_result()
  if w == 3 then
    assert_eq(strong.phase, 'battle', 'gauntlet choice skips camp after wave 3')
    assert_eq(strong.stats.forks_taken, 1, 'gauntlet increments forks_taken')
  elseif w < 15 then
    assert_eq(strong.phase, 'camp', 'normal win opens camp')
    assert_eq(strong.camp.kind, 'camp', 'run.camp populated')
    strong:finish_node()
  end
end
assert_eq(strong.phase, 'victory', 'winning wave 15 sets phase=victory')
assert_eq(strong.stats.waves_cleared, 15, 'waves_cleared=15')
assert_true(strong.stats.fuses_saved == 2, 'saving fuse across Act 1 and Act 2 bosses yields 2 fuses_saved')

-- 3. Wave 1 defeat flow
local doomed = Run.new(9, {})
doomed.roster[1] = nil
local lose_res = doomed:fight(0)
assert_true(not lose_res.won, 'empty roster loses wave 1')
doomed:commit(lose_res)
doomed:after_result()
assert_eq(doomed.phase, 'defeat', 'wave 1 defeat does not rewind (wave <= 1)')

-- 4. Deterministic camp generation & recruit coverage across 400 seeds + GROWTH_MAX_WAVE cutoff
local seen_recruits = {}
local rare_after_7 = 0
for seed = 1, 400 do
  local r_low = Run.new(seed)
  r_low.wave = 4
  r_low:open_camp(0, false)
  for _, o in ipairs(r_low:node_offers()) do
    if o.kind == 'recruit' then
      seen_recruits[o.class] = true
    end
  end
  local r_high = Run.new(seed)
  r_high.wave = Constants.GROWTH_MAX_WAVE + 1
  r_high:open_camp(0, false)
  for _, o in ipairs(r_high:node_offers()) do
    if o.kind == 'recruit' and o.slot_kind == 'rare' then
      rare_after_7 = rare_after_7 + 1
    end
  end
end
for _, c in ipairs(Units.ALLY_ORDER) do
  assert_true(seen_recruits[c], 'all ally classes reachable in camp: ' .. c)
end
assert_eq(rare_after_7, 0, 'rare growth recruits do not appear after GROWTH_MAX_WAVE')

local det_a, det_b = Run.new(555), Run.new(555)
det_a.wave, det_b.wave = 4, 4
det_a:open_camp(0, false)
det_b:open_camp(0, false)
assert_eq(#det_a:node_offers(), #det_b:node_offers(), 'same seed produces identical offer count')
for i = 1, #det_a:node_offers() do
  assert_eq(det_a:node_offers()[i].kind, det_b:node_offers()[i].kind, 'offer kind deterministic #' .. i)
  assert_eq(det_a:node_offers()[i].id, det_b:node_offers()[i].id, 'offer id deterministic #' .. i)
end

-- 5. Wave 2 gift core_cell, economy, dismiss, upgrade caps, inventory replacement, sell gear
local shop_run = Run.new(11)
shop_run.wave = 2
shop_run.gold = 20
shop_run:open_camp(0, false)
local gift_idx, dismiss_idx
for i, o in ipairs(shop_run:node_offers()) do
  if o.kind == 'active' and o.id == 'core_cell' then
    gift_idx = i
  elseif o.kind == 'dismiss' then
    dismiss_idx = i
  end
end
assert_true(gift_idx ~= nil, 'wave 2 offers free core_cell gift')
assert_eq(#Camp.offer_targets(shop_run, dismiss_idx), 0, 'cannot dismiss the sole survivor')
assert_true(shop_run:apply_offer(gift_idx), 'claim free wave 2 core_cell')
assert_eq(shop_run.inventory[3], 'core_cell', 'core_cell added to inventory')
assert_true(shop_run.wave2_gift_claimed, 'wave2_gift_claimed recorded')

-- Selling core_cell (price 0 -> sell value 0) and shift_both (price 3 -> sell value 1)
assert_eq(shop_run:sell_value('active', 3), 0, 'free core_cell has 0 sell value')
assert_true(shop_run:sell_gear('active', 3, 'core_cell'), 'selling core_cell succeeds for 0G')
assert_eq(shop_run:sell_value('active', 1), 1, 'shift_both sells for 1G')
assert_true(shop_run:sell_gear('active', 1, 'shift_both'), 'selling shift_both pays +1G')
assert_eq(shop_run.gold, 21, 'gold incremented after sale')

-- Upgrade caps & inventory max 3 replacement
shop_run.roster[1] = { kind = 'G', hp = 4, max_hp = 6 }
assert_true(#Camp.offer_targets(shop_run, dismiss_idx) == 2, 'dismiss allowed when >=2 alive')
assert_true(shop_run:apply_offer(dismiss_idx, 1), 'dismiss slot 1')
assert_eq(shop_run.gold, 22, 'dismiss grants +1G')

shop_run.inventory = { 'medkit', 'core_patch', 'shift_both' }
shop_run.camp.offers[1] = { kind = 'active', id = 'swap_kit', price = 4, available = true }
assert_eq(#shop_run:offer_targets(shop_run.camp.offers[1]), 3, 'full inventory exposes replacement slots 1..3')
assert_true(shop_run:apply_offer(1, 3), 'buying active with full bag replaces chosen slot')
assert_eq(shop_run.inventory[3], 'swap_kit', 'slot 3 replaced with swap_kit')

-- Camp item usage (medkit heals wounded unit, core_patch heals damaged core)
shop_run.roster[3].hp = 2
shop_run.core = 4
assert_true(shop_run:can_use_shop_item(1), 'medkit usable in camp')
assert_true(shop_run:use_shop_item(1, 3, 'medkit'), 'medkit heals slot 3')
assert_eq(shop_run.roster[3].hp, 5, 'slot 3 healed +3 HP (2->5)')
assert_true(shop_run:can_use_shop_item(1), 'core_patch usable in camp when core < core_max')
assert_true(shop_run:use_shop_item(1, 'core', 'core_patch'), 'core_patch restores +3 Core')
assert_eq(shop_run.core, 7, 'core restored 4->7 via core_patch')

-- Upgrade cap check
local max_atk = Units.ALLIES.S.atk + Constants.UPGRADE_CAPS.atk
shop_run.roster[3].atk = max_atk
local upg_offer = { kind = 'upgrade', mode = 'atk', price = 4, available = true }
assert_eq(#shop_run:offer_targets(upg_offer), 0, 'capped unit cannot receive more atk upgrades')

-- 6. Charge camp sinks: reroll (1), swap (2), triage (2)
local cr = Run.new(33)
cr.wave = 2
cr.charge = 6
cr.roster[4] = { kind = 'G', hp = 2 }
cr.roster[3].hp = 3
cr:open_camp(0, false)
-- Mark swap bought before reroll
for i, o in ipairs(cr:node_offers()) do
  if o.kind == 'swap' then
    assert_true(cr:apply_offer(i, 3, 2), 'paid camp swap moves S 3->2')
    break
  end
end
assert_true(cr:use_charge('reroll'), 'charge reroll costs 1 charge')
assert_eq(cr.charge, 5, 'reroll deducted 1 charge')
assert_eq(cr.camp.reroll_count, 1, 'reroll_count incremented')
for _, o in ipairs(cr:node_offers()) do
  if o.kind == 'swap' then
    assert_true(not o.available, 'swap remains unavailable after reroll')
  end
end
assert_true(cr:use_charge('swap', 2, 5), 'charge swap moves slot 2 -> 5')
assert_true(cr.roster[5] ~= nil and cr.roster[2] == nil, 'swap updated slots')
assert_true(cr:use_charge('triage'), 'charge triage heals all wounded allies +2 HP')
assert_eq(cr.roster[5].hp, 5, 'S healed 3->5')
assert_eq(cr.roster[4].hp, 4, 'G healed 2->4')
assert_eq(cr.charge, 1, 'charge sinks deducted 1+2+2=5 (6->1)')

-- 7. Unit growth milestones (A:5w, D:2/4/6w, N:3w)
local gr = Run.new(7)
gr.roster = {
  [1] = { kind = 'A', hp = 3 },
  [2] = { kind = 'D', hp = 4 },
  [3] = { kind = 'N', hp = 4 },
}
for w = 1, 6 do
  local mock_res = {
    won = true, reason = 'victory', core_damage = 0, core_after = gr.core,
    gold_earned = 0, casualties = 0, enemy_escaped = 0, rounds = 1,
    start_roster = gr.roster, end_roster = gr.roster,
  }
  gr.committed_wave = nil
  local sum = gr:commit(mock_res)
  gr.wave = gr.wave + 1
  if w == 2 then
    assert_eq(Unit.form(gr.roster[2]), 'drake', 'D evolves to drake at 2 wins')
    assert_eq(Unit.max_hp(gr.roster[2]), 5, 'drake gains +1 max HP')
    assert_eq(sum.survivors[2].level_after, 2, 'result summary records D level up')
  elseif w == 3 then
    assert_eq(Unit.form(gr.roster[3]), 'mature', 'N evolves to veteran at 3 wins')
    assert_eq(Unit.defense(gr.roster[3]), 1, 'veteran gains +1 DEF')
    assert_true(Unit.trait(gr.roster[3], 'attack') ~= nil, 'veteran gains sword_right')
  elseif w == 4 then
    assert_eq(Unit.max_hp(gr.roster[2]), 6, 'drake gains second HP bonus at 4 wins')
    assert_eq(Unit.defense(gr.roster[2]), 1, 'drake gains +1 DEF at 4 wins')
  elseif w == 5 then
    assert_eq(Unit.form(gr.roster[1]), 'mature', 'A evolves to blademaster at 5 wins')
    assert_true(Unit.trait(gr.roster[1], 'attack').id == 'sword_sides', 'blademaster gains sword_sides')
  elseif w == 6 then
    assert_eq(Unit.form(gr.roster[2]), 'mature', 'D evolves to dragon at 6 wins')
    assert_eq(Unit.level(gr.roster[2]), 3, 'dragon reaches level 3')
    assert_true(Unit.trait(gr.roster[2], 'attack').id == 'dragon_breath', 'dragon gains dragon_breath')
  end
end

-- 8. Trait capacity & reservation rules
local full_s = { kind = 'S', hp = 6, learned_traits = { 'guard_1', 'heal_1', 'taunt', 'pierce', 'momentum' } }
assert_true(not Unit.can_learn_trait(full_s, 'armor_1'), 'MAX_TRAITS (5) caps learned traits')
local full_d = { kind = 'D', hp = 4, learned_traits = { 'guard_1', 'heal_1', 'taunt', 'pierce' } }
assert_true(not Unit.can_learn_trait(full_d, 'armor_1'), 'D reaches MAX_TRAITS with 1 growth + 4 learned = 5')
local learned_d = { kind = 'D', hp = 4 }
assert_true(not Unit.can_learn_trait(learned_d, 'sword_sides'), 'D blocks teaching another attack-family trait')

-- 9. Act Fuse rewind, free swap, refresh, bonus gold, and boss exclusion
local fuse_run = Run.new(99)
fuse_run.wave = 2
fuse_run.core = 6
fuse_run.gold = 12
fuse_run.charge = 2
fuse_run:finish_node() -- saves battle_snapshot
-- Simulate defeat at wave 2
local w2_loss = {
  won = false, reason = 'wiped', core_damage = 4, core_after = 2,
  gold_earned = 5, casualties = 1, enemy_escaped = 0, rounds = 3,
  start_roster = fuse_run.roster, end_roster = {},
}
local loss_sum = fuse_run:commit(w2_loss)
assert_true(loss_sum.fuse_triggered and w2_loss.fuse_triggered, 'wave 2 defeat triggers Act Fuse rewind')
assert_eq(fuse_run.fuse, 0, 'fuse decremented 1->0')
fuse_run:after_result()
assert_eq(fuse_run.phase, 'camp', 'rewind reopens camp before wave 2')
assert_eq(fuse_run.wave, 2, 'rewind stays on wave 2')
assert_eq(fuse_run.gold, 12, 'snapshot restores pre-battle gold')
assert_eq(fuse_run.core, 6, 'snapshot restores pre-battle core')
assert_eq(fuse_run.free_swaps, 1, 'rewind grants 1 free swap')
assert_true(fuse_run.roster[3] ~= nil, 'snapshot restores fallen unit')

-- Min core floor on rewind when snapshot core was low
fuse_run.fuse = 1
fuse_run.core = 1
fuse_run:finish_node()
fuse_run:commit({
  won = false, reason = 'core', core_damage = 1, core_after = 0,
  gold_earned = 0, casualties = 0, enemy_escaped = 1, rounds = 1,
  start_roster = fuse_run.roster, end_roster = fuse_run.roster,
})
fuse_run:after_result()
assert_eq(fuse_run.core, Constants.FUSE_MIN_CORE, 'rewind raises low core up to FUSE_MIN_CORE (3)')

-- Boss victory refreshes spent fuse; boss defeat NEVER triggers fuse rewind
fuse_run.wave = 5
fuse_run.fuse = 0
fuse_run.gold = 10
fuse_run.committed_wave = nil
local boss_lose = {
  won = false, reason = 'overrun', core_damage = 0, core_after = 4,
  gold_earned = 0, casualties = 0, enemy_escaped = 0, rounds = 18,
  start_roster = fuse_run.roster, end_roster = fuse_run.roster,
}
fuse_run.fuse = 1
local bl_sum = fuse_run:commit(boss_lose)
assert_true(not bl_sum.fuse_triggered, 'boss defeat does NOT trigger fuse rewind')
fuse_run.committed_wave = nil
fuse_run.pending_rewind = nil
fuse_run.fuse = 0
local bw_sum = fuse_run:commit({
  won = true, reason = 'victory', core_damage = 0, core_after = 4,
  gold_earned = 12, casualties = 0, enemy_escaped = 0, rounds = 4,
  start_roster = fuse_run.roster, end_roster = fuse_run.roster,
})
assert_true(bw_sum.fuse_refreshed and fuse_run.fuse == 1, 'clearing Act 1 boss refreshes spent fuse')

-- 10. Engineer core_mend post-victory heal
local eng_run = Run.new(5, { [1] = { kind = 'E', hp = 5 } })
eng_run.core = 5
local e_sum = eng_run:commit({
  won = true, reason = 'victory', core_damage = 0, core_after = 5,
  gold_earned = 2, casualties = 0, enemy_escaped = 0, rounds = 1,
  start_roster = eng_run.roster, end_roster = eng_run.roster,
})
assert_eq(eng_run.core, 6, 'Engineer restores +1 Core after winning a wave')
assert_eq(e_sum.bonus_core, 1, 'summary records +1 bonus_core from Engineer')

print('progression_test.lua: ALL PASSED')
