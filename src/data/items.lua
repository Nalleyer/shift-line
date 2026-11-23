-- Passive relics and active consumables shared across combat, camp, and UI.
local RELICS = {
  whetstone = {
    name = 'WHETSTONE',
    short = 'ROUND 1 ATK',
    description = '+1 ATK for all allies in round 1.',
    icon = 'whetstone',
    rarity = 'common',
    price = 4,
    max_stacks = 2,
  },
  padding = {
    name = 'PLATING',
    short = 'ROUND 1 DEF',
    description = '+1 DEF for all allies in round 1.',
    icon = 'padding',
    rarity = 'common',
    price = 3,
    max_stacks = 2,
  },
  far_lens = {
    name = 'FAR LENS',
    short = 'FAR SUPPORT',
    description = 'Support abilities also reach 2 slots away.',
    icon = 'far_lens',
    rarity = 'rare',
    price = 5,
    max_stacks = 1,
  },
  compensation = {
    name = 'BARRICADE',
    short = 'BLOCK BREACH',
    description = 'Block the first core breach each battle.',
    icon = 'compensation',
    rarity = 'rare',
    price = 5,
    max_stacks = 2,
  },
  insurance = {
    name = 'LAST STAND',
    short = 'SURVIVE ONCE',
    description = 'Once per battle, survive a lethal hit at 1 HP.',
    icon = 'insurance',
    rarity = 'epic',
    price = 7,
    max_stacks = 2,
  },
  bounty = {
    name = 'BOUNTY',
    short = 'KILL GOLD +1',
    description = '+1 extra gold for every enemy slain.',
    icon = 'bounty',
    rarity = 'rare',
    price = 6,
    max_stacks = 2,
  },
  field_rations = {
    name = 'FIELD RATIONS',
    short = 'WIN HEAL +1',
    description = 'Survivors heal +1 extra HP after victory.',
    icon = 'field_rations',
    rarity = 'common',
    price = 3,
    max_stacks = 1,
  },
  navigator = {
    name = 'NAVIGATOR',
    short = 'ROTATE',
    description = 'Between rounds, shift the line up to 3 slots either way.',
    icon = 'navigator',
    rarity = 'legendary',
    price = 9,
    max_stacks = 1,
  },
}

for id, def in pairs(RELICS) do
  def.id = id
end

local RELIC_ORDER = {
  'whetstone',
  'padding',
  'far_lens',
  'compensation',
  'insurance',
  'bounty',
  'field_rations',
  'navigator',
}

local ACTIVES = {}
local ACTIVE_ORDER = {}

local function register_active(def)
  ACTIVES[def.id] = def
  if def.in_shop ~= false then
    ACTIVE_ORDER[#ACTIVE_ORDER + 1] = def.id
  end
end

for steps = 1, 3 do
  local suffix = steps == 1 and '' or '_' .. steps
  local rarity = steps == 1 and 'common' or (steps == 2 and 'rare' or 'epic')
  local price = steps == 1 and 3 or (steps == 2 and 4 or 6)
  local unit_word = steps == 1 and ' slot' or ' slots'
  register_active({
    id = 'shift_both' .. suffix,
    name = 'SHIFT ' .. steps,
    short = 'RANGE ' .. steps,
    description = 'Between rounds, shift the line up to ' .. steps .. unit_word .. ' either way.',
    icon = 'shift_both' .. suffix,
    rarity = rarity,
    price = price,
    effect = 'shift',
    steps = steps,
  })
end

register_active({
  id = 'medkit',
  name = 'MEDKIT',
  short = 'HEAL 3',
  description = 'Restore 3 HP to an ally. Usable in camp or battle.',
  icon = 'medkit',
  rarity = 'common',
  price = 3,
  effect = 'heal',
  amount = 3,
  shop = true,
})

register_active({
  id = 'core_patch',
  name = 'CORE PATCH',
  short = 'CORE +3',
  description = 'Restore 3 Core. Usable in camp or battle.',
  icon = 'core_patch',
  rarity = 'common',
  price = 4,
  effect = 'core',
  amount = 3,
  shop = true,
})

-- Wave 2 camp gift only (excluded from general shop pool).
register_active({
  id = 'core_cell',
  name = 'CORE CELL',
  short = 'CORE +1',
  description = 'Camp gift: buy for 0G to store in consumables, then use to restore 1 Core.',
  icon = 'core_mend',
  rarity = 'common',
  price = 0,
  effect = 'core',
  amount = 1,
  shop = true,
  in_shop = false,
})

register_active({
  id = 'battle_draught',
  name = 'COMBAT STIM',
  short = 'ATK +2',
  description = 'Grant an ally +2 ATK for this round.',
  icon = 'battle_draught',
  rarity = 'rare',
  price = 4,
  effect = 'attack',
  amount = 2,
})

register_active({
  id = 'guard_plate',
  name = 'GUARD PLATE',
  short = 'DEF +2',
  description = 'Grant an ally +2 DEF for this round.',
  icon = 'guard_plate',
  rarity = 'rare',
  price = 4,
  effect = 'defense',
  amount = 2,
})

register_active({
  id = 'swap_kit',
  name = 'SWAP KIT',
  short = 'SWAP',
  description = 'Move or swap an ally to any slot this round.',
  icon = 'swap_kit',
  rarity = 'common',
  price = 4,
  effect = 'swap',
})

return {
  RELICS = RELICS,
  RELIC_ORDER = RELIC_ORDER,
  ACTIVES = ACTIVES,
  ACTIVE_ORDER = ACTIVE_ORDER,
}
