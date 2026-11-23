-- Battle visual effects: smooth wrap-around repositioning, particles, streaks, bolts, and floating numbers.
local Util = require('core.util')
local Ui = require('ui')

local T = Ui.theme
local C = Ui.C
local Text = Ui.text

local Fx = {}
Fx.__index = Fx

function Fx.new()
  return setmetatable({
    numbers = {},
    shards = {},
    streaks = {},
    breach_ghosts = {},
    lane_flashes = {},
    charge_bolts = {},
    heal_flash = {},
    hit_flash = { player = {}, enemy = {} },
    motion = nil,
    actor = nil,
    shake = 0,
    flash = 0,
    heart_flash = 0,
    charge_flash = 0,
    core_delta = nil,
    core_delta_t = 0,
    charge_delta = nil,
    charge_delta_t = 0,
  }, Fx)
end

function Fx.actor_key(unit, col)
  return unit.slot and ('ally' .. unit.slot) or unit.uid or (unit.kind .. col)
end

function Fx:begin_reposition(old_line, old_enemies, new_line, new_enemies, delta, side)
  local prior = self.motion
  local motion = { t = 0, duration = 0.3, player = {}, enemy = {} }

  for _, team in ipairs({ 'player', 'enemy' }) do
    local old = team == 'player' and old_line or old_enemies
    local new = team == 'player' and new_line or new_enemies
    local origins = {}
    for col, u in pairs(old or {}) do
      local key = Fx.actor_key(u, col)
      local start = T.col_x(col)
      local moving = prior and prior[team][key]
      if moving then
        local e = 1 - (1 - math.min(1, prior.t / prior.duration)) ^ 2
        start = moving.from + (moving.to - moving.from) * e
        start = start + math.floor((T.col_x(col) - start) / (6 * T.COL_STEP) + 0.5) * 6 * T.COL_STEP
      end
      origins[key] = { x = start, col = col }
    end

    for col, u in pairs(new or {}) do
      local key = Fx.actor_key(u, col)
      local origin = origins[key]
      if origin then
        local target = T.col_x(col)
        if delta and team == side and ((origin.col + delta - 1) % 6) + 1 == col then
          target = T.col_x(origin.col) + delta * T.COL_STEP
        end
        if math.abs(origin.x - target) > 0.01 then
          motion[team][key] = { from = origin.x, to = target }
        end
      end
    end
  end

  self.motion = motion
  return Util.deep_copy(new_line), Util.deep_copy(new_enemies)
end

function Fx:add_number(cx, cy, text, col, scale)
  self.numbers[#self.numbers + 1] = {
    x = cx,
    y = cy,
    text = text,
    col = col or C.white,
    t = 0,
    life = 0.8,
    scale = scale or 2,
    vy = -26,
  }
end

function Fx:add_shards(cx, cy, col, n)
  for i = 1, n do
    local a = (i / n) * math.pi * 2 + love.math.random() * 0.4
    local sp = 32 + love.math.random() * 46
    self.shards[#self.shards + 1] = {
      x = cx,
      y = cy,
      vx = math.cos(a) * sp,
      vy = math.sin(a) * sp - 24,
      t = 0,
      life = 0.5 + love.math.random() * 0.25,
      size = love.math.random() < 0.5 and 2 or 3,
      col = col,
    }
  end
end

