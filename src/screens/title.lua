-- Title screen: game logo, battle-style A/D Swordsman menu, language toggle, and fixed seed entry.
local App = require('app')
local Audio = require('platform.audio')
local I18n = require('i18n')
local Ui = require('ui')

local T = Ui.theme
local C = Ui.C
local Text = Ui.text

local Title = {
  t = 0,
  editing = false,
  blink = 0,
  menu = nil,
}

local CHECK = { x = 14, y = 256 }

local function build_targets()
  return {
    { id = 'settings', label = I18n.t('title.settings'), icon = 'gear', color = C.blue, sound = 'ui_select' },
    { id = 'start', label = I18n.t('title.start'), icon = 'attack', color = C.amber, sound = 'fight' },
    { id = 'quit', label = I18n.t('title.quit'), icon = 'x', color = C.red, sound = 'ui_move' },
  }
end

function Title:activate(id)
  if id == 'start' then
    App.start_run(App.chosen_seed())
  elseif id == 'settings' then
    App.go('settings')
  elseif id == 'quit' then
    love.event.quit()
  end
end

function Title:enter()
  self.t = 0
  self.editing = false
  self.blink = 0
  self.menu = Ui.duel_menu.new({
    y_enemy = 152,
    y_player = 204,
    default_col = 2,
    on_select = function(target)
      self:activate(target.id)
    end,
  })
  Audio.music('title')
end

function Title:check_box()
  return { x = CHECK.x, y = CHECK.y, w = 11, h = 11 }
end

function Title:seed_hit(x, y)
  return x >= 14 and x <= 200 and y >= CHECK.y - 4 and y <= CHECK.y + 13
end

function Title:toggle_fixed()
  App.fixed_seed = not App.fixed_seed
  if App.fixed_seed and App.seed_text == '' then
    App.seed_text = '7'
  end
  Audio.play(App.fixed_seed and 'ui_select' or 'ui_move', 0.7)
end

function Title:update(dt)
  self.t = self.t + dt
  self.blink = self.blink + dt
  if self.menu then
    self.menu:update(dt, App.mouse, build_targets())
  end
end

function Title:keypressed(key)
  if self.editing then
    if key == 'backspace' then
      App.seed_text = App.seed_text:sub(1, -2)
      Audio.play('tick', 0.6)
    elseif key == 'return' or key == 'kpenter' then
      self.editing = false
      Audio.play('ui_select')
    elseif key == 'escape' then
      self.editing = false
      Audio.play('ui_move')
    elseif #key == 1 and key:match('%d') and #App.seed_text < 6 then
      if App.seed_text == '0' then
        App.seed_text = ''
      end
      App.seed_text = App.seed_text .. key
      Audio.play('tick', 0.7)
    end
    return
  end

  if self.menu and self.menu:keypressed(key, build_targets()) then
    return
  end

  if key == 'escape' then
    love.event.quit()
  end
end

function Title:mousepressed(x, y, button)
  if button ~= 1 then
    return
  end
  if self:seed_hit(x, y) then
    local box = self:check_box()
    if x >= box.x and x <= box.x + box.w + 70 then
      self:toggle_fixed()
    elseif App.fixed_seed then
      self.editing = true
      Audio.play('ui_select', 0.7)
    end
    return
  end
  if self.menu then
    self.menu:mousepressed(x, y, build_targets())
  end
end

local function draw_logo(t)
  local cx = T.W / 2
  Text.text('SHIFTLINE', cx + 3, 75, { scale = 5, align = 'center', color = C.red_dk, bitmap = true })
  Text.text('SHIFTLINE', cx, 72, { scale = 5, align = 'center', color = C.white, bitmap = true })
  local y = 114
  Ui.hline(cx - 132, y, 264, C.amber, 0.7)
  local notch = (t * 46) % 264
  Ui.rect(cx - 132 + notch, y - 2, 12, 5, C.ink)
  Ui.rect(cx - 132 + notch + 1, y - 1, 10, 3, C.red)
end

function Title:draw_seed()
  local box = self:check_box()
  local on = App.fixed_seed
  Ui.rect(box.x, box.y, box.w, box.h, on and C.panel or C.ink)
  Ui.frame(box.x, box.y, box.w, box.h, on and C.amber or C.line, on and 1 or 0.6)
  if on then
    Ui.rect(box.x + 3, box.y + 3, 5, 5, C.amber)
  end
  Text.text(I18n.t('title.fixed_seed'), box.x + 17, box.y + (Ui.cjk and 0 or 2), {
    color = on and C.paper or C.dim,
    alpha = on and 1 or 0.5,
  })

  if not on then
    return
  end

  local fx, fy, fw, fh = 108, box.y - 4, 64, 17
  local hot = self.editing
  Ui.rect(fx, fy, fw, fh, hot and C.panel or C.shade)
  Ui.frame(fx, fy, fw, fh, hot and C.amber or C.line)
  local caret = (hot and (self.blink * 2) % 2 < 1) and '_' or ''
  Text.text(App.seed_text .. caret, fx + fw - 6, fy + (Ui.cjk and 2 or 5), {
    color = C.white,
    align = 'right',
    bitmap = true,
  })
end

function Title:draw()
  Ui.wipe(1)
  Ui.draw_grid_bg(self.t, 18, 200)
  draw_logo(self.t)

  if self.menu then
    self.menu:draw(build_targets(), self.t, App.mouse)
  end

  self:draw_seed()
  Text.text(App.VERSION or '', T.W - 8, 8, { color = C.dim, alpha = 0.40, align = 'right', bitmap = true })
end

return Title
