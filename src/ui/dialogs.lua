-- Shared modal confirmation dialogs used by Map, Camp, and Battle screens.
local I18n = require('i18n')
local Theme = require('ui.theme')
local Draw = require('ui.draw')
local Text = require('ui.text')

local C = Theme.C
local Dialogs = {}

local Confirm = {
  CANCEL_RECT = { x = 70, y = 142, w = 100, h = 22 },
  CONFIRM_RECT = { x = 214, y = 142, w = 100, h = 22 },
}

function Confirm.keypressed(key)
  if key == 'return' or key == 'space' or key == 'kpenter' then
    return 'confirm'
  elseif key == 'escape' or key == 'backspace' then
    return 'cancel'
  end
  return nil
end

function Confirm.mousepressed(x, y, button)
  if button ~= 1 then
    return nil
  end
  if Draw.hit(Confirm.CONFIRM_RECT, x, y) then
    return 'confirm'
  elseif Draw.hit(Confirm.CANCEL_RECT, x, y) then
    return 'cancel'
  end
  return nil
end

function Confirm.draw(mouse, message)
  Draw.rect(0, 0, Theme.W, Theme.H, C.ink, 0.85)
  Draw.panel(52, 105, 280, 70, { fill = C.shade, border = C.amber })
  Text.fit_text(message or '', Theme.W / 2, 115, 260, { color = C.white, align = 'center' })
  Draw.button_rect(Confirm.CANCEL_RECT, I18n.t('common.back'), {}, mouse)
  Draw.button_rect(Confirm.CONFIRM_RECT, I18n.t('common.confirm'), { primary = true, color = C.white }, mouse)
end

Dialogs.confirm = Confirm
Dialogs.quit_confirm = {
  CANCEL_RECT = Confirm.CANCEL_RECT,
  CONFIRM_RECT = Confirm.CONFIRM_RECT,
  keypressed = Confirm.keypressed,
  mousepressed = Confirm.mousepressed,
  draw = function(mouse)
    Confirm.draw(mouse, I18n.t('battle.quit_confirm'))
  end,
}

return Dialogs
