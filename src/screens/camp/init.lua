-- Camp screen controller: offer purchases, formation swaps, Charge actions, item use, and selling.
local Constants = require('data.constants')
local Encounters = require('data.encounters')
local App = require('app')
local Audio = require('platform.audio')
local I18n = require('i18n')
local Ui = require('ui')
local Cards = require('screens.camp.cards')
local Views = require('screens.camp.views')

local T = Ui.theme
local C = Ui.C
local Text = Ui.text

local Screen = { t = 0 }

function Screen:ui_context()
  return {
    can_use_actives = (self.step == 'choose') and not self.leave_confirm,
    active_block_reason = self.step ~= 'choose' and 'shop_busy' or nil,
    allow_inspect = not self.leave_confirm,
    inspect_preview_only = (self.step ~= 'choose'),
  }
end

function Screen:needs_target(o)
  return o.kind == 'recruit'
    or o.kind == 'upgrade'
    or o.kind == 'dismiss'
    or o.kind == 'trait'
    or (o.kind == 'active' and #self.run.inventory >= Constants.INVENTORY_MAX)
end

function Screen:sell_slots()
  return Views.sell_slots(self.run)
end

function Screen:enter()
  self.run = App.run
  self.t = 0
  self.sel = nil
  self.step = 'choose'
  self.target = nil
  self.drag = nil
  self.swap_from = nil
  self.charge_swap = nil
  self.leave_confirm = false
  Audio.play('node', 0.8)
  Audio.music('shop')
end

function Screen:leave() end

function Screen:finish()
  if self.step == 'choose' then
    App.go('map', { from_camp = true })
  end
end

function Screen:use_item(index)
  if self.step ~= 'choose' then
    return
  end
  if not self.run:can_use_shop_item(index) then
    Audio.play('ui_deny')
    return
  end
  self.use_index = index
  self.use_id = self.run.inventory[index]
  self.targets = self.run:shop_item_targets(index)
  self.target = self.targets[1] == 'core' and 'core' or nil
  self.step = 'use'
  Audio.play('ui_select')
end

function Screen:confirm_use()
  if self.run:use_shop_item(self.use_index, self.target, self.use_id) then
    self.step = 'choose'
    self.target = nil
    Audio.play('ui_select')
  else
    Audio.play('ui_deny')
  end
end

function Screen:confirm()
  if self.step == 'confirm' and self.charge_swap then
    return
  end
  local o = self.sel and self.run:node_offers()[self.sel]
  if not o then
    return
  end
  if self.step == 'choose' then
    if not o.available then
      Audio.play('ui_deny')
      return
    end
    self.step = 'confirm'
    self.charge_swap = nil
    self.target = nil
    self.drag = nil
    self.swap_from = nil
    self.targets = self.run:offer_targets(o)
    Audio.play('ui_select')
    return
  end
  if o.kind == 'swap' then
    return
  end
  if self.run:apply_offer(self.sel, self.target) then
    self.step = 'choose'
    self.sel = nil
    self.target = nil
    self.swap_from = nil
    Audio.play('ui_select')
  else
    Audio.play('ui_deny')
  end
end

local function commit_sell(self)
  if self.run:sell_gear(self.sell_kind, self.sell_index, self.sell_id) then
    self.sell_kind = nil
    self.sell_index = nil
    Audio.play('ui_select')
  else
    Audio.play('ui_deny')
  end
end

local function reset_confirm(self)
  self.step = 'choose'
  self.sel = nil
  self.charge_swap = nil
  self.target = nil
  self.drag = nil
  self.swap_from = nil
end

function Screen:keypressed(key)
  if self.leave_confirm then
    local action = Ui.dialogs.confirm.keypressed(key)
    if action == 'confirm' then
      self.leave_confirm = false
      self.run.camp_leave_warned = true
      Audio.play('ui_select')
      self:finish()
    elseif action == 'cancel' then
      self.leave_confirm = false
      Audio.play('ui_move')
    end
    return
  end

  if self.step == 'use' then
    if key == 'escape' or key == 'backspace' then
      self.step = 'choose'
      self.target = nil
    elseif (key == 'return' or key == 'space' or key == 'kpenter') and self.target then
      self:confirm_use()
    end
    return
  end

  if self.step == 'sell' then
    if key == 'escape' or key == 'backspace' then
      self.step = 'choose'
      self.sell_kind = nil
      self.sell_index = nil
    elseif (key == 'return' or key == 'space' or key == 'kpenter') and self.sell_kind then
      commit_sell(self)
    end
    return
  end

  if key == 'escape' or key == 'backspace' then
    if self.step == 'confirm' and self.swap_from then
      self.swap_from = nil
      self.target = nil
      self.drag = nil
      Audio.play('ui_move')
    elseif self.step ~= 'choose' then
      reset_confirm(self)
    end
  elseif self.step == 'choose' and (key == '1' or key == '2' or key == '3') then
    self:use_item(tonumber(key))
  elseif self.step == 'choose' and key == 'm' then
    Audio.play('ui_select')
    App.go('map', { peek = true })
  elseif self.step == 'confirm' and (key == 'return' or key == 'space' or key == 'kpenter') then
    local o = not self.charge_swap and self.sel and self.run:node_offers()[self.sel]
    if o and o.kind ~= 'swap' then
      self:confirm()
    end
  end
end

local function try_commit_swap(self, from, to)
  local ok = (self.charge_swap and self.run:use_charge('swap', from, to))
    or self.run:apply_offer(self.sel, from, to)
  if ok then
    reset_confirm(self)
    Audio.play('ui_select')
  else
    Audio.play('ui_deny')
  end
end

function Screen:mousepressed(x, y, button)
  if button ~= 1 then
    return
  end

  if self.leave_confirm then
    local action = Ui.dialogs.confirm.mousepressed(x, y, button)
    if action == 'confirm' then
      self.leave_confirm = false
      self.run.camp_leave_warned = true
      Audio.play('ui_select')
      self:finish()
    elseif action == 'cancel' then
      self.leave_confirm = false
      Audio.play('ui_move')
    end
    return
  end

  if self.step == 'choose' then
    if Ui.hit(Views.MAP_BTN, x, y) then
      Audio.play('ui_select')
      App.go('map', { peek = true })
      return
    end
    for i, rect in ipairs(Cards.offer_rects(self.run:node_offers())) do
      if Ui.hit(rect, x, y) then
        self.sel = i
        self:confirm()
        return
      end
    end
    if Ui.hit(Views.REROLL_BTN, x, y) then
      if self.run:use_charge('reroll') then
        self.sel = nil
        Audio.play('ui_select')
      else
        Audio.play('ui_deny')
      end
      return
    end
    if Ui.hit(Views.ADJUST_BTN, x, y) then
      if (self.run.charge or 0) >= 2 and self.run:alive_count() > 0 then
        self.charge_swap = true
        self.step = 'confirm'
        self.target = nil
        self.drag = nil
        self.swap_from = nil
        Audio.play('ui_select')
      else
        Audio.play('ui_deny')
      end
      return
    end
    if Ui.hit(Views.TRIAGE_BTN, x, y) then
      if self.run:use_charge('triage') then
        Audio.play('ui_select')
      else
        Audio.play('ui_deny')
      end
      return
    end
    if Ui.hit(Views.LEAVE_BTN, x, y) then
      Audio.play('ui_select', 0.7)
      if self.run.camp_leave_warned then
        self:finish()
      else
        self.leave_confirm = true
        self.leave_confirm_t = 0
      end
      return
    end
    if Ui.hit(Views.SELL_BTN, x, y) then
      self.step = 'sell'
      self.sell_kind = nil
      self.sell_index = nil
      self.drag = nil
      return
    end
  elseif self.step == 'use' then
    if Ui.hit(Views.BACK_BTN, x, y) then
      self.step = 'choose'
      self.target = nil
      return
    end
    if Ui.hit(Views.CONFIRM_BTN, x, y) then
      self:confirm_use()
      return
    end
    for _, slot in ipairs(self.targets) do
      if slot ~= 'core' and Ui.hit(Views.roster_rect(slot), x, y) then
        self.target = slot
        Audio.play('ui_move')
        return
      end
    end
  elseif self.step == 'sell' then
    if Ui.hit(Views.BACK_BTN, x, y) then
      self.step = 'choose'
      self.sell_kind = nil
      return
    end
    if Ui.hit(Views.CONFIRM_BTN, x, y) and self.sell_kind then
      commit_sell(self)
      return
    end
    for _, slot in ipairs(self:sell_slots()) do
      if Ui.hit(slot.rect, x, y) then
        self.sell_kind = slot.kind
        self.sell_index = slot.index
        self.sell_id = slot.id
        Audio.play('ui_move')
        return
      end
    end
  else
    local o = not self.charge_swap and self.sel and self.run:node_offers()[self.sel]
    local can_drag = (self.charge_swap and (self.run.charge or 0) >= 2)
      or (o and o.kind == 'swap' and self.run.gold >= o.price)
    if can_drag then
      for i = 1, Constants.SLOTS do
        if Ui.hit(Views.roster_rect(i), x, y) then
          if self.swap_from then
            if i == self.swap_from then
              self.swap_from = nil
              self.target = nil
              Audio.play('ui_move')
            else
              try_commit_swap(self, self.swap_from, i)
            end
            return
          elseif self.run.roster[i] then
            self.drag = i
            return
          end
        end
      end
    end
    if o and self:needs_target(o) then
      for _, slot in ipairs(self.targets) do
        local r = Cards.is_gear(o) and Views.gear_rect(slot) or Views.roster_rect(slot)
        if Ui.hit(r, x, y) then
          self.target = slot
          Audio.play('ui_move')
          return
        end
      end
    end
    if Ui.hit(Views.CONFIRM_BTN, x, y) then
      self:confirm()
    elseif Ui.hit(Views.BACK_BTN, x, y) then
      reset_confirm(self)
    end
  end
end

function Screen:mousereleased(x, y, button)
  if button ~= 1 then
    return
  end
  if not self.drag then
    return
  end
  local from = self.drag
  self.drag = nil
  if self.step ~= 'confirm' then
    return
  end
  local o = not self.charge_swap and self.sel and self.run:node_offers()[self.sel]
  if not self.charge_swap and (not o or o.kind ~= 'swap') then
    return
  end
  for i = 1, Constants.SLOTS do
    if Ui.hit(Views.roster_rect(i), x, y) then
      if i == from then
        self.swap_from = from
        self.target = from
        Audio.play('ui_select')
      else
        try_commit_swap(self, from, i)
      end
      return
    end
  end
end

function Screen:update(dt)
  self.t = self.t + dt
  if self.leave_confirm then
    self.leave_confirm_t = (self.leave_confirm_t or 0) + dt
  end
end

function Screen:draw()
  Ui.wipe(1)
  App.draw_topbar()

  local act = self.run:act()
  local header_text_y = Cards.HEADER_Y + math.floor((Cards.HEADER_H - Ui.text_h) / 2)
  Text.fit_text(I18n.t('shop.act_header', act, self.run.wave, #Encounters.WAVES), 8, header_text_y, 90, {
    color = C.amber,
  })

  if self.step == 'choose' then
    Views.draw_choose(self, header_text_y, App.mouse)
  elseif self.step == 'use' then
    Views.draw_use(self, App.mouse)
  elseif self.step == 'sell' then
    Views.draw_sell(self, App.mouse)
  else
    Views.draw_confirm(self, App.mouse)
  end

  Ui.rect(0, Views.CAMP_FOOT_Y, T.W, T.H - Views.CAMP_FOOT_Y, C.shade, 0.55)
  Ui.hline(0, Views.CAMP_FOOT_Y, T.W, C.line, 0.75)

  if self.leave_confirm then
    Ui.begin_frame(App.mouse)
    local cps = Ui.cjk and 26 or 44
    Ui.dialogs.confirm.draw(App.mouse, I18n.t('shop.leave_confirm'), {
      reveal_chars = math.floor((self.leave_confirm_t or 0) * cps),
    })
  end
end

return Screen
