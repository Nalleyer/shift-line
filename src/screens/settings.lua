-- Settings screen: immediate persistent language selection.
local App = require('app')
local Audio = require('platform.audio')
local Settings = require('platform.settings')
local I18n = require('i18n')
local Ui = require('ui')

local T = Ui.theme
local C = Ui.C
local Text = Ui.text

local Screen = { t = 0, hover = nil }

local OPTION_Y = 120
local OPTION_W = 132
local OPTION_H = 40
local OPTION_X = { 52, 200 }
local BACK = { x = 132, y = 184, w = 120, h = 26 }

local function options()
  return {
    { locale = 'zh', label = I18n.t('settings.lang_zh') },
    { locale = 'en', label = I18n.t('settings.lang_en') },
  }
end

local function option_rect(i)
  return { x = OPTION_X[i], y = OPTION_Y, w = OPTION_W, h = OPTION_H }
end

function Screen:enter()
  self.t = 0
  self.hover = nil
  Audio.music('title')
end

function Screen:choose(locale)
  if locale == I18n.locale then
    Audio.play('ui_move', 0.5)
    return
  end
  Settings.set_locale(locale)
  Ui.set_locale(locale)
  Audio.play('ui_select')
end

function Screen:keypressed(key)
  if key == 'escape' or key == 'backspace' then
    Audio.play('ui_move')
    App.go('title')
  end
end

function Screen:mousepressed(x, y, button)
  if button ~= 1 then
    return
  end
  for i = 1, 2 do
    if Ui.hit(option_rect(i), x, y) then
      self:choose(options()[i].locale)
      return
    end
  end
  if Ui.hit(BACK, x, y) then
    Audio.play('ui_move')
    App.go('title')
  end
end

function Screen:update(dt)
  self.t = self.t + dt
  self.hover = nil
  for i = 1, 2 do
    if Ui.hit(option_rect(i), App.mouse.x, App.mouse.y) then
      self.hover = i
    end
  end
  if Ui.hit(BACK, App.mouse.x, App.mouse.y) then
    self.hover = 'back'
  end
end

function Screen:draw()
  Ui.wipe(1)
  Ui.draw_grid_bg(self.t)

  Text.text(I18n.t('settings.title'), T.W / 2, 38, { scale = 3, color = C.white, align = 'center' })
  Ui.hline(T.W / 2 - 120, 84, 240, C.amber, 0.6)

  for i, option in ipairs(options()) do
    local r = option_rect(i)
    local active = option.locale == I18n.locale
    local hot = self.hover == i
    local border = active and C.amber or (hot and C.white or C.line)
    local fill = (active or hot) and C.panel or C.shade
    Ui.rect(r.x, r.y, r.w, r.h, fill)
    Ui.frame(r.x, r.y, r.w, r.h, border)
    if active then
      Ui.frame(r.x + 1, r.y + 1, r.w - 2, r.h - 2, C.amber, 0.25)
    end
    Text.text(option.label, r.x + r.w / 2, r.y + math.floor((r.h - Ui.text_h) / 2), {
      color = (active or hot) and C.white or C.dim,
      align = 'center',
    })
  end

  Ui.button(BACK.x, BACK.y, BACK.w, BACK.h, I18n.t('common.back'), {
    color = C.paper,
    sub = 'ESC',
    hover = self.hover == 'back',
  })

  Ui.footer(I18n.t('settings.hint'))
end

return Screen
