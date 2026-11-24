-- Wave templates, gauntlet forks, act mini-bosses, and final bosses across 3 Acts (15 waves).
local MINI_BOSSES_1 = {
  {
    pattern = 'g.b...',
    name = 'GATEKEEPER',
    boss = true,
    mini_boss = true,
    boss_id = 'gatekeeper',
    boss_hp = 15,
    atk = { g = 2, b = 2 },
    def = { b = 1 },
    boss_alt_pattern = '.g.b..',
    boss_period = 2,
    boss_motion = 'formation',
  },
  {
    pattern = 'r..x..',
    name = 'TWIN FANG',
    boss = true,
    mini_boss = true,
    boss_id = 'twin_fang',
    boss_hp = 12,
    atk = { r = 2, x = 2 },
    def = { x = 1 },
    brk = { r = 1 },
    boss_period = 3,
    boss_motion = 'tide',
  },
}

local MINI_BOSSES_2 = {
  {
    pattern = 's.b.r.',
    name = 'BASTION',
    boss = true,
    mini_boss = true,
    boss_id = 'bastion',
    boss_hp = 32,
    atk = { s = 2, b = 4, r = 3 },
    def = { s = 1, b = 1 },
    unit_traits = { s = { 'guard_1' } },
    boss_alt_pattern = '.sb..r',
    boss_period = 2,
    boss_motion = 'formation',
  },
  {
    pattern = 'l.x.s.',
    name = 'IRON CROSS',
    boss = true,
    mini_boss = true,
    boss_id = 'iron_cross',
    boss_hp = 35,
    atk = { l = 3, x = 2, s = 2 },
    def = { s = 1 },
    unit_traits = { x = { 'cleave_1' } },
    boss_period = 2,
    boss_motion = 'tide',
  },
}

local BOSSES = {
  {
    pattern = '.aca..',
    name = 'SHIFTING CORE',
    boss = true,
    boss_id = 'shifting_core',
    boss_hp = 54,
    atk = { a = 4, c = 5 },
    def = { a = 1, c = 1 },
    boss_alt_pattern = 'a..c.a',
    boss_period = 2,
    boss_motion = 'formation',
  },
  {
    pattern = 'a.c.a.',
    name = 'IRON PHALANX',
    boss = true,
    boss_id = 'iron_phalanx',
    boss_hp = 56,
    atk = { a = 4, c = 5 },
    def = { a = 1, c = 1 },
    unit_traits = { a = { 'guard_1' } },
    boss_alt_pattern = '.aca..',
    boss_period = 3,
    boss_motion = 'formation',
  },
  {
    pattern = 'r.c.r.',
    name = 'TIDE ENGINE',
    boss = true,
    boss_id = 'tide_engine',
    boss_hp = 56,
    atk = { r = 4, c = 5 },
    def = { r = 1, c = 1 },
    boss_period = 2,
    boss_motion = 'tide',
  },
}

local FORKS = {
  [3] = {
    {
      pattern = 'x.r.g.',
      name = 'KILL SQUAD',
      hp = { g = 4, r = 4, x = 4 },
      atk = { r = 3, x = 2 },
      draft = true,
      draft_gold = 6,
      elite = true,
    },
    {
      pattern = '.s.rl.',
      name = 'LANCE PATROL',
      hp = { r = 4, s = 4, l = 4 },
      atk = { r = 3, l = 2 },
      draft = true,
      draft_gold = 6,
      elite = true,
    },
  },
  [8] = {
    {
      pattern = 'b.g.r.',
      name = 'ARMORED RAID',
      hp = { g = 4, r = 5, b = 9 },
      atk = { r = 3, b = 4 },
      draft = true,
      draft_gold = 7,
      elite = true,
    },
    {
      pattern = 'l.x.rs',
      name = 'CROSSFIRE PACK',
      hp = { r = 5, x = 5, l = 4, s = 4 },
      atk = { r = 3, l = 3, x = 2 },
      draft = true,
      draft_gold = 7,
      elite = true,
    },
  },
  [13] = {
    {
      pattern = 'b.xr.l',
      name = 'BREACH SQUAD',
      hp = { r = 6, x = 6, b = 10, l = 6 },
      atk = { r = 4, x = 3, l = 3, b = 4 },
      draft = true,
      draft_gold = 9,
      elite = true,
    },
    {
      pattern = 'sb.x.l',
      name = 'IRON BASTION',
      hp = { b = 11, x = 6, s = 5, l = 6 },
      atk = { b = 4, x = 3, l = 3 },
      unit_traits = { x = { 'cleave_2' }, s = { 'guard_1' } },
      draft = true,
      draft_gold = 9,
      elite = true,
    },
  },
}

