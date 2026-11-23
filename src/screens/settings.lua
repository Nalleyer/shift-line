-- Settings screen: battle-style A/D Swordsman menu for language selection and back.
local App = require('app')
local Audio = require('platform.audio')
local Settings = require('platform.settings')
local I18n = require('i18n')
local Ui = require('ui')

local T = Ui.theme
local C = Ui.C
local Text = Ui.text

local Screen = { t = 0, menu = nil }

local function build_targets()
  return {
    {
      id = 'zh',
      label = I18n.t('settings.lang_zh'),
      icon = 'lang_zh',
      color = C.amber,
      active = I18n.locale == 'zh',
      sound = 'ui_select',
    },
    {
      id = 'en',
      label = I18n.t('settings.lang_en'),
      icon = 'lang_en',
      color = C.blue,
      active = I18n.locale == 'en',
      sound = 'ui_select',
    },
    {
      id = 'back',
      label = I18n.t('common.back'),
      icon = 'arrowL',
      color = C.paper,
      sound = 'ui_move',
    },
  }
end

function Screen:enter()
  self.t = 0
  self.menu = Ui.duel_menu.new({
    y_enemy = 132,
    y_player = 188,
    default_col = I18n.locale == 'zh' and 1 or 2,
    on_select = function(target)
      if target.id == 'back' then
        App.go('title')
      else
        self:choose(target.id)
      end
    end,
  })
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
  if self.menu and self.menu:keypressed(key, build_targets()) then
    return
  end
  if key == 'escape' or key == 'backspace' then
    Audio.play('ui_move')
    App.go('title')
  end
end

function Screen:mousepressed(x, y, button)
  if button ~= 1 then
    return
  end
  if self.menu then
    self.menu:mousepressed(x, y, build_targets())
  end
end

function Screen:update(dt)
  self.t = self.t + dt
  if self.menu then
    self.menu:update(dt, App.mouse, build_targets())
  end
end

function Screen:draw()
  Ui.wipe(1)
  Ui.draw_grid_bg(self.t)

  Text.text(I18n.t('settings.title'), T.W / 2, 38, { scale = 3, color = C.white, align = 'center' })
  Ui.hline(T.W / 2 - 120, 84, 240, C.amber, 0.6)

  if self.menu then
    self.menu:draw(build_targets(), self.t, App.mouse)
  end

  Ui.footer(I18n.t('settings.hint'))
end

return Screen
