-- Deterministic 32-bit PRNG and stream hashing for seed reproducibility.
local Rng = {}
Rng.__index = Rng

local MOD = 4294967296

local function mul32(a, b)
  local ah = math.floor(a / 65536)
  local al = a % 65536
  local bh = math.floor(b / 65536)
  local bl = b % 65536
  return (al * bl + ((ah * bl + al * bh) % 65536) * 65536) % MOD
end

-- FNV-ish avalanche hash over a list of integers.
function Rng.hash(...)
  local h = 2166136261
  local args = { ... }
  for i = 1, #args do
    h = (mul32(h, 16777619) + (math.floor(args[i]) % MOD)) % MOD
  end
  h = (h + mul32(h, 3535411333)) % MOD
  h = mul32(h, 2246822519)
  h = (h + 374761393) % MOD
  h = mul32(h, 3266489917)
  h = (h + 668265263) % MOD
  return h
end

function Rng.new(state)
  return setmetatable({ s = math.floor(math.abs(state)) % MOD }, Rng)
end

function Rng:raw()
  self.s = (mul32(self.s, 1664525) + 1013904223) % MOD
  return self.s
end

-- Float in [0, 1) built from the best-mixed high bits.
function Rng:float()
  local x = self:raw()
  return math.floor(x / 256) / 16777216
end

-- Integer in [lo, hi] inclusive (or [1, lo] when hi is omitted).
function Rng:int(lo, hi)
  if hi == nil then
    lo, hi = 1, lo
  end
  return lo + math.floor(self:float() * (hi - lo + 1))
end

function Rng:chance(p)
  return self:float() < p
end

function Rng:pick(list)
  return list[self:int(1, #list)]
end

function Rng:shuffle(list)
  for i = #list, 2, -1 do
    local j = self:int(1, i)
    list[i], list[j] = list[j], list[i]
  end
  return list
end

-- Independent stream per (seed, wave, category) so adding new consumers never perturbs existing ones.
function Rng.stream(seed, wave, category)
  return Rng.new(Rng.hash(seed, wave, category, 0x5bf03635))
end

return Rng