local WAVES = {
  -- Act 1 (Waves 1-5)
  { { pattern = 'g...g.', name = 'FIRST CONTACT' } },
  { { pattern = '.g..g.', name = 'SCOUT PAIR' }, { pattern = '.g.g..', name = 'CLOSE PAIR' } },
  { { pattern = '.g.r..', name = 'FLANK CROSS' }, { pattern = 'g..g..', name = 'TWIN VANGUARD' } },
  {
    { pattern = 'g.x...', name = 'CLEAVER SCOUT', hp = { g = 3, x = 4 } },
    { pattern = '.s.g..', name = 'SHIELDED GRUNT', hp = { g = 3, s = 4 } },
  },
  MINI_BOSSES_1,

  -- Act 2 (Waves 6-10)
  {
    { pattern = 'g.x.r.', name = 'CLEAVER LINE', hp = { g = 4, r = 4, x = 5 } },
    { pattern = '.s.gr.', name = 'SENTINEL LINE', hp = { g = 4, r = 4, s = 4 }, atk = { r = 3 } },
  },
  {
    { pattern = 'g.xr..', name = 'VISE PRESSURE', hp = { g = 4, r = 5, x = 5 }, atk = { r = 3, x = 2 } },
    { pattern = '.gl.s.', name = 'PIKE WALL', hp = { g = 4, l = 4, s = 5 }, atk = { l = 3 } },
  },
  {
    { pattern = 'g.x.rg', name = 'CROSS CUT', hp = { g = 4, r = 5, x = 5 }, atk = { r = 3, x = 3 } },
    { pattern = 'ls..rg', name = 'LANCE FLANK', hp = { g = 4, r = 5, l = 5, s = 4 }, atk = { r = 3, l = 3 } },
  },
  {
    {
      pattern = 'g.xr.l',
      name = 'ROLLING ELITE',
      hp = { g = 4, r = 5, x = 6, l = 5 },
      atk = { r = 3, x = 3, l = 3 },
      motion = 'right',
      elite = true,
    },
  },
  MINI_BOSSES_2,

  -- Act 3 (Waves 11-15)
  {
    { pattern = 'b.s.r.', name = 'HEAVY LINE', hp = { r = 6, s = 6, b = 11 }, atk = { r = 4, b = 4 } },
    { pattern = 'l.b.x.', name = 'CRUSHING AXE', hp = { l = 6, x = 6, b = 11 }, atk = { l = 4, x = 3, b = 4 } },
  },
  {
    {
      pattern = 'b.x.rg',
      name = 'IRON CRUSH',
      hp = { g = 5, r = 6, x = 7, b = 11 },
      atk = { r = 4, x = 3, b = 4 },
      unit_traits = { x = { 'cleave_2' } },
    },
    {
      pattern = 'xs..rl',
      name = 'SIEGE BREAKER',
      hp = { r = 6, x = 7, s = 6, l = 6 },
      atk = { r = 4, x = 3, l = 3 },
      unit_traits = { x = { 'cleave_2' } },
    },
  },
  {
    {
      pattern = 'b.xr.g',
      name = 'DRIFTING TANK',
      hp = { g = 5, r = 6, x = 7, b = 12 },
      atk = { r = 4, x = 3, b = 4 },
      motion = 'right',
      elite = true,
    },
  },
  {
    {
      pattern = 'b.rx.l',
      name = 'VANGUARD WALL',
      hp = { r = 6, x = 7, b = 12, l = 6 },
      atk = { r = 4, x = 3, l = 4, b = 4 },
      unit_traits = { x = { 'cleave_2' } },
    },
    {
      pattern = 'sb.r.g',
      name = 'ROYAL GUARD',
      hp = { g = 5, r = 6, b = 12, s = 6 },
      atk = { r = 4, s = 2, b = 4 },
    },
  },
  BOSSES,
}

return {
  MINI_BOSSES_1 = MINI_BOSSES_1,
  MINI_BOSSES_2 = MINI_BOSSES_2,
  BOSSES = BOSSES,
  FORKS = FORKS,
  WAVES = WAVES,
}
