-- Fixed 384x288 canvas with integer scaling and CRT scanlines.
local Theme = require('ui.theme')

local Viewport = {
  canvas = nil,
  scale = Theme.SCALE,
  ox = 0,
  oy = 0,
}

function Viewport.recompute()
  local w, h = love.graphics.getDimensions()
  local s = math.max(1, math.floor(math.min(w / Theme.W, h / Theme.H)))
  Viewport.scale = s
  Viewport.ox = math.floor((w - Theme.W * s) / 2)
  Viewport.oy = math.floor((h - Theme.H * s) / 2)
end

function Viewport.init()
  love.graphics.setDefaultFilter('nearest', 'nearest')
  Viewport.canvas = love.graphics.newCanvas(Theme.W, Theme.H)
  Viewport.canvas:setFilter('nearest', 'nearest')
  Viewport.recompute()
end

function Viewport.to_canvas(x, y)
  return (x - Viewport.ox) / Viewport.scale, (y - Viewport.oy) / Viewport.scale
end

function Viewport.begin_draw()
  love.graphics.setCanvas(Viewport.canvas)
  love.graphics.clear(Theme.C.ink)
  love.graphics.setColor(1, 1, 1, 1)
end

function Viewport.draw_scanlines(alpha)
  local scale = Viewport.scale
  if scale < 2 then
    return
  end
  love.graphics.setColor(0, 0, 0, alpha or 0.12)
  local bottom = Viewport.oy + Theme.H * scale - 1
  for y = Viewport.oy + scale - 1, bottom, scale do
    love.graphics.rectangle('fill', Viewport.ox, y, Theme.W * scale, 1)
  end
  love.graphics.setColor(1, 1, 1, 1)
end

function Viewport.end_draw()
  love.graphics.setCanvas()
  love.graphics.clear(0, 0, 0, 1)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(Viewport.canvas, Viewport.ox, Viewport.oy, 0, Viewport.scale, Viewport.scale)
  Viewport.draw_scanlines(0.10)
end

return Viewport
