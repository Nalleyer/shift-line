-- Deterministic pre-battle camp/shop stock generation and transaction rules.
local Constants = require('data.constants')
local Traits = require('data.traits')
local Units = require('data.units')
local Items = require('data.items')
local Rng = require('core.rng')
local Util = require('core.util')
local Unit = require('core.unit')

local Camp = {}

local function stock_equipment(run, rng, offers, kind, order, defs, count)
  local pool = {}
  for _, id in ipairs(order) do
    local d = defs[id]
    local cap_ok = kind ~= 'relic' or not d.max_stacks or Util.relic_count(run.relics, id) < d.max_stacks
    local rarity_ok = d.rarity ~= 'legendary' or run.wave >= 4
    local active_ok = kind ~= 'active' or run.wave > 2 or d.effect ~= 'shift'
    if d and rarity_ok and active_ok and cap_ok then
      pool[#pool + 1] = id
    end
  end

  for _ = 1, count do
    if #pool == 0 then
      break
    end
    local groups = {}
    local total = 0
    for _, id in ipairs(pool) do
      local tier = defs[id].rarity or 'common'
      if not groups[tier] then
        groups[tier] = {}
        total = total + (Constants.RARITY_WEIGHTS[tier] or 58)
      end
      groups[tier][#groups[tier] + 1] = id
    end

    local roll = rng:int(1, total)
    local chosen_tier
    for _, tier in ipairs(Constants.RARITY_ORDER) do
      if groups[tier] then
        roll = roll - (Constants.RARITY_WEIGHTS[tier] or 58)
        if roll <= 0 then
          chosen_tier = tier
          break
        end
      end
    end

    local group = groups[chosen_tier]
    local id = group[rng:int(1, #group)]
    for i, v in ipairs(pool) do
      if v == id then
        table.remove(pool, i)
        break
      end
    end

    local d = defs[id]
    offers[#offers + 1] = {
      kind = kind,
      id = id,
      price = d.price or 3,
      title = d.name,
      detail = d.description or d.short,
      available = true,
    }
  end
end

function Camp.generate_offers(run, reroll_count, swap_bought)
  local salt = (reroll_count or 0) * 10
  local rng = Rng.stream(run.seed, run.wave, 31 + salt)
  local recruit_rng = Rng.stream(run.seed, run.wave, 32 + salt)
  local trait_rng = Rng.stream(run.seed, run.wave, 33 + salt)

  local offers = {}
  local function add(o)
    if o.available == nil then
      o.available = true
    end
    offers[#offers + 1] = o
  end

  local used_classes = {}
  add({ kind = 'dismiss', price = -1, title = 'DISMISS', detail = 'REMOVE ONE UNIT' })

  for _ = 1, 3 do
    local pool = {}
    for _, c in ipairs(Units.COMMON_RECRUITS) do
      if not used_classes[c] then
        pool[#pool + 1] = c
      end
    end
    local recruit = pool[recruit_rng:int(1, #pool)]
    used_classes[recruit] = true
    local def = Units.ALLIES[recruit]
    add({
      kind = 'recruit',
      class = recruit,
      slot_kind = 'common',
      rarity = def.rarity or 'common',
      price = def.price or 4,
      title = 'RECRUIT',
      detail = 'PLACE A NEW UNIT',
    })
  end

  if run.wave <= Constants.GROWTH_MAX_WAVE and recruit_rng:chance(0.40) then
    local pool = {}
    for _, c in ipairs(Units.GROWTH_RECRUITS) do
      if not used_classes[c] then
        pool[#pool + 1] = c
      end
    end
    if #pool > 0 then
      local recruit = pool[recruit_rng:int(1, #pool)]
      used_classes[recruit] = true
      local def = Units.ALLIES[recruit]
      add({
        kind = 'recruit',
        class = recruit,
        slot_kind = 'rare',
        rarity = def.rarity or 'rare',
        price = def.price or 4,
        title = 'RECRUIT',
        detail = 'PLACE A NEW UNIT',
      })
    end
  end

  local modes = {}
  for _, mode in ipairs({ 'atk', 'hp', 'def' }) do
    if #Camp.offer_targets(run, { kind = 'upgrade', mode = mode }) > 0 then
      modes[#modes + 1] = mode
    end
  end
  local up_count = math.min(2, #modes)
  for _ = 1, up_count do
    local idx = rng:int(1, #modes)
    local mode = table.remove(modes, idx)
    add({ kind = 'upgrade', mode = mode, price = 4, title = 'UPGRADE', detail = 'IMPROVE A UNIT' })
  end

  local free_swap = (run.free_swaps or 0) > 0
  add({
    kind = 'swap',
    price = free_swap and 0 or 2,
    free = free_swap,
    title = 'ADJUST',
    detail = 'MOVE OR SWAP ONE UNIT',
    available = not swap_bought or free_swap,
  })

  if run.wave == 2 and (reroll_count or 0) == 0 and not run.wave2_gift_claimed then
    local gift = Items.ACTIVES.core_cell
    if gift then
      add({ kind = 'active', id = 'core_cell', price = 0, free = true, title = gift.name, detail = gift.description })
    end
  end

  stock_equipment(run, rng, offers, 'relic', Items.RELIC_ORDER, Items.RELICS, rng:int(1, 2))
  stock_equipment(run, rng, offers, 'active', Items.ACTIVE_ORDER, Items.ACTIVES, rng:int(1, 2))

  if trait_rng:chance(0.55) then
    local rare, epic = {}, {}
    for _, id in ipairs(Traits.shop_order) do
      local d = Traits.shop[id]
      if #Camp.offer_targets(run, { kind = 'trait', id = id }) > 0 then
        if d.rarity == 'epic' then
          if run.wave >= 4 then
            epic[#epic + 1] = id
          end
        else
          rare[#rare + 1] = id
        end
      end
    end
    local pool = (#epic > 0 and (#rare == 0 or trait_rng:chance(0.30))) and epic or rare
    if #pool > 0 then
      local id = pool[trait_rng:int(1, #pool)]
      local d = Traits.shop[id]
      add({ kind = 'trait', id = id, rarity = d.rarity, price = d.price, title = 'TRAIT', detail = 'TEACH ONE UNIT' })
    end
  end

  return offers
end

function Camp.offer_targets(run, offer)
  if type(offer) == 'number' then
    offer = run:node_offers()[offer]
  end
  if not offer then
    return {}
  end

  if offer.kind == 'recruit' then
    return run:empty_slots()
  elseif offer.kind == 'dismiss' then
    return run:alive_count() > 1 and run:alive_slots() or {}
  elseif offer.kind == 'trait' then
    local out = {}
    for _, i in ipairs(run:alive_slots()) do
      if Unit.can_learn_trait(run.roster[i], offer.id) then
        out[#out + 1] = i
      end
    end
    return out
  elseif offer.kind == 'active' then
    if #run.inventory < Constants.INVENTORY_MAX then
      return {}
    end
    return { 1, 2, 3 }
  elseif offer.kind == 'upgrade' then
    local out = {}
    local caps = Constants.UPGRADE_CAPS
    for _, i in ipairs(run:alive_slots()) do
      local u = run.roster[i]
      local base = Units.ALLIES[u.kind]
      local can_atk = offer.mode == 'atk' and (u.atk or base.atk) < base.atk + caps.atk
      local can_hp = offer.mode == 'hp' and (u.max_hp or base.hp) < base.hp + caps.hp
      local can_def = offer.mode == 'def' and (u.def or base.def or 0) < (base.def or 0) + caps.def
      if can_atk or can_hp or can_def then
        out[#out + 1] = i
      end
    end
    return out
  end

  return {}
end

function Camp.can_buy(run, index, slot, to)
  local o = run:node_offers()[index]
  if run.phase ~= 'camp' or not o or not o.available then
    return false, 'INVALID OFFER'
  end
  if run.gold < (o.price or 0) then
    return false, 'NOT ENOUGH GOLD'
  end

  if o.kind == 'recruit' and not Units.ALLIES[o.class] then
    return false, 'INVALID RECRUIT'
  end
  if o.kind == 'relic' then
    local d = Items.RELICS[o.id]
    if not d then
      return false, 'INVALID RELIC'
    end
    if d.max_stacks and Util.relic_count(run.relics, o.id) >= d.max_stacks then
      return false, 'MAX STACKS'
    end
  end
  if o.kind == 'active' and not Items.ACTIVES[o.id] then
    return false, 'INVALID ACTIVE'
  end
  if o.kind == 'trait' and not Traits.shop[o.id] then
    return false, 'INVALID TRAIT'
  end
  if o.kind == 'upgrade' and o.mode ~= 'atk' and o.mode ~= 'hp' and o.mode ~= 'def' then
    return false, 'INVALID UPGRADE'
  end

  if o.kind == 'swap' then
    if not Util.valid_slot(slot) or not Util.valid_slot(to) or slot == to or not run.roster[slot] then
      return false, 'INVALID TARGET'
    end
    return true
  end

  local targeted = o.kind == 'recruit'
    or o.kind == 'dismiss'
    or o.kind == 'upgrade'
    or o.kind == 'trait'
    or (o.kind == 'active' and #run.inventory >= Constants.INVENTORY_MAX)
  if targeted and not Util.contains(Camp.offer_targets(run, o), slot) then
    return false, 'INVALID TARGET'
  end

  return true
end

function Camp.apply_offer(run, index, slot, to)
  local ok, err = Camp.can_buy(run, index, slot, to)
  if not ok then
    return false, err
  end
  local o = run:node_offers()[index]

  if o.kind == 'swap' then
    run.roster[slot], run.roster[to] = run.roster[to], run.roster[slot]
    if o.free and (run.free_swaps or 0) > 0 then
      run.free_swaps = run.free_swaps - 1
    end
  elseif o.kind == 'recruit' then
    run:apply_recruit_at(o.class, slot)
  elseif o.kind == 'dismiss' then
    run.roster[slot] = nil
  elseif o.kind == 'trait' then
    local u = run.roster[slot]
    u.learned_traits = u.learned_traits or {}
    u.learned_traits[#u.learned_traits + 1] = o.id
  elseif o.kind == 'upgrade' then
    local u = run.roster[slot]
    local base = Units.ALLIES[u.kind]
    if o.mode == 'atk' then
      u.atk = (u.atk or base.atk) + 1
    elseif o.mode == 'hp' then
      local step = Constants.HP_UPGRADE_STEP
      u.max_hp = (u.max_hp or base.hp) + step
      u.hp = math.min(Unit.max_hp(u), u.hp + step)
    elseif o.mode == 'def' then
      u.def = (u.def or base.def or 0) + 1
    else
      return false, 'INVALID UPGRADE'
    end
  elseif o.kind == 'relic' then
    run.relics[#run.relics + 1] = o.id
  elseif o.kind == 'active' then
    if o.id == 'core_cell' then
      run.wave2_gift_claimed = true
    end
    if #run.inventory < Constants.INVENTORY_MAX then
      run.inventory[#run.inventory + 1] = o.id
    else
      run.inventory[slot] = o.id
    end
  else
    return false, 'INVALID OFFER'
  end

  run.gold = run.gold - (o.price or 0)
  o.available = false
  return true
end

function Camp.item_targets(run, index)
  if run.phase ~= 'camp' or type(index) ~= 'number' or index % 1 ~= 0 then
    return {}
  end
  local def = Items.ACTIVES[run.inventory[index]]
  if not def or not def.shop then
    return {}
  end
  if def.effect == 'heal' then
    return run:wounded_slots()
  end
  if def.effect == 'core' and run.core < run.core_max then
    return { 'core' }
  end
  return {}
end

function Camp.can_use_item(run, index)
  if run.phase ~= 'camp' then
    return false, 'unavailable'
  end
  if type(index) ~= 'number' or index % 1 ~= 0 then
    return false, 'invalid item'
  end
  local def = Items.ACTIVES[run.inventory[index]]
  if not def then
    return false, 'invalid item'
  end
  if not def.shop then
    return false, 'battle only'
  end
  if def.effect == 'core' and run.core >= run.core_max then
    return false, 'core full'
  end
  if #Camp.item_targets(run, index) == 0 then
    return false, 'no target'
  end
  return true
end

function Camp.use_item(run, index, target, expected_id)
  if not Camp.can_use_item(run, index) then
    return false
  end
  if expected_id and run.inventory[index] ~= expected_id then
    return false
  end
  if not Util.contains(Camp.item_targets(run, index), target) then
    return false
  end

  local def = Items.ACTIVES[run.inventory[index]]
  local amount = def.amount or 3
  local restored = def.effect == 'core' and run:apply_core(amount) or run:apply_heal(target, amount)
  if restored <= 0 then
    return false
  end

  table.remove(run.inventory, index)
  run.stats.items_used = run.stats.items_used + 1
  return true, restored
end

function Camp.sell_value(run, kind, index)
  if run.phase ~= 'camp' or (kind ~= 'relic' and kind ~= 'active') or type(index) ~= 'number' or index % 1 ~= 0 then
    return nil
  end
  local list = kind == 'relic' and run.relics or run.inventory
  local defs = kind == 'relic' and Items.RELICS or Items.ACTIVES
  local id = list[index]
  local def = id and defs[id]
  if not def or type(def.price) ~= 'number' then
    return nil
  end
  if def.price == 0 then
    return 0
  end
  return math.max(1, math.floor(def.price / 4))
end

function Camp.sell_gear(run, kind, index, expected_id)
  local value = Camp.sell_value(run, kind, index)
  if not value then
    return false
  end
  local list = kind == 'relic' and run.relics or run.inventory
  if expected_id and list[index] ~= expected_id then
    return false
  end
  table.remove(list, index)
  run.gold = run.gold + value
  return true, value
end

function Camp.use_charge(run, action, slot, to)
  if run.phase ~= 'camp' then
    return false, 'unavailable'
  end
  if action == 'reroll' then
    if (run.charge or 0) < 1 then
      return false, 'NOT ENOUGH CHARGE'
    end
    local swap_bought = false
    for _, o in ipairs(run:node_offers()) do
      if o.kind == 'swap' and not o.available then
        swap_bought = true
        break
      end
    end
    run.charge = run.charge - 1
    run.stats.charge_spent = (run.stats.charge_spent or 0) + 1
    local count = ((run.camp and run.camp.reroll_count) or 0) + 1
    run:open_camp(count, swap_bought)
    return true
  elseif action == 'swap' then
    if (run.charge or 0) < 2 then
      return false, 'NOT ENOUGH CHARGE'
    end
    if not Util.valid_slot(slot) or not Util.valid_slot(to) or slot == to or not run.roster[slot] then
      return false, 'INVALID TARGET'
    end
    run.charge = run.charge - 2
    run.stats.charge_spent = (run.stats.charge_spent or 0) + 2
    run.roster[slot], run.roster[to] = run.roster[to], run.roster[slot]
    return true
  elseif action == 'triage' then
    if (run.charge or 0) < 2 then
      return false, 'NOT ENOUGH CHARGE'
    end
    local wounded = run:wounded_slots()
    if #wounded == 0 then
      return false, 'no target'
    end
    run.charge = run.charge - 2
    run.stats.charge_spent = (run.stats.charge_spent or 0) + 2
    for _, i in ipairs(wounded) do
      run:apply_heal(i, 2)
    end
    return true
  end
  return false, 'invalid command'
end

return Camp