function Fx:add_streak(col, amount)
  self.streaks[#self.streaks + 1] = { col = col, amount = amount, t = 0, life = 0.6 }
end

function Fx:add_breach_ghost(col, kind, escape)
  self.breach_ghosts[#self.breach_ghosts + 1] = {
    col = col,
    kind = kind,
    escape = escape,
    t = 0,
    life = 0.48,
  }
end

function Fx:add_charge_bolts(sx, sy)
  for j = 1, 3 do
    self.charge_bolts[#self.charge_bolts + 1] = {
      x0 = sx + (j - 2) * 5,
      y0 = sy,
      x1 = 149,
      y1 = 12,
      arc = (sx < 149 and -1 or 1) * (14 + j * 4),
      t = -(j - 1) * 0.045,
      life = 0.34,
      arrived = false,
    }
  end
end

function Fx:update(dt)
  if self.motion then
    self.motion.t = self.motion.t + dt
    if self.motion.t >= self.motion.duration then
      self.motion = nil
    end
  end

  if self.actor then
    self.actor.t = self.actor.t + dt
    if self.actor.t >= 0.32 then
      self.actor = nil
    end
  end

  for k, v in pairs(self.heal_flash) do
    self.heal_flash[k] = math.max(0, v - dt)
  end

  for i = #self.numbers, 1, -1 do
    local n = self.numbers[i]
    n.t = n.t + dt
    n.y = n.y + n.vy * dt
    n.vy = n.vy + 48 * dt
    if n.t >= n.life then
      table.remove(self.numbers, i)
    end
  end

  for i = #self.shards, 1, -1 do
    local s = self.shards[i]
    s.t = s.t + dt
    s.x = s.x + s.vx * dt
    s.y = s.y + s.vy * dt
    s.vy = s.vy + 220 * dt
    if s.t >= s.life then
      table.remove(self.shards, i)
    end
  end

  for i = #self.streaks, 1, -1 do
    local s = self.streaks[i]
    s.t = s.t + dt
    if s.t >= s.life then
      table.remove(self.streaks, i)
    end
  end

  for i = #self.breach_ghosts, 1, -1 do
    local g = self.breach_ghosts[i]
    g.t = g.t + dt
    if g.t >= g.life then
      table.remove(self.breach_ghosts, i)
    end
  end

  for col, lf in pairs(self.lane_flashes) do
    lf.t = lf.t + dt
    if lf.t >= lf.life then
      self.lane_flashes[col] = nil
    end
  end

  for i = #self.charge_bolts, 1, -1 do
    local b = self.charge_bolts[i]
    b.t = b.t + dt
    if b.t >= b.life and not b.arrived then
      b.arrived = true
      self.charge_flash = 1
      self.charge_delta_t = 0
      self:add_shards(b.x1, b.y1, C.blue, 4)
    end
    if b.t >= b.life + 0.08 then
      table.remove(self.charge_bolts, i)
    end
  end

  for _, team in pairs(self.hit_flash) do
    for k, v in pairs(team) do
      local nv = math.max(0, v - dt)
      team[k] = nv == 0 and nil or nv
    end
  end

  self.shake = math.max(0, self.shake - dt * 26)
  self.flash = math.max(0, self.flash - dt * 2.4)
  self.heart_flash = math.max(0, self.heart_flash - dt * 1.8)
  self.charge_flash = math.max(0, self.charge_flash - dt * 1.4)
  self.core_delta_t = self.core_delta_t + dt
  if self.core_delta and self.core_delta_t > 1.1 then
    self.core_delta = nil
  end
  self.charge_delta_t = self.charge_delta_t + dt
  if self.charge_delta and self.charge_delta_t > 1.5 then
    self.charge_delta = nil
  end
end

function Fx:draw_world()
  for _, s in ipairs(self.streaks) do
    local k = s.t / s.life
    local x = T.col_cx(s.col)
    local y0 = T.ENEMY_Y + 24
    local y1 = T.PLAYER_Y + T.PANEL_H + 14
    local head = y0 + (y1 - y0) * math.min(1, k * 1.9)
    local tail = math.max(y0, head - 46)
    local fade = 1 - k
    Ui.rect(x - 10, tail, 20, head - tail, C.red, fade * 0.16)
    Ui.rect(x - 5, tail, 10, head - tail, C.red, fade * 0.35)
    Ui.rect(x - 2, tail, 4, head - tail, C.amber, fade * 0.88)
    Ui.rect(x - 1, math.max(tail, head - 10), 2, math.min(10, head - tail), C.white, fade * 0.9)
  end

  for _, g in ipairs(self.breach_ghosts) do
    local k = g.t / g.life
    local cx = T.col_cx(g.col)
    local y_start = T.ENEMY_Y + 25
    local y_end = g.escape and (T.PLAYER_Y + T.PANEL_H + 22) or (T.PLAYER_Y + 34)
    local ease = 1 - (1 - k) * (1 - k)
    local cy = y_start + (y_end - y_start) * ease
    local alpha = math.max(0, 1 - k * k)
    if g.kind then
      Ui.unit(g.kind, cx, cy - 12, 2, C.red, alpha * 0.25)
      Ui.unit(g.kind, cx, cy - 6, 2, C.amber, alpha * 0.45)
      Ui.unit(g.kind, cx, cy, 2, C.red, alpha * 0.9)
    end
  end

  for _, s in ipairs(self.shards) do
    local a = 1 - s.t / s.life
    Ui.rect(s.x, s.y, s.size, s.size, s.col, a)
  end

  for _, n in ipairs(self.numbers) do
    local k = n.t / n.life
    local pop = 1 + 0.35 * math.max(0, 1 - n.t / 0.1)
    local a = 1 - k * k
    Text.text_outlined(n.text, n.x, n.y, {
      color = n.col,
      scale = n.scale * pop,
      align = 'center',
      alpha = a,
    })
  end
end

function Fx:draw_topbar_overlay(charge, charge_max)
  if self.charge_flash > 0 then
    local f = self.charge_flash
    local glow = Ui.mix(C.blue, C.white, f * 0.6)
    Ui.rect(141, 2, 32, 17, C.blue, 0.28 * f)
    Ui.frame(141, 2, 32, 17, glow, 0.9 * f)
    Ui.icon_text('charge', charge .. '/' .. charge_max, 145, 8, { color = glow })
  end

  if self.core_delta then
    local a = math.max(0, 1 - self.core_delta_t / 1.1)
    Text.text(string.format('%+d', self.core_delta), 101, 8, {
      color = self.core_delta > 0 and C.green or C.red,
      align = 'right',
      alpha = a,
      bitmap = true,
    })
  end

  if self.charge_delta then
    local a = math.max(0, 1 - self.charge_delta_t / 1.5)
    local pop = 1 + 0.35 * math.max(0, 1 - self.charge_delta_t / 0.18)
    local rise = math.min(4, self.charge_delta_t * 6)
    Text.text_outlined('+' .. self.charge_delta, 157, 21 - rise * 0.4, {
      color = Ui.mix(C.blue, C.white, a * 0.4),
      scale = pop > 1.15 and 2 or 1,
      align = 'center',
      alpha = a,
      bitmap = true,
    })
  end

  for _, b in ipairs(self.charge_bolts) do
    if b.t >= 0 and b.t < b.life then
      local k = b.t / b.life
      for step = 0, 4 do
        local sk = math.max(0, k - step * 0.055)
        local inv = 1 - sk
        local mx = (b.x0 + b.x1) * 0.5 + b.arc
        local my = (b.y0 + b.y1) * 0.5 - 12
        local px = inv * inv * b.x0 + 2 * inv * sk * mx + sk * sk * b.x1
        local py = inv * inv * b.y0 + 2 * inv * sk * my + sk * sk * b.y1
        local sz = step == 0 and 4 or (step <= 2 and 3 or 2)
        local col = step == 0 and C.white or C.blue
        Ui.rect(px - sz / 2, py - sz / 2, sz, sz, col, 1 - step * 0.18)
      end
    end
  end
end

return Fx
