-- Gameplay-wide numeric and structural constants.
local Constants = {
  SLOTS = 6,
  CORE_MAX = 8,
  CHARGE_MAX = 6,
  BATTLE_CHARGE_CAP = 3,
  MAX_ROUNDS = 18,
  MAX_TRAITS = 5,
  INVENTORY_MAX = 3,

  ACT_SIZE = 5,
  ACTS = 3,
  GROWTH_MAX_WAVE = 7,

  UPGRADE_CAPS = { atk = 4, hp = 12, def = 2 },
  HP_UPGRADE_STEP = 3,

  START_GOLD = 5,
  START_SLOT = 3,
  START_UNIT = 'S',
  START_INVENTORY = { 'shift_both', 'medkit' },

  ENEMY_BOUNTIES = {
    g = 2,
    r = 3,
    x = 3,
    s = 3,
    l = 3,
    b = 4,
    mini_boss = 6,
    boss = 12,
  },

  RARITY_WEIGHTS = {
    common = 58,
    rare = 28,
    epic = 11,
    legendary = 3,
  },
  RARITY_ORDER = { 'common', 'rare', 'epic', 'legendary' },

  FUSE_MAX = 1,
  FUSE_BONUS_GOLD = 3,
  FUSE_MIN_CORE = 3,
}

return Constants
