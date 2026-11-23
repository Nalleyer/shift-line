-- Shared battle-style A/D alignment + Space strike menu for Title and Settings.
local Audio = require('platform.audio')
local Theme = require('ui.theme')
local Draw = require('ui.draw')
local Text = require('ui.text')
local Assets = require('ui.assets')

local T = Theme.C and Theme or Theme
local C = Theme.C

local DuelMenu = {}
DuelMenu.__index = DuelMenu

local DEFAULT_COL_X = { 108, 192, 276 }

function DuelMenu.new(opts)
  opts = opts or {}
  local col_x = opts.col_x or DEFAULT_COL_X
  local m = setmetatable({
    col_x = col_x,
    y_enemy = opts.y_enemy or 152,
    y_player = opts.y_player or 202,
    col = opts.default_col or 2,
    hover = nil,
    anim = nil,
    strike = nil,
    on_select = opts.on_select,
  }, DuelMenu)
  return m
end

function DuelMenu:target_rect(i)
  local cx = self.col_x[i]
  return { x = cx - 32, y = self.y_enemy - 14, w = 64, h = 42 }
end

function DuelMenu:shift_left_rect()
  return { x = self.col_x[1] - 66, y = self.y_player - 6, w = 34, h = 16 }
end

function DuelMenu:shift_right_rect()
  return { x = self.col_x[#self.col_x] + 32, y = self.y_player - 6, w = 34, h = 16 }
end

function DuelMenu:player_x()
  if self.anim then
    local p = math.min(1, self.anim.t / self.anim.duration)
    local e = 1 - (1 - p) ^ 2
    local x = self.anim.from_x + (self.anim.to_x - self.anim.from_x) * e
    local span = (self.col_x[#self.col_x] - self.col_x[1]) + (self.col_x[2] - self.col_x[1])
    local min_x = self.col_x[1] - (self.col_x[2] - self.col_x[1]) * 0.5
    local max_x = self.col_x[#self.col_x] + (self.col_x[2] - self.col_x[1]) * 0.5
    if x < min_x then
      x = x + span
    elseif x > max_x then
      x = x - span
    end
    return x
  end
  return self.col_x[self.col]
end

function DuelMenu:shift(dir, count)
  if self.strike then
    return
  end
  count = count or #self.col_x
  local start_x = self:player_x()
  local next_col = ((self.col - 1 + dir) % count) + 1
  local target_x = self.col_x[next_col]
  local step = self.col_x[2] - self.col_x[1]
  local span = count * step
  if dir < 0 and start_x < target_x then
    start_x = start_x + span
  elseif dir > 0 and start_x > target_x then
    start_x = start_x - span
  end
  self.col = next_col
  self.anim = { t = 0, duration = 0.14, from_x = start_x, to_x = target_x }
  Audio.play('ui_move', 0.8)
end

function DuelMenu:trigger(targets)
  if self.strike then
    return
  end
  local target = targets[self.col]
  if not target then
    return
  end
  self.anim = nil
  self.strike = { t = 0, duration = 0.09, target = target }
  Audio.play(target.sound or 'hit', 0.75)
end

function DuelMenu:update(dt, mouse, targets)
  if self.anim then
    self.anim.t = self.anim.t + dt
    if self.anim.t >= self.anim.duration then
      self.anim = nil
    end
  end

  if self.strike then
    self.strike.t = self.strike.t + dt
    if self.strike.t >= self.strike.duration then
      local target = self.strike.target
      self.strike = nil
      if self.on_select then
        self.on_select(target)
      end
    end
    return
  end

  local hovered = nil
  for i = 1, #targets do
    if Draw.hit(self:target_rect(i), mouse.x, mouse.y) then
      hovered = i
      break
    end
  end
  if not hovered then
    if Draw.hit(self:shift_left_rect(), mouse.x, mouse.y) then
      hovered = 'shift_left'
    elseif Draw.hit(self:shift_right_rect(), mouse.x, mouse.y) then
      hovered = 'shift_right'
    end
  end
  if type(hovered) == 'number' and hovered ~= self.hover then
    Audio.play('ui_move', 0.45)
  end
  self.hover = hovered
end

function DuelMenu:keypressed(key, targets)
  if key == 'a' or key == 'left' then
    self:shift(-1, #targets)
    return true
  elseif key == 'd' or key == 'right' then
    self:shift(1, #targets)
    return true
  elseif key == 'space' or key == 'return' or key == 'kpenter' then
    self:trigger(targets)
    return true
  end
  return false
end

function DuelMenu:mousepressed(x, y, targets)
  if Draw.hit(self:shift_left_rect(), x, y) then
    self:shift(-1, #targets)
    return true
  end
  if Draw.hit(self:shift_right_rect(), x, y) then
    self:shift(1, #targets)
    return true
  end
  for i = 1, #targets do
    if Draw.hit(self:target_rect(i), x, y) then
      self.col = i
      self.anim = nil
      self:trigger(targets)
      return true
    end
  end
  return false
end

function DuelMenu:draw(targets, t, mouse)
  local foot_y = self.y_player + 11
  local px = self:player_x()
  local lunge = 0
  if self.strike then
    local p = self.strike.t / self.strike.duration
    lunge = math.sin(p * math.pi) * 14
  end

  -- Alignment sightline between Swordsman and aligned target
  local acx = self.col_x[self.col]
  Draw.vline(acx, self.y_enemy + 24, self.y_player - self.y_enemy - 34, C.amber, 0.32)

  -- Top row: icon-only targets (no button frames)
  for i, target in ipairs(targets) do
    local cx = self.col_x[i]
    local aligned = (i == self.col)
    local hot = (self.hover == i)
    local bob = aligned and math.sin(t * 4) * 1.5 or 0
    local icon_col = aligned and (target.color or C.amber) or (hot and C.white or (target.active and C.amber or C.paper))
    local label_col = aligned and C.white or (hot and C.paper or (target.active and C.amber or C.dim))

    if aligned then
      Draw.icon('arrowD', cx, self.y_enemy - 16 + bob, 1, C.amber, 0.8)
    end
    Draw.icon(target.icon, cx, self.y_enemy + bob, 2, icon_col, (aligned or hot or target.active) and 1 or 0.72)
    Text.text(target.label, cx, self.y_enemy + 12, {
      color = label_col,
      align = 'center',
    })
    if target.active then
      Draw.rect(cx - 2, self.y_enemy + 12 + (Assets.cjk and 13 or 9), 4, 2, C.amber)
    end
  end

  -- Bottom row: player Swordsman lane + clickable A/D shift buttons
  for i = 1, #targets do
    local cx = self.col_x[i]
    Draw.slot_marker(cx, foot_y, i ~= self.col, i == self.col and C.amber or C.line)
  end

  Draw.unit_shadow(px, foot_y, 16, 0.45)
  Draw.unit('S', px, self.y_player - lunge, 2, C.white)

  Draw.button_rect(self:shift_left_rect(), '< A', { hover = self.hover == 'shift_left' }, mouse)
  Draw.button_rect(self:shift_right_rect(), 'D >', { hover = self.hover == 'shift_right' }, mouse)
end

return DuelMenu
