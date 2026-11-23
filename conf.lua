-- SHIFTLINE — LÖVE configuration
function love.conf(t)
  t.identity = 'shiftline'
  t.version = '11.4'
  t.console = false
  t.window.title = 'SHIFTLINE'
  t.window.width = 384 * 3
  t.window.height = 288 * 3
  t.window.minwidth = 384
  t.window.minheight = 288
  t.window.resizable = true
  t.window.vsync = 1
  t.window.msaa = 0
  t.window.highdpi = false
  t.modules.physics = false
  t.modules.joystick = false
  t.modules.touch = false
  t.modules.video = false
end
