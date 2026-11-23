package.path = './src/?.lua;./src/?/init.lua;' .. package.path

local Constants = require('data.constants')
local Units = require('data.units')
local Encounters = require('data.encounters')
local Util = require('core.util')
local Unit = require('core.unit')
local Encounter = require('core.encounter')
local Battle = require('core.battle')

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

local function make_unit(kind, overrides)
  local def = Units.ALLIES[kind]
  local u = { kind = kind, hp = def.hp }
  if overrides then
    for k, v in pairs(overrides) do
      u[k] = v
    end
  end
  return u
end

local function count_events(events, typ)
  local n = 0
  for _, ev in ipairs(events) do
    if ev.type == typ then
      n = n + 1
    end
  end
  return n
end

-- 1. Geometry & basic offset outcomes (S: hp=6, atk=2 at slot 3 vs single grunt g at col 1: hp=2, atk=1, brk=1)
local starter = { [3] = make_unit('S') }
local direct = Battle.simulate(starter, 'g.....', 4, 8) -- (3 + 4 - 1) % 6 + 1 = col 1!
assert_true(direct.won, 'aligned S kills g in col 1')
assert_eq(direct.core_damage, 0, 'aligned S prevents breach')
assert_eq(direct.gold_earned, 2, 'killing grunt yields 2g')
assert_eq(direct.end_roster[3].hp, 6, 'S attacks first and kills 2 HP grunt cleanly')

local misaligned = Battle.simulate(starter, 'g.....', 0, 8)
assert_true(misaligned.won, 'even after grunt escapes, empty enemy board counts as cleared')
assert_eq(misaligned.core_damage, 1, 'unblocked grunt deals 1 core damage')
assert_eq(misaligned.enemy_escaped, 1, 'misaligned grunt escapes after breach')
assert_eq(misaligned.gold_earned, 0, 'escaped grunt pays no bounty')
assert_eq(misaligned.charge_after, 1, '1 core breach generates 1 charge')

-- Empty roster loses immediately; zero enemies wins immediately
local empty_res = Battle.simulate({}, 'g.....', 0, 8)
assert_true(not empty_res.won and empty_res.reason == 'wiped', 'empty roster wipes immediately')
local pacifist_res = Battle.simulate(starter, '......', 0, 8)
assert_true(pacifist_res.won and pacifist_res.reason == 'victory', 'empty wave wins immediately')
assert_eq(pacifist_res.rounds, 0, 'empty wave ends in 0 rounds')

