-- Global application state, run lifecycle helpers, and screen router.
local Run = require('core.run')
local Ui = require('ui')

local App = {
  VERSION = 'v1.0',
  seed = 7,
  fixed_seed = false,
  seed_text = '7',
  run = nil,
  mouse = { x = -100, y = -100, down = false },
  time = 0,
  toast = nil,
  screens = {},
  current = nil,
  current_name = nil,
}

function App.register(name, mod)
  mod.name = name
  App.screens[name] = mod
  return mod
end

function App.go(name, ...)
  local s = App.screens[name]
  assert(s, 'unknown screen: ' .. tostring(name))
  if App.current and App.current.leave then
    App.current:leave()
  end
  App.current = s
  App.current_name = name
  App.toast = nil
  App.mouse.x, App.mouse.y = -100, -100
  Ui.inspector.close()
  Ui.begin_frame(App.mouse)
  if s.enter then
    s:enter(...)
  end
end

function App.show_toast(message)
  App.toast = { message = message, remaining = 1.8 }
end

function App.ui_context()
  local ctx = {
    run = App.run,
    mouse = App.mouse,
    show_loadout = App.run ~= nil and App.current_name ~= 'title',
    allow_inspect = true,
    inspect_preview_only = false,
    on_use_item = function(index)
      if App.current and App.current.use_item then
        App.current:use_item(index)
      end
    end,
  }
  if App.current and App.current.ui_context then
    for k, v in pairs(App.current:ui_context()) do
      ctx[k] = v
    end
  end
  return ctx
end

function App.draw_topbar(overrides)
  local ctx = App.ui_context()
  if overrides then
    for k, v in pairs(overrides) do
      ctx[k] = v
    end
  end
  local run = ctx.run
  if not run then
    return
  end
  local core = (overrides and overrides.core ~= nil) and overrides.core or run.core
  local core_max = (overrides and overrides.core_max ~= nil) and overrides.core_max or run.core_max
  Ui.hud.topbar(core, core_max, ctx)
end

function App.update(dt)
  App.time = App.time + dt
  if App.toast then
    App.toast.remaining = App.toast.remaining - dt
    if App.toast.remaining <= 0 then
      App.toast = nil
    end
  end
  if App.current and App.current.update then
    App.current:update(dt)
  end
end

function App.draw()
  Ui.begin_frame(App.mouse)
  if App.current and App.current.draw then
    App.current:draw()
  end
  Ui.draw_overlay(App.ui_context())
  if App.toast then
    Ui.draw_toast(App.toast.message)
  end
end

function App.keypressed(key, isrepeat)
  if Ui.inspector.keypressed(key) then
    return
  end
  if App.current and App.current.keypressed then
    App.current:keypressed(key, isrepeat)
  end
end

function App.mousepressed(x, y, button)
  App.mouse.down = true
  local ctx = App.ui_context()
  if Ui.inspector.mousepressed(x, y, button, ctx) then
    return
  end
  if Ui.hud.mousepressed(x, y, button, ctx) then
    return
  end
  if App.current and App.current.mousepressed then
    App.current:mousepressed(x, y, button)
  end
end

function App.mousereleased(x, y, button)
  App.mouse.down = false
  if App.current and App.current.mousereleased then
    App.current:mousereleased(x, y, button)
  end
end

function App.mousemoved(x, y)
  App.mouse.x, App.mouse.y = x, y
  if App.current and App.current.mousemoved then
    App.current:mousemoved(x, y)
  end
end

function App.start_run(seed)
  App.seed = seed
  App.run = Run.new(seed)
  App.go('map')
end

function App.new_seed()
  return love.math.random(0, 999999)
end

function App.chosen_seed()
  if App.fixed_seed then
    return tonumber(App.seed_text) or 7
  end
  return App.new_seed()
end

return App
