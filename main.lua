-- SHIFTLINE — LÖVE entrypoint
if love.filesystem and love.filesystem.setRequirePath then
  love.filesystem.setRequirePath('src/?.lua;src/?/init.lua;?.lua;?/init.lua')
end
package.path = './src/?.lua;./src/?/init.lua;' .. package.path

local App = require('app')
local Audio = require('platform.audio')
local Settings = require('platform.settings')
local Viewport = require('platform.viewport')
local I18n = require('i18n')
local Ui = require('ui')

local function parse_lang_arg(args)
  args = args or {}
  for i = 1, #args do
    if args[i] == '--lang' then
      local lang = args[i + 1]
      if lang == 'zh' or lang == 'en' then
        return lang
      end
    end
  end
  return nil
end

function love.load(args)
  love.keyboard.setKeyRepeat(false)
  Viewport.init()

  Settings.load()
  local lang_override = parse_lang_arg(args)
  if lang_override then
    I18n.set_locale(lang_override)
  end

  Ui.load()
  Audio.load()

  App.register('title', require('screens.title'))
  App.register('settings', require('screens.settings'))
  App.register('map', require('screens.map'))
  App.register('camp', require('screens.camp'))
  App.register('battle', require('screens.battle'))
  App.register('result', require('screens.result'))
  App.register('ending', require('screens.ending'))

  App.go('title')
end

function love.resize()
  Viewport.recompute()
end

function love.update(dt)
  Audio.update()
  App.update(math.min(dt, 1 / 20))
end

function love.draw()
  Viewport.begin_draw()
  App.draw()
  Viewport.end_draw()
end

function love.keypressed(key)
  if key == 'f11' then
    love.window.setFullscreen(not love.window.getFullscreen(), 'desktop')
    Viewport.recompute()
    return
  end
  App.keypressed(key)
end

function love.mousemoved(x, y)
  local cx, cy = Viewport.to_canvas(x, y)
  App.mousemoved(cx, cy)
end

function love.mousepressed(x, y, button)
  local cx, cy = Viewport.to_canvas(x, y)
  App.mousepressed(cx, cy, button)
end

function love.mousereleased(x, y, button)
  local cx, cy = Viewport.to_canvas(x, y)
  App.mousereleased(cx, cy, button)
end