-- 2. Encounter generation & determinism
local e1 = Encounter.generate_encounters(12345)
local e2 = Encounter.generate_encounters(12345)
assert_eq(#e1, Constants.ACTS * Constants.ACT_SIZE, '15 waves generated')
for w = 1, #e1 do
  local p1 = type(e1[w]) == 'table' and e1[w].pattern or e1[w]
  local p2 = type(e2[w]) == 'table' and e2[w].pattern or e2[w]
  assert_eq(p1, p2, 'encounter generation deterministic at wave ' .. w)
end
assert_true(type(e1[5]) == 'table' and e1[5].boss, 'wave 5 is Act 1 boss')
assert_true(type(e1[10]) == 'table' and e1[10].boss, 'wave 10 is Act 2 boss')
assert_true(type(e1[15]) == 'table' and e1[15].boss, 'wave 15 is Act 3 boss')

local th = Encounter.threats({ pattern = 'lxsb..', boss = true, motion = 'right' })
assert_true(Util.contains(th, 'boss') and Util.contains(th, 'pierce') and Util.contains(th, 'cleave')
  and Util.contains(th, 'heavy') and Util.contains(th, 'guard') and Util.contains(th, 'mobile'),
  'threat summary reports boss, pierce, cleave, heavy, guard, and mobile tags')
local pc = Encounter.pattern_counts('grr.s.')
assert_eq(pc.r, 2, 'pattern_counts counts enemies')

-- 3. Traits: Guard + Shielding, Heal + Ward, Taunt, Volley, Pierce, Momentum
-- Guard + Shield: G at col 2 shields S at col 1 against r (atk=2)
local guard_res = Battle.simulate({ [1] = make_unit('S'), [2] = make_unit('G') }, 'r.....', 0, 8)
-- Wait: S kills r in round 1 (S atk=2 kills 2hp r). Use 5HP Brute b (atk=2, def=1, brk=3):
local g_vs_b = Battle.simulate({ [1] = make_unit('S'), [2] = make_unit('G') }, 'b.....', 0, 8)
-- Round 1: S hits b for 2-1=1 (4hp), G does 0. b hits S for 2 - 1(guard) = 1.
assert_true(g_vs_b.end_roster[1].hp < 6 and g_vs_b.end_roster[1].hp > 0, 'G protects adjacent ally to survive b')

-- M (Medic): heals wounded neighbor or wards full-HP neighbor (+1 combat_def absorbed)
local heal_b = Battle.new({ [1] = make_unit('S', { hp = 3 }), [2] = make_unit('M'), [3] = make_unit('S') }, 'g.g...', 0, 8)
local evs = Battle.step(heal_b)
assert_eq(heal_b.line[1].hp, 4, 'M heals wounded ally at slot 1 (+1 HP)')
local has_ward_action = false
for _, ev in ipairs(evs) do
  if ev.type == 'action' and ev.kind == 'guard' and ev.from == 2 then
    has_ward_action = true
    break
  end
end
assert_true(has_ward_action, 'M emits guard action for full-HP ally at slot 3')
assert_eq(heal_b.line[3].hp, 6, 'M ward blocks g attack so full-HP ally stays at 6 HP')

-- T (Taunt): pulls adjacent enemy attack (enemy in col 1 targets col 2 where T stands)
local taunt_b = Battle.new({ [2] = make_unit('T') }, 'r.....', 0, 8)
Battle.step(taunt_b)
assert_eq(taunt_b.core_damage, 0, 'T at col 2 taunts r at col 1 and prevents breach')
assert_eq(taunt_b.line[2].hp, 6, 'T takes max(0, 2-1)=1 dmg from r (7->6)')

-- B (Archer volley): attacks front + left + right with side_penalty (use 0-atk blockers at 1 & 3 so side g don't escape)
local archer_b = Battle.new({
  [1] = make_unit('G', { atk = 0 }),
  [2] = make_unit('B'),
  [3] = make_unit('G', { atk = 0 }),
}, 'ggg...', 0, 8)
Battle.step(archer_b)
assert_eq(Util.count_slots(archer_b.enemies), 2, 'B atk=2 kills front col 2 g and leaves col 1 & 3 alive at 1 HP')
assert_eq(archer_b.enemies[2], nil, 'B front lane g killed')
assert_eq(archer_b.enemies[1].hp, 1, 'B side lane g takes 1 dmg (2->1)')
assert_eq(archer_b.enemies[3].hp, 1, 'B side lane g takes 1 dmg (2->1)')

-- C (Lancer pierce): ignores armor on b (def=1, hp=5)
local pierce_b = Battle.new({ [1] = make_unit('C') }, 'b.....', 0, 8)
Battle.step(pierce_b)
assert_eq(pierce_b.enemies[1].hp, 3, 'C deals full 2 dmg ignoring Brute 1 DEF (5->3)')

-- W (Interceptor): intercepts first breach in enemy phase (1/round, +2 def, nearest W picks shortest wrap)
local inter_b = Battle.new({ [4] = make_unit('W') }, 'r.r...', 0, 8)
Battle.step(inter_b)
-- Enemy loop runs col 1 first -> W at col 4 wraps d=-3 to intercept col 1; col 3 still breaches for 2
assert_eq(inter_b.core_damage, 2, 'W intercepts first breach (col 1), second breach (col 3) deals 2 core dmg')
assert_true(inter_b.line[1] ~= nil, 'W shifted to col 1 during intercept')
assert_eq(inter_b.line[1].hp, 7, 'W takes max(0, 2 - (1 def + 2 intercept_def)) = 0 dmg from r')

-- When two W units exist, the nearest one intercepts without dragging other allies
local inter_near = Battle.new({ [2] = make_unit('W'), [5] = make_unit('W') }, '.....g', 0, 8)
Battle.step(inter_near)
assert_true(inter_near.line[6] ~= nil and inter_near.line[2] ~= nil and inter_near.line[5] == nil,
  'nearest W (slot 5, dist 1) moves to col 6 to intercept while slot 2 stays in place')

-- Two W units can each intercept once per round
local inter_two = Battle.new({ [2] = make_unit('W'), [5] = make_unit('W') }, 'g....g', 0, 8)
Battle.step(inter_two)
assert_eq(inter_two.core_damage, 0, 'two W units each intercept one breach in the same round')
assert_true(inter_two.line[1] ~= nil and inter_two.line[6] ~= nil, 'both W units moved to intercepting lanes')

-- Interceptor does NOT fire if Barricade ('compensation') blocks the breach
local inter_comp = Battle.new({ [4] = make_unit('W') }, 'g.....', 0, 8, { relics = { 'compensation' } })
Battle.step(inter_comp)
assert_true(inter_comp.line[4] ~= nil and inter_comp.line[1] == nil, 'W stays in slot 4 when Barricade blocks breach')

-- K (Kinetic / Overcharge): starts with min 1 charge and adds +1 extra on first breach
local k_b = Battle.new({ [6] = make_unit('K') }, 'g.....', 0, 8, { charge = 0 })
assert_eq(k_b.charge, 1, 'K raises battle start charge from 0 to 1')
Battle.step(k_b)
assert_eq(k_b.charge, 3, '1 breach gains 1+1(K bonus)=2 charge (1->3)')

-- E (Engineer / Core Mend): trait carries amount = 1 (post-victory heal tested in progression_test.lua)
assert_eq(Unit.trait(make_unit('E'), 'core_mend').amount, 1, 'E exposes core_mend amount = 1')

-- P (Pike): adjacent reach (side_penalty 1 -> 1 dmg) + left motion; R (Outrider): right motion + round-1 +1 ATK
local p_reach = Battle.new({ [1] = make_unit('G', { atk = 0 }), [2] = make_unit('P') }, 'g.....', 0, 8)
Battle.step(p_reach)
assert_eq(p_reach.enemies[1].hp, 1, 'P at col 2 reaches col 1 with max(1, 2-1)=1 dmg')

local p_move = Battle.new({ [2] = make_unit('P'), [5] = make_unit('G') }, 'g...b.', 0, 8)
Battle.step(p_move)
assert_true(p_move.line[1] ~= nil and p_move.line[2] == nil, 'P auto-shifts left into empty col 1 after round 1')

local r_b = Battle.new({ [1] = make_unit('R') }, 'b.....', 0, 8)
assert_eq(Unit.attack(r_b.line[1], r_b), 3, 'R gets +1 ATK at battle start (2->3)')
Battle.step(r_b)
assert_eq(r_b.enemies[1].hp, 3, 'R deals 3-1=2 dmg to Brute (5->3)')

local r_move = Battle.new({ [1] = make_unit('R'), [5] = make_unit('G') }, 'g...b.', 0, 8)
Battle.step(r_move)
assert_true(r_move.line[2] ~= nil and r_move.line[1] == nil, 'R auto-shifts right after defeating g in front of it')

-- Momentum trait (V): grants +3 ATK and +1 DEF in rounds where player shifted
local v_b = Battle.new({ [2] = make_unit('V') }, 'b.....', 0, 8, { charge = 1 })
assert_eq(Unit.attack(v_b.line[2], v_b), 2, 'V base ATK is 2 before shift')
local ok_cs = Battle.command(v_b, { type = 'deploy_shift', delta = -1 })
assert_true(ok_cs, 'deploy shift ok')
Battle.step(v_b)
-- Now force a charge_shift in round >= 1
ok_cs = Battle.command(v_b, { type = 'charge_shift', delta = 1 })
assert_true(ok_cs, 'charge shift ok after round 1')
assert_true(v_b.shifted_this_round, 'shifted_this_round set')
-- Attack bonus (2 base + 3 momentum = 5) applies right away before round ends
assert_eq(Unit.attack(v_b.line[2], v_b), 5, 'V gets +3 ATK when shifted_this_round')

-- 4. Charge caps & command restrictions
local cap_b = Battle.new({ [6] = make_unit('S') }, 'bbb...', 0, 8, { charge = 0, charge_max = 6 })
Battle.step(cap_b)
assert_eq(cap_b.charge, Constants.BATTLE_CHARGE_CAP, 'battle charge gain capped at BATTLE_CHARGE_CAP (3)')

local cs_r0 = Battle.new({ [3] = make_unit('S') }, 'g.....', 0, 8, { charge = 2 })
local ok0, _, err0 = Battle.command(cs_r0, { type = 'charge_shift', delta = 1 })
assert_true(not ok0 and err0 == 'unavailable', 'charge_shift disallowed before round 1')
local ok_d1 = Battle.command(cs_r0, { type = 'deploy_shift', delta = -1 })
assert_true(ok_d1, 'deploy_shift delta -1 allowed round 0')
Battle.step(cs_r0)
local ok_d_after = Battle.command(cs_r0, { type = 'deploy_shift', delta = 1 })
assert_true(not ok_d_after, 'deploy_shift disallowed after round 1')

-- 5. Boss mechanics: shared HP pool, AoE side dampening, boss shift, Navigator 3-slot shift, overrun
local boss_enc = Util.deep_copy(Encounters.BOSSES[1])
local boss_b = Battle.new({ [1] = make_unit('B', { atk = 4 }), [2] = make_unit('S') }, boss_enc, 0, 8, { relics = { 'navigator' } })
-- Col 1 enemy is 'a', Col 2 enemy is '.' or let's verify pattern 'a..c.a': col 1 is 'a'. B at col 1 hits col 1 (4 dmg) and... wait if pattern has another part adjacent e.g. 'ac....':
local aoe_boss = { pattern = 'ac....', boss = true, boss_id = 1, boss_hp = 20, atk = { a = 1, c = 2 }, def = { a = 0, c = 0 }, boss_period = 2, boss_motion = 'formation' }
local ab = Battle.new({ [1] = make_unit('D', { traits = { 'drake_breath' }, combat_atk = 3 }) }, aoe_boss, 0, 8)
-- Wait D base atk=1, drake_breath has offsets={-1,1}, piercing=true, no side_penalty? Let's test B with atk=4 at col 1 against 'ac....':
local aoe_b = Battle.new({ [1] = make_unit('B', { atk = 4 }) }, aoe_boss, 0, 8)
Battle.step(aoe_b)
-- Front col 1 gets 4 dmg; side col 2: side_penalty=1 -> 3 dmg, halved for boss AoE -> floor(3/2)=1 dmg. Total = 5 dmg -> 20 - 5 = 15!
assert_eq(aoe_b.boss_hp, 15, 'boss takes full front dmg (4) + halved side AoE dmg (1)')
Battle.step(aoe_b) -- round 2 triggers boss_shift
assert_true(aoe_b.boss_shift, 'boss shifts on period round 2')
assert_true(Battle.command(aoe_b, { type = 'boss_shift', delta = 1 }), 'player can respond with boss_shift')

local nav_b = Battle.new({ [1] = make_unit('S') }, aoe_boss, 0, 8, { relics = { 'navigator' } })
Battle.step(nav_b)
assert_true(Battle.command(nav_b, { type = 'navigator_shift', delta = 3 }), 'navigator shifts up to 3 slots')
local ok_over_nav = Battle.command(nav_b, { type = 'navigator_shift', delta = 1 })
assert_true(not ok_over_nav, 'navigator cannot exceed cumulative 3 slots per round')

-- Boss MAX_ROUNDS overrun defeat
local stall_boss = { pattern = 'c.....', boss = true, boss_id = 1, boss_hp = 999, atk = { c = 0 }, boss_motion = 'formation', boss_period = 99 }
local over_res = Battle.simulate({ [1] = make_unit('T', { hp = 999 }) }, stall_boss, 0, 8)
assert_true(not over_res.won and over_res.reason == 'overrun', 'boss reaching MAX_ROUNDS causes overrun defeat')

-- 6. Stalemate / pressure escalation breaks unbreakable stalls
local stall_b = Battle.new({ [1] = make_unit('T', { atk = 0, def = 2 }) }, { pattern = 'b.....', hp = { b = 99 }, atk = { b = 1 } }, 0, 8)
Battle.step(stall_b)
assert_eq(stall_b.pressure, 1, 'zero-progress round increments stalemate pressure')
Battle.step(stall_b)
assert_eq(stall_b.pressure, 2, 'pressure escalates each zero-progress round')
Battle.step(stall_b)
assert_true(stall_b.line[1].hp < 7, 'escalated pressure eventually deals damage through high DEF')

-- Intercept + rolling line_right zero-damage chase loop must trigger stalemate pressure instead of looping at pressure=0
local chase_b = Battle.new(
  {
    [1] = make_unit('A', { atk = 6, def = 2, growth_wins = 5 }),
    [2] = make_unit('W'),
    [4] = make_unit('K', { atk = 2 }),
    [6] = make_unit('S', { hp = 1 }),
  },
  { pattern = '..r...', hp = { r = 5 }, atk = { r = 3 }, motion = 'right', elite = true },
  0,
  6
)
Battle.step(chase_b)
assert_eq(chase_b.pressure, 1, 'intercept + rolling enemy 0-dmg loop increments pressure despite reposition')
local chase_sim = Battle.simulate(
  {
    [1] = make_unit('A', { atk = 6, def = 2, growth_wins = 5 }),
    [2] = make_unit('W'),
    [4] = make_unit('K', { atk = 2 }),
    [6] = make_unit('S', { hp = 1 }),
  },
  { pattern = '..r...', hp = { r = 5 }, atk = { r = 3 }, motion = 'right', elite = true },
  0,
  6
)
assert_true(chase_sim.rounds < Constants.MAX_ROUNDS, 'rolling intercept chase resolves via pressure before MAX_ROUNDS')

-- Matched heal + damage zero-net-HP loop (M + W vs rolling enemy) also escalates pressure and resolves
local heal_loop_sim = Battle.simulate(
  { [1] = make_unit('M'), [2] = make_unit('W') },
  { pattern = '..r...', hp = { r = 5 }, atk = { r = 3 }, motion = 'right', elite = true },
  0,
  6
)
assert_true(heal_loop_sim.rounds < Constants.MAX_ROUNDS, 'M + W heal-intercept loop resolves via pressure before MAX_ROUNDS')

-- 7. Relics & stacking: whetstone, padding, far_lens, bounty, insurance
local far_targets = Unit.support_targets({ [3] = make_unit('M'), [5] = make_unit('S') }, 3, { 'far_lens' })
assert_true(Util.contains(far_targets, 1) and Util.contains(far_targets, 5), 'far_lens extends support reach to 2 slots')

local pad_b = Battle.new({ [1] = make_unit('S') }, 'r.....', 0, 8, { relics = { 'padding' } })
-- Wait S kills r round 1; use Brute b (atk=2, hp=5, def=1): padding reduces round-1 dmg 2->1 (6->5)
local pad_b2 = Battle.new({ [1] = make_unit('S') }, 'b.....', 0, 8, { relics = { 'padding' } })
Battle.step(pad_b2)
assert_eq(pad_b2.line[1].hp, 5, 'padding reduces Brute round-1 attack (2 - 1 = 1 dmg, 6->5)')

local b2 = Battle.new(
  { [1] = make_unit('S'), [2] = make_unit('M', { hp = 1 }) },
  { pattern = 'bg....', hp = { b = 4 } }, 0, 8,
  { relics = { 'whetstone', 'whetstone', 'bounty', 'insurance' } }
)
-- Wait: let M die or survive vs r at col 2 while S hits b at col 1, AND let S kill g?
-- Test whetstone + insurance cleanly on 'br....', and bounty cleanly on 'g.....':
local b_ins = Battle.new(
  { [1] = make_unit('S'), [2] = make_unit('M', { hp = 1 }) },
  { pattern = 'br....', hp = { b = 4 } }, 0, 8,
  { relics = { 'whetstone', 'whetstone', 'insurance' } }
)
Battle.step(b_ins)
assert_eq(b_ins.enemies[1].hp, 1, 'double whetstone adds +2 round-1 ATK (4 vs 1 def = 3 dmg, 4->1)')
assert_eq(b_ins.line[2].hp, 1, 'insurance keeps M alive at 1 HP against lethal strike')

local b_bounty = Battle.simulate({ [1] = make_unit('S') }, 'g.....', 0, 8, { relics = { 'bounty', 'bounty' } })
assert_eq(b_bounty.gold_earned, 4, 'double bounty grants +2 extra gold on grunt kill (2 base + 2 = 4)')

-- 8. Active items in battle: shift_both_3 (step/cancel/finish), medkit, core_patch, core_cell, battle_draught, guard_plate, swap_kit
local it_b = Battle.new(
  { [1] = make_unit('S', { hp = 3 }), [2] = make_unit('G') },
  'b.....', 0, 4,
  { core_max = 8, inventory = { 'shift_both_3', 'medkit', 'core_cell' } }
)
Battle.step(it_b)
assert_true(Battle.can_use_item(it_b, 1), 'shift_both_3 usable after round 1')
local ok_sh, ev_sh = Battle.command(it_b, { type = 'item', index = 1, delta = 1 })
assert_true(ok_sh and it_b.shift_moves ~= nil and #ev_sh >= 1, 'shift_both_3 opens modal and moves +1')
assert_true(Battle.command(it_b, { type = 'shift_step', delta = 1 }), 'shift_step +1')
assert_eq(it_b.shift_moves.remaining, 1, 'shift_both_3 has 1 step remaining after 2 moves')
assert_true(Battle.command(it_b, { type = 'shift_cancel' }), 'shift_cancel restores origin and keeps item')
assert_eq(#it_b.inventory, 3, 'cancelled shift_both_3 remains in inventory')
assert_true(it_b.line[1] ~= nil and it_b.line[3] == nil, 'shift_cancel reverts line back to origin')

assert_true(Battle.command(it_b, { type = 'item', index = 1, delta = -1 }), 're-open shift_both_3')
assert_true(Battle.command(it_b, { type = 'shift_finish' }), 'shift_finish consumes item')
assert_eq(#it_b.inventory, 2, 'finished shift consumed 1 item')
assert_true(it_b.line[6] ~= nil, 'S shifted -1 to slot 6')

-- Now inventory[1] is medkit (slot 6 S is wounded, slot 1 G is full HP)
local heal_targets = Battle.item_targets(it_b, 1)
assert_eq(#heal_targets, 1, 'medkit only targets wounded slots')
assert_true(not Battle.command(it_b, { type = 'item', index = 1, target = 1 }), 'medkit rejects full HP unit')
assert_true(Battle.command(it_b, { type = 'item', index = 1, target = 6 }), 'medkit heals wounded unit')
assert_true(Battle.command(it_b, { type = 'item', index = 1 }), 'core_cell restores +1 core in battle')

-- Swap kit, battle draught, guard plate
local buff_b = Battle.new(
  { [1] = make_unit('S'), [2] = make_unit('G') },
  'b.....', 0, 8,
  { inventory = { 'battle_draught', 'guard_plate', 'swap_kit' } }
)
assert_true(Battle.command(buff_b, { type = 'item', index = 1, target = 1 }), 'combat stim +2 ATK')
assert_true(Battle.command(buff_b, { type = 'item', index = 1, target = 1 }), 'guard plate +2 DEF')
assert_true(Battle.command(buff_b, { type = 'item', index = 1, from = 1, to = 2 }), 'swap kit swaps slot 1 & 2')
assert_eq(buff_b.line[2].kind, 'S', 'S moved to slot 2 via swap_kit')

print('combat_test.lua: ALL PASSED')
