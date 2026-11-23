-- Pure table, slot, and relic helpers.
local Constants = require('data.constants')

local Util = {}

function Util.deep_copy(v)
  if type(v) ~= 'table' then
    return v
  end
  local out = {}
  for k, x in pairs(v) do
    out[k] = Util.deep_copy(x)
  end
  return out
end

function Util.contains(list, value)
  if not list then
    return false
  end
  for _, v in ipairs(list) do
    if v == value then
      return true
    end
  end
  return false
end

function Util.valid_slot(n)
  return type(n) == 'number' and n == math.floor(n) and n >= 1 and n <= Constants.SLOTS
end

function Util.count_slots(t)
  local n = 0
  for i = 1, Constants.SLOTS do
    if t and t[i] then
      n = n + 1
    end
  end
  return n
end

function Util.shift_line(t, delta)
  local out = {}
  local slots = Constants.SLOTS
  for i = 1, slots do
    out[((i + delta - 1) % slots) + 1] = t[i]
  end
  return out
end

function Util.relic_count(relics, id)
  local n = 0
  for _, v in ipairs(relics or {}) do
    if v == id then
      n = n + 1
    end
  end
  return n
end

function Util.has_relic(relics, id)
  return Util.relic_count(relics, id) > 0
end

return Util
