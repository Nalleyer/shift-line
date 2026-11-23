-- Declarative special unit abilities; unit and encounter definitions select traits by ID.
local definitions = {
  sword_right = {
    icon = 'sword_right',
    family = 'attack',
    offsets = { 1 },
    side_penalty = 1,
    price = 5,
    rarity = 'rare',
  },
  sword_sides = {
    icon = 'sword_sides',
    family = 'attack',
    offsets = { 1, -1 },
    side_penalty = 0,
    price = 8,
    rarity = 'epic',
  },
  guard_1 = {
    icon = 'guard',
    family = 'guard',
    amount = 1,
    price = 5,
    rarity = 'rare',
  },
  guard_2 = {
    icon = 'guard',
    family = 'guard',
    amount = 2,
  },
  heal_1 = {
    icon = 'heal',
    family = 'heal',
    amount = 1,
    price = 5,
    rarity = 'rare',
  },
  heal_2 = {
    icon = 'heal',
    family = 'heal',
    amount = 2,
  },
  move_right = {
    icon = 'arrowR',
    family = 'motion',
    motion = 'right',
    bonus = 2,
  },
  move_left = {
    icon = 'arrowL',
    family = 'motion',
    motion = 'left',
  },
  pike_reach = {
    icon = 'pike_reach',
    family = 'reach',
    offset = -1,
    side_penalty = 1,
  },
  armor_1 = {
    icon = 'armor',
    family = 'armor',
    amount = 1,
    price = 6,
    rarity = 'rare',
  },
  cleave_1 = {
    icon = 'cleave',
    family = 'splash',
    amount = 1,
  },
  cleave_2 = {
    icon = 'cleave',
    family = 'splash',
    amount = 2,
  },
  line_right = {
    icon = 'arrowR',
    family = 'motion',
    motion = 'right',
    scope = 'line',
  },
  boss_formation = {
    icon = 'boss_formation',
    family = 'motion',
    motion = 'formation',
    scope = 'line',
    period = 2,
  },
  boss_tide = {
    icon = 'arrowR',
    family = 'motion',
    motion = 'tide',
    scope = 'line',
    period = 2,
  },
  linked_core = {
    icon = 'link',
    family = 'shared_health',
  },
  taunt = {
    icon = 'taunt',
    family = 'taunt',
    price = 5,
    rarity = 'rare',
  },
  intercept = {
    icon = 'intercept',
    family = 'intercept',
    def_bonus = 2,
    price = 7,
    rarity = 'epic',
  },
  volley = {
    icon = 'volley',
    family = 'attack',
    offsets = { -1, 1 },
    side_penalty = 1,
  },
  drake_breath = {
    icon = 'dragon_breath',
    family = 'attack',
    offsets = { -1, 1 },
    side_penalty = 1,
    bonus = 1,
    piercing = true,
  },
  dragon_breath = {
    icon = 'dragon_breath',
    family = 'attack',
    offsets = { -2, -1, 1, 2 },
    side_penalty = 1,
    bonus = 1,
    piercing = true,
  },
  pierce = {
    icon = 'pierce',
    family = 'pierce',
    price = 6,
    rarity = 'rare',
  },
  momentum = {
    icon = 'momentum',
    family = 'momentum',
    amount = 3,
    def_bonus = 1,
    price = 6,
    rarity = 'rare',
  },
  overcharge = {
    icon = 'charge',
    family = 'charge_aura',
    min_start_charge = 1,
    aura_min = 2,
    high_min = 5,
  },
  core_mend = {
    icon = 'core_mend',
    family = 'core_mend',
    amount = 1,
  },
  apprentice_growth = {
    icon = 'star',
    family = 'growth',
    wins = 5,
    mature_trait = 'sword_sides',
  },
  dragon_growth = {
    icon = 'star',
    family = 'growth',
    wins = 6,
    mature_trait = 'dragon_breath',
  },
  squire_growth = {
    icon = 'star',
    family = 'growth',
    wins = 3,
    mature_trait = 'sword_right',
  },
}

local shop_order = {
  'sword_right',
  'guard_1',
  'heal_1',
  'armor_1',
  'taunt',
  'momentum',
  'pierce',
  'intercept',
  'sword_sides',
}

local shop = {}
for id, trait in pairs(definitions) do
  trait.id = id
end
for _, id in ipairs(shop_order) do
  local t = definitions[id]
  shop[id] = { price = t.price, rarity = t.rarity }
end

return {
  definitions = definitions,
  shop_order = shop_order,
  shop = shop,
}
