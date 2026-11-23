-- Title screen: game logo, menu, language toggle, and optional fixed seed entry.
local App = require('app')
local Audio = require('platform.audio')
local Settings = require('platform.settings')
local I18n = require('i18n')
local Ui = require('ui')

local T = Ui.theme
local C = Ui.C
local Text = Ui.text

local Title = { t = 0, hover = nil, editing = false, blink = 0 }

local ITEMS = {
  { id = 'start', key = 'title.start' },
  { id = 'settings', key = 'title.settings' },
  { id = 'quit', key = 'title.quit' },
}

local MENU_Y = 168
local MENU_STEP = 24
local CHECK = { x = 14, y = 239 }

local function item_box(i)
  local y = MENU_Y + (i - 1) * MENU_STEP
  local box_y = Ui.cjk and (y - 3) or (y - 5)
  local box_h = Ui.cjk and 18 or 16
  return 112, box_y, 160, box_h, y
end

function Title:enter()
  self.t = 0
  self.hover = nil
  self.editing = false
  self.blink = 0
  Audio.music('title')
end

function Title:activate(index)
  local item = ITEMS[index]
  if not item then
    return
  end
  if item.id == 'start' then
    Audio.play('fight', 0.8)
    App.start_run(App.chosen_seed())
  elseif item.id == 'settings' then
    Audio.play('ui_select')
    App.go('settings')
  else
    love.event.quit()
  end
end

function Title:toggle_language()
  Settings.set_locale(I18n.other_locale())
  Ui.set_locale(I18n.locale)
  Audio.play('ui_select')
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

  local mx, my = App.mouse.x, App.mouse.y
  local hovered = nil
  for i = 1, #ITEMS do
    local bx, by, bw, bh = item_box(i)
    if mx >= bx and mx <= bx + bw and my >= by and my <= by + bh then
      hovered = i
      break
    end
  end
  if hovered and hovered ~= self.hover then
    Audio.play('ui_move', 0.5)
  end
  self.hover = hovered
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

  if key == 'f' then
    self:toggle_fixed()
  elseif key == 'l' then
    self:toggle_language()
  elseif key == 'e' then
    if App.fixed_seed then
      self.editing = true
      Audio.play('ui_select', 0.7)
    else
      Audio.play('ui_deny', 0.6)
    end
  elseif key == 'escape' then
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
  for i = 1, #ITEMS do
    local bx, by, bw, bh = item_box(i)
    if x >= bx and x <= bx + bw and y >= by and y <= by + bh then
      self:activate(i)
      return
    end
  end
end

local function draw_logo(t)
  local cx = T.W / 2
  Text.text('SHIFTLINE', cx + 3, 91, { scale = 5, align = 'center', color = C.red_dk, bitmap = true })
  Text.text('SHIFTLINE', cx, 88, { scale = 5, align = 'center', color = C.white, bitmap = true })
  local y = 130
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

  for i, item in ipairs(ITEMS) do
    local bx, by, bw, bh, y = item_box(i)
    local hovered = (i == self.hover)
    local primary = (i == 1)
    local fill = hovered and C.panel or (primary and Ui.mix(C.shade, C.amber, 0.10) or C.shade)
    local border = hovered and C.amber or (primary and Ui.mix(C.line, C.amber, 0.35) or C.line)
    Ui.rect(bx, by, bw, bh, fill, hovered and 0.95 or 0.75)
    Ui.frame(bx, by, bw, bh, border, hovered and 1 or 0.7)
    if hovered then
      Ui.frame(bx + 1, by + 1, bw - 2, bh - 2, C.amber, 0.25)
    end
    Text.text(I18n.t(item.key), T.W / 2, y, {
      color = hovered and C.white or (primary and C.paper or C.dim),
      align = 'center',
    })
  end

  self:draw_seed()
  Text.text(App.VERSION or '', T.W - 8, 8, { color = C.dim, alpha = 0.40, align = 'right', bitmap = true })
  Ui.footer(I18n.t('title.footer_select'), I18n.t('title.footer_keys'))
end

return Title
