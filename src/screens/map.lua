-- Act-by-Act Expedition Map with Battle, Camp, and Gauntlet-Fork nodes.
local Constants = require('data.constants')
local Encounters = require('data.encounters')
local Unit = require('core.unit')
local Encounter = require('core.encounter')
local App = require('app')
local Audio = require('platform.audio')
local I18n = require('i18n')
local Ui = require('ui')

local T = Ui.theme
local C = Ui.C
local Text = Ui.text

local Map = { t = 0 }

local Y_MID = 96
local Y_TOP = 68
local Y_BOT = 122
local HEADER_Y = T.TOP_H + 5
local INTEL_Y, INTEL_H = 151, 101
local INTEL_TITLE_Y, INTEL_SUB_Y = 154, 168
local INTEL_ENEMY_Y, INTEL_ALLY_Y, INTEL_CELL_H = 183, 218, 33
local ACT_BTN = { x = 294, y = 218, w = 78, h = 25 }
local CAMP_BTN = { x = 294, y = 155, w = 78, h = 16 }
local TITLE_BTN = { x = 8, y = 263, w = 18, h = 18 }

local function tr(key, ...)
  return I18n.t('map.' .. key, ...)
end

local function act_cols(nodes)
  local max_c = 1
  for _, n in ipairs(nodes) do
    if n.col > max_c then
      max_c = n.col
    end
  end
  return max_c
end

local function col_x(col, total_cols)
  if (total_cols or 9) >= 10 then
    return 20 + (col - 1) * 38
  end
  return 24 + (col - 1) * 42
end

local function node_y(n)
  if (n.fork or n.kind == 'draft') and n.branch == 2 then
    return Y_BOT
  end
  if n.fork or (n.kind == 'camp' and n.branch == 1) then
    return Y_TOP
  end
  return Y_MID
end

local function node_size(n)
  return n.kind == 'boss' and 22 or 18
end

local function node_rect(n, total_cols)
  local s = node_size(n)
  local cx, cy = col_x(n.col, total_cols), node_y(n)
  return { x = cx - s / 2, y = cy - s / 2, w = s, h = s, cx = cx, cy = cy }
end

local function act_tab_rect(a)
  return { x = 134 + (a - 1) * 58, y = HEADER_Y, w = 54, h = 14 }
end

local function rail_segment(x1, y1, x2, y2, col, thick, alpha)
  local w = thick and 2 or 1
  local off = thick and 1 or 0
  if y1 == y2 then
    Ui.rect(x1, y1 - off, x2 - x1, w, col, alpha)
  else
    local xm = math.floor((x1 + x2) / 2)
    local top, bot = math.min(y1, y2), math.max(y1, y2)
    Ui.rect(x1, y1 - off, xm - x1, w, col, alpha)
    Ui.rect(xm, top - off, w, bot - top + w, col, alpha)
    Ui.rect(xm + w, y2 - off, x2 - (xm + w), w, col, alpha)
  end
end

function Map:ui_context()
  return { allow_inspect = not self.quit_confirm }
end

function Map:is_node_active(n)
  if not n or n.wave ~= self.run.wave then
    return false
  end
  if self.run.phase == 'camp' and not self.from_camp then
    return n.kind == (self.run:is_draft() and 'draft' or 'camp')
  end
  return n.kind == 'battle' or n.kind == 'boss'
end

function Map:is_node_done(n)
  local run = self.run
  local left_camp = self.from_camp or run.phase ~= 'camp'
  local fork_w = ((n.kind == 'camp' and n.branch == 1) or n.kind == 'draft') and (n.wave - 1) or n.wave
  if n.kind == 'camp' and n.branch == 1 then
    if run.wave < n.wave then
      return false
    end
    if run:fork_choice(fork_w) ~= 1 then
      return false
    end
    return run.wave > n.wave or left_camp
  end
  if n.kind == 'draft' then
    if run.wave < n.wave or run:fork_choice(fork_w) ~= 2 then
      return false
    end
    return run.wave > n.wave or left_camp or not run:is_draft()
  end
  if n.fork then
    if n.wave >= run.wave then
      return false
    end
    return run:fork_choice(n.wave) == n.branch
  end
  if n.wave < run.wave then
    return true
  end
  if n.wave == run.wave and n.kind == 'camp' then
    return left_camp
  end
  return false
end

local function is_node_skipped(run, n)
  if n.kind == 'camp' and n.branch == 1 then
    local fork_w = n.wave - 1
    return run.wave > fork_w and run:fork_choice(fork_w) == 2
  end
  if n.kind == 'draft' then
    local fork_w = n.wave - 1
    return run.wave > fork_w and run:fork_choice(fork_w) ~= 2
  end
  if n.fork and n.wave < run.wave then
    return run:fork_choice(n.wave) ~= n.branch
  end
  return false
end

local function find_node(nodes, kind, wave, branch)
  for _, n in ipairs(nodes) do
    if n.kind == kind and n.wave == wave and (not branch or n.branch == branch) then
      return n
    end
  end
  return nil
end

function Map:show_act(act)
  self.view_act = act
  self.nodes = Encounter.act_nodes(act)
  self.hover_node = nil
  self.inspect_node = self.nodes[1]
  for _, n in ipairs(self.nodes) do
    if self:is_node_active(n) and (not n.fork or n.branch == self.selected_branch) then
      self.inspect_node = n
      break
    end
  end
end

function Map:select_node(n)
  self.inspect_node = n
  if not self.peek and n.fork and self:is_node_active(n) then
    self.selected_branch = n.branch
  end
end

function Map:can_select_fork()
  local run = self.run
  return not self.peek
    and self.view_act == run:act()
    and (run.phase == 'battle' or self.from_camp)
    and run:has_fork(run.wave)
end

function Map:enter(opts)
  opts = opts or {}
  self.run = App.run
  self.t = 0
  self.peek = not not opts.peek
  self.from_camp = opts.from_camp and self.run.phase == 'camp' or false
  self.quit_confirm = false
  self.selected_branch = self.run:fork_choice(self.run.wave)
  self:show_act(self.run:act())
  self.anim_t = 0
  self.anim_dur = (opts.from_wave or opts.from_camp or opts.from_draft) and 0.42 or 0
  self.from_pos = nil

  local nodes = self.nodes
  local total_cols = act_cols(nodes)
  if opts.from_camp then
    local prev = find_node(nodes, 'camp', self.run.wave)
    if prev then
      self.from_pos = { x = col_x(prev.col, total_cols), y = node_y(prev) }
    end
  elseif opts.from_draft then
    local prev = find_node(nodes, 'draft', self.run.wave)
    if prev then
      self.from_pos = { x = col_x(prev.col, total_cols), y = node_y(prev) }
    end
  elseif opts.from_wave then
    local fw = opts.from_wave
    if Encounter.act_of(fw) == self.view_act then
      local prev = find_node(nodes, 'battle', fw, self.run:fork_choice(fw)) or find_node(nodes, 'boss', fw)
      if prev then
        self.from_pos = { x = col_x(prev.col, total_cols), y = node_y(prev) }
      end
    else
      self.from_pos = { x = 8, y = Y_MID }
    end
  end

  Audio.music('shop')
end

function Map:leave() end

function Map:update(dt)
  self.t = self.t + dt
  if self.anim_dur > 0 and self.anim_t < self.anim_dur then
    self.anim_t = math.min(self.anim_dur, self.anim_t + dt)
  end
  local mx, my = App.mouse.x, App.mouse.y
  local nodes = self.nodes
  local total_cols = act_cols(nodes)
  self.hover_node = nil
  for _, n in ipairs(nodes) do
    if Ui.hit(node_rect(n, total_cols), mx, my) then
      self.hover_node = n
      break
    end
  end
end

function Map:back()
  Audio.play('ui_move')
  if self.peek or self.from_camp then
    App.go('camp')
  else
    self.quit_confirm = true
  end
end

function Map:activate()
  local n = self.inspect_node
  if self.peek then
    self:back()
  elseif not self:is_node_active(n) then
    self:show_act(self.run:act())
    Audio.play('ui_move')
  elseif n.kind == 'camp' or n.kind == 'draft' then
    Audio.play('ui_select')
    App.go('camp')
  else
    if self.from_camp then
      self.run:finish_node()
    end
    if n.fork then
      self.run:choose_fork(n.branch, n.wave)
    end
    Audio.play('ui_select')
    App.go('battle')
  end
end

function Map:keypressed(key)
  local confirm = key == 'return' or key == 'space' or key == 'kpenter'
  local back = key == 'escape' or key == 'backspace'
  if self.quit_confirm then
    local action = Ui.dialogs.quit_confirm.keypressed(key)
    if action == 'confirm' then
      Audio.play('ui_select')
      App.go('title')
    elseif action == 'cancel' then
      Audio.play('ui_move')
      self.quit_confirm = false
    end
    return
  end

  if back or (self.peek and (key == 'm' or key == 'tab')) then
    self:back()
    return
  end
  if confirm then
    self:activate()
    return
  end
  if key == '1' or key == '2' or key == '3' then
    self:show_act(tonumber(key))
    Audio.play('ui_move', 0.5)
    return
  end
  if self:can_select_fork() and (key == 'up' or key == 'w' or key == 'down' or key == 's') then
    local branch = (key == 'up' or key == 'w') and 1 or 2
    self:select_node(find_node(self.nodes, 'battle', self.run.wave, branch))
    Audio.play('ui_move', 0.6)
    return
  end
  if key == 'left' or key == 'a' or key == 'right' or key == 'd' then
    local nodes = self.nodes
    local idx = 1
    for i, n in ipairs(nodes) do
      if n == self.inspect_node then
        idx = i
        break
      end
    end
    idx = math.max(1, math.min(#nodes, idx + ((key == 'left' or key == 'a') and -1 or 1)))
    self:select_node(nodes[idx])
    Audio.play('ui_move', 0.4)
  end
end

function Map:mousepressed(x, y, button)
  if button ~= 1 then
    return
  end
  if self.quit_confirm then
    local action = Ui.dialogs.quit_confirm.mousepressed(x, y, button)
    if action == 'confirm' then
      Audio.play('ui_select')
      App.go('title')
    elseif action == 'cancel' then
      Audio.play('ui_move')
      self.quit_confirm = false
    end
    return
  end
  if Ui.hit(TITLE_BTN, x, y) then
    Audio.play('ui_select')
    self.quit_confirm = true
    return
  end
  if self.from_camp and Ui.hit(CAMP_BTN, x, y) then
    self:back()
    return
  end
  for a = 1, Constants.ACTS do
    if Ui.hit(act_tab_rect(a), x, y) then
      self:show_act(a)
      Audio.play('ui_move', 0.5)
      return
    end
  end
  if Ui.hit(ACT_BTN, x, y) then
    self:activate()
    return
  end
  local nodes = self.nodes
  local total_cols = act_cols(nodes)
  for _, n in ipairs(nodes) do
    if Ui.hit(node_rect(n, total_cols), x, y) then
      self:select_node(n)
      Audio.play('ui_move', 0.45)
      return
    end
  end
end

local function inspected_encounter(run, n)
  if not n or n.kind == 'camp' or n.kind == 'draft' then
    return nil
  end
  if run:has_fork(n.wave) then
    local std, alt = run:fork_pair(n.wave)
    return n.branch == 2 and alt or std
  end
  return run.encounters[n.wave]
end

function Map:draw_rails(nodes)
  local run = self.run
  local total_cols = act_cols(nodes)
  local function xof(n)
    return col_x(n.col, total_cols)
  end

  local by_col = {}
  local f_top, f_bot, camp_top, draft_bot
  for _, n in ipairs(nodes) do
    if n.fork then
      if n.branch == 2 then
        f_bot = n
      else
        f_top = n
      end
    elseif n.kind == 'camp' and n.branch == 1 then
      camp_top = n
    elseif n.kind == 'draft' then
      draft_bot = n
    else
      by_col[n.col] = n
    end
  end

  local function link(a, b, force_col, force_alpha)
    if not a or not b then
      return
    end
    local done = self:is_node_done(a) and self:is_node_done(b)
    local actv = (self:is_node_done(a) and self:is_node_active(b))
      or (self:is_node_active(a) and self:is_node_active(b))
    local skip = is_node_skipped(run, a) or is_node_skipped(run, b)
    local col = force_col or (done and C.green or (actv and C.amber or C.line))
    local alpha = force_alpha or (skip and 0.18 or (done and 0.9 or (actv and 0.85 or 0.4)))
    rail_segment(xof(a), node_y(a), xof(b), node_y(b), col, done or actv, alpha)
  end

  for c = 1, (f_top.col - 2) do
    link(by_col[c], by_col[c + 1])
  end
  local pre_fork = by_col[f_top.col - 1]
  local post_fork = by_col[camp_top.col + 1]

  local top_active = self:is_node_active(f_top) and self.selected_branch == 1
  local bot_active = self:is_node_active(f_bot) and self.selected_branch == 2
  local function draw_top_fork()
    rail_segment(
      xof(pre_fork),
      node_y(pre_fork),
      xof(f_top),
      node_y(f_top),
      self:is_node_done(f_top) and C.green or (top_active and C.amber or C.line),
      self:is_node_done(f_top) or top_active,
      is_node_skipped(run, f_top) and 0.18 or 0.7
    )
  end
  local function draw_bot_fork()
    rail_segment(
      xof(pre_fork),
      node_y(pre_fork),
      xof(f_bot),
      node_y(f_bot),
      self:is_node_done(f_bot) and C.green or (bot_active and C.amber or C.red),
      self:is_node_done(f_bot) or bot_active,
      is_node_skipped(run, f_bot) and 0.18 or 0.55
    )
  end
  if is_node_skipped(run, f_top) and not is_node_skipped(run, f_bot) then
    draw_top_fork()
    draw_bot_fork()
  else
    draw_bot_fork()
    draw_top_fork()
  end

  link(f_top, camp_top)
  link(camp_top, post_fork)

  local bot_done = self:is_node_done(f_bot) and (self:is_node_done(post_fork) or self:is_node_active(post_fork))
  local bot_col = bot_done and C.green or (bot_active and C.amber or C.red)
  local bot_alpha = is_node_skipped(run, f_bot) and 0.18 or (bot_done and 0.9 or 0.65)
  if draft_bot then
    link(f_bot, draft_bot, self:is_node_done(f_bot) and C.green or (bot_active and C.amber or C.red), bot_alpha)
    link(draft_bot, post_fork, bot_done and C.green or (self:is_node_active(draft_bot) and C.amber or C.red), bot_alpha)
  else
    rail_segment(xof(f_bot), node_y(f_bot), xof(post_fork), node_y(post_fork), bot_col, bot_done or bot_active, bot_alpha)
  end

  for c = post_fork.col, total_cols - 1 do
    link(by_col[c], by_col[c + 1])
  end
end

function Map:draw_nodes(nodes)
  local run = self.run
  local total_cols = act_cols(nodes)
  for _, n in ipairs(nodes) do
    local r = node_rect(n, total_cols)
    local active = self:is_node_active(n)
    local done = self:is_node_done(n)
    local skipped = is_node_skipped(run, n)
    local is_sel = active and (not n.fork or n.branch == self.selected_branch)
    local is_insp = (self.inspect_node == n)
    local hot = (self.hover_node == n)

    local fill = C.shade
    if done then
      fill = Ui.mix(C.shade, C.green, 0.16)
    elseif is_sel then
      fill = Ui.mix(C.shade, C.amber, 0.16 + 0.08 * math.sin(self.t * 5))
    elseif n.kind == 'camp' then
      fill = Ui.mix(C.shade, C.blue, 0.10)
    elseif n.kind == 'draft' then
      fill = Ui.mix(C.shade, C.amber, 0.12)
    elseif n.kind == 'boss' or n.gauntlet then
      fill = Ui.mix(C.shade, C.red, 0.12)
    end

    local alpha = skipped and 0.22 or 1
    local border = (hot or is_insp) and C.white
      or is_sel and C.amber
      or done and C.green
      or (n.kind == 'camp' and C.blue or (n.kind == 'draft' and C.amber) or (n.kind == 'boss' or n.gauntlet) and C.red or C.line)

    Ui.rect(r.x, r.y, r.w, r.h, fill, alpha)
    Ui.frame(r.x, r.y, r.w, r.h, border, alpha)
    if is_sel then
      Ui.frame(r.x - 2, r.y - 2, r.w + 4, r.h + 4, C.amber, 0.45 + 0.35 * math.sin(self.t * 5))
    end

    local icon_col = done and C.green
      or (is_sel and C.white or (n.kind == 'camp' and C.blue or (n.kind == 'draft' and C.amber) or (n.kind == 'boss' or n.gauntlet) and C.red or C.paper))
    if n.kind == 'camp' then
      Ui.icon('gear', r.cx, r.cy, 1, icon_col, alpha)
    elseif n.kind == 'draft' then
      Ui.icon('star', r.cx, r.cy, 1, icon_col, alpha)
    elseif n.kind == 'boss' then
      Ui.unit(n.wave == #Encounters.WAVES and 'c' or 'b', r.cx, r.cy, 1, done and C.green or C.red, alpha)
    elseif n.gauntlet then
      Ui.icon('dragon_breath', r.cx, r.cy, 1, icon_col, alpha)
    else
      Ui.icon('sword_sides', r.cx, r.cy, 1, icon_col, alpha)
    end
  end

  if self.view_act == run:act() then
    local cur
    for _, n in ipairs(nodes) do
      if self:is_node_active(n) and (not n.fork or n.branch == self.selected_branch) then
        cur = n
        break
      end
    end
    if cur then
      local cx, cy = col_x(cur.col, total_cols), node_y(cur)
      local tx, ty = cx, cy
      if self.anim_dur > 0 and self.from_pos and self.anim_t < self.anim_dur then
        local k = Ui.ease_out(self.anim_t / self.anim_dur)
        tx = self.from_pos.x + (cx - self.from_pos.x) * k
        ty = self.from_pos.y + (cy - self.from_pos.y) * k
      end
      local bob = math.sin(self.t * 6) * 1.2
      local lead = run.roster[run:alive_slots()[1] or 3] or { kind = 'S' }
      Ui.unit(lead.kind, tx, ty - 17 + bob, 1, C.amber)
    end
  end
end

function Map:draw_legend()
  local items = {
    { icon = 'sword_sides', col = C.paper, key = 'legend_battle' },
    { icon = 'gear', col = C.blue, key = 'legend_camp' },
    { icon = 'dragon_breath', col = C.red, key = 'legend_gauntlet' },
    { icon = 'star', col = C.amber, key = 'legend_draft' },
  }
  local x = 14
  local y = 140
  for _, it in ipairs(items) do
    Ui.icon(it.icon, x, y, 1, it.col, 0.7)
    local label = tr(it.key)
    Text.text(label, x + 7, y - (Ui.cjk and 6 or 3), { color = C.dim, alpha = 0.85 })
    x = x + 16 + Text.width(label)
  end
end

local function draw_unit_cell(sx, sy, w, h, unit, side, opts)
  opts = opts or {}
  local cx = sx + w / 2
  local hidden = opts.hidden
  local border = unit and (side == 'enemy' and C.red or C.line) or C.line
  local balpha = unit and (side == 'enemy' and 0.65 or 0.7) or 0.3
  Ui.rect(sx, sy, w, h, C.ink, 0.92)
  Ui.frame(sx, sy, w, h, border, balpha)
  if not unit then
    Text.text('.', cx, sy + 13, { align = 'center', bitmap = true, color = C.dim })
    return
  end
  if hidden then
    Text.text('?', cx, sy + 13, { align = 'center', bitmap = true, color = C.red })
    return
  end
  local col = side == 'enemy' and C.red or C.paper
  Ui.unit(unit, cx, sy + 8, 1, col)
  local hp_col = side == 'enemy' and C.red or (unit.hp < Unit.max_hp(unit) and C.amber or C.green)
  Ui.icon_text('heart', unit.hp, cx, sy + 16, { align = 'center', color = hp_col })
  local atk = side == 'enemy' and (unit.atk or 0) or Unit.attack(unit)
  local def = side == 'enemy' and (unit.def or 0) or Unit.defense(unit)
  Ui.unit_plate(cx, sy + 24, atk, def)
  Ui.tooltip.unit_tooltip({ x = sx, y = sy, w = w, h = h }, unit, opts.tip)
end

function Map:draw_intel()
  local run = self.run
  local n = self.inspect_node
  Ui.panel(8, INTEL_Y, 278, INTEL_H, { fill = C.shade, border = C.line })

  local w = n.wave
  local is_camp = n.kind == 'camp'
  local is_draft = n.kind == 'draft'
  local is_non_battle = is_camp or is_draft
  local is_boss = n.kind == 'boss'
  local done = self:is_node_done(n)
  local enc = (not is_non_battle) and inspected_encounter(run, n) or nil
  local show_exact = (not is_non_battle) and ((w <= run.wave + 1) or is_boss)
  local shared_hp = type(enc) == 'table' and enc.boss and (enc.boss_hp or 14)

  if is_camp then
    Text.fit_text(tr('camp_title', w), 14, INTEL_TITLE_Y, 174, { color = C.blue })
    local badge = done and I18n.t('shop.node_cleared') or (self:is_node_active(n) and tr('next_stop') or '')
    if badge ~= '' then
      Text.text(badge, 280, INTEL_TITLE_Y, { align = 'right', color = C.green })
    end
    Text.fit_text(n.branch == 1 and tr('camp_top_note') or tr('camp_sub'), 14, INTEL_SUB_Y, 264, { color = C.dim })
  elseif is_draft then
    local _, alt = run:fork_pair(w - 1)
    Text.fit_text(tr('draft_title', w), 14, INTEL_TITLE_Y, 174, { color = C.amber })
    local badge = done and I18n.t('shop.node_cleared') or (self:is_node_active(n) and tr('next_stop') or '')
    if badge ~= '' then
      Text.text(badge, 280, INTEL_TITLE_Y, { align = 'right', color = C.green })
    end
    Text.wrap_text(tr('draft_sub', I18n.draft_preview(alt)), 14, INTEL_SUB_Y, 264, { color = C.amber, max_lines = 2 })
  else
    local title_key = is_boss and (w == #Encounters.WAVES and 'node_finalboss' or 'node_miniboss')
      or (n.fork and (n.branch == 2 and 'node_bounty' or 'node_std') or 'node_battle')
    Text.fit_text(I18n.t('shop.' .. title_key, w), 14, INTEL_TITLE_Y, 150, {
      color = is_boss and C.red or C.amber,
    })

    local badge, bcol = '', C.dim
    if done then
      badge, bcol = I18n.t('shop.node_cleared'), C.green
    elseif n.gauntlet and enc then
      badge, bcol = tr('gauntlet_badge'), C.amber
    elseif self:is_node_active(n) then
      badge, bcol = tr('next_stop'), C.green
    end
    if badge ~= '' then
      Text.fit_text(badge, 280, INTEL_TITLE_Y, 124, { align = 'right', color = bcol })
    end

    local threats = enc and Encounter.threats(enc) or {}
    local tnames = {}
    for _, tid in ipairs(threats) do
      tnames[#tnames + 1] = I18n.t('threat.' .. tid)
    end
    local tstr = #tnames > 0 and table.concat(tnames, ', ') or I18n.t('shop.node_threat_none')

    if done then
      Text.fit_text(I18n.t('shop.node_cleared'), 14, INTEL_SUB_Y, 264, { color = C.green })
      Ui.rect(14, INTEL_ENEMY_Y, 266, INTEL_CELL_H, C.ink, 0.85)
      Ui.frame(14, INTEL_ENEMY_Y, 266, INTEL_CELL_H, C.green, 0.45)
      Text.text(I18n.t('shop.node_cleared'), 147, INTEL_ENEMY_Y + 11, { align = 'center', color = C.green })
    else
      if shared_hp then
        Text.fit_text(
          I18n.wave_name(enc.name) .. (I18n.is_zh() and ' · ' or ' / ') .. tr('boss_shared', shared_hp),
          14,
          INTEL_SUB_Y,
          134,
          { color = C.red }
        )
        Text.fit_text(I18n.t('shop.node_threats', tstr), 280, INTEL_SUB_Y, 128, {
          align = 'right',
          color = #threats > 0 and C.amber or C.dim,
        })
      elseif show_exact and enc then
        local wname = I18n.wave_name(enc.name)
        local left_w = math.min(96, Text.width(wname) + 4)
        Text.fit_text(wname, 14, INTEL_SUB_Y, left_w, { color = C.paper })
        Text.fit_text(I18n.t('shop.node_threats', tstr), 280, INTEL_SUB_Y, 260 - left_w, {
          align = 'right',
          color = #threats > 0 and C.amber or C.dim,
        })
      else
        local hint = tr('intel_hidden')
        local left_w = math.min(138, Text.width(hint) + 4)
        Text.fit_text(hint, 14, INTEL_SUB_Y, left_w, { color = C.dim })
        Text.fit_text(I18n.t('shop.node_threats', tstr), 280, INTEL_SUB_Y, 260 - left_w, {
          align = 'right',
          color = #threats > 0 and C.amber or C.dim,
        })
      end
    end
  end

  local enemies = (not is_non_battle and not done and enc) and Encounter.parse_enemies(enc) or {}
  for i = 1, Constants.SLOTS do
    local sx = 14 + (i - 1) * 45
    local cx = sx + 20
    local e = enemies[i]
    local u = run.roster[i]
    if not is_non_battle and not done then
      draw_unit_cell(sx, INTEL_ENEMY_Y, 41, INTEL_CELL_H, e, 'enemy', {
        hidden = e and not show_exact,
        tip = { relics = run.relics },
      })
    end
    local pair = (not is_non_battle and not done) and e and u
    Ui.vline(cx, INTEL_ENEMY_Y + INTEL_CELL_H, 2, pair and C.amber or C.line, pair and 0.85 or 0.35)
    draw_unit_cell(sx, INTEL_ALLY_Y, 41, INTEL_CELL_H, u, 'ally', {
      tip = { line = run.roster, col = i, relics = run.relics },
    })
  end
end

function Map:draw_action_panel()
  local run = self.run
  Ui.panel(290, INTEL_Y, 86, INTEL_H, { fill = C.shade, border = C.line })

  if self.from_camp then
    Ui.button_rect(CAMP_BTN, tr('back_camp'), { color = C.blue }, App.mouse)
  end

  local n = self.inspect_node
  local scouting = not self:is_node_active(n)
  local label_key
  if self.peek or scouting then
    Text.fit_text(tr('action_peek'), 296, 174, 74, { color = C.blue })
    label_key = self.peek and 'back_camp' or 'back_current'
  elseif n.kind == 'camp' then
    Text.fit_text(tr('action_camp', run.wave), 296, 174, 74, { color = C.blue })
    label_key = 'enter_camp'
  elseif n.kind == 'draft' then
    local _, alt = run:fork_pair(run.wave - 1)
    Text.fit_text(tr('action_draft'), 296, 168, 74, { color = C.amber })
    Text.wrap_text(I18n.draft_preview(alt), 296, 182, 74, { color = C.paper, max_lines = 3 })
    label_key = 'enter_draft'
  elseif n.gauntlet then
    local _, alt = run:fork_pair(run.wave)
    Text.wrap_text(tr('action_gauntlet', I18n.draft_preview(alt)), 296, 173, 74, {
      color = C.amber,
      max_lines = 4,
    })
    label_key = 'enter_gauntlet'
  else
    Text.fit_text(tr('action_wave', run.wave, #Encounters.WAVES), 296, 174, 74, { color = C.amber })
    label_key = run.wave == 1 and 'deploy_w1' or 'fight_wave'
  end

  Ui.button_rect(ACT_BTN, tr(label_key), {
    primary = true,
    sub = self.peek and 'ESC / M' or 'ENTER',
    color = label_key == 'enter_gauntlet' and C.amber or nil,
  }, App.mouse)
end

function Map:draw()
  Ui.wipe(1)
  local run = self.run
  App.draw_topbar()

  local cur_act = run:act()
  local header_text_y = HEADER_Y + math.floor((14 - Ui.text_h) / 2)
  Text.fit_text(tr('title_short', cur_act, run.wave, #Encounters.WAVES), 10, header_text_y, 120, { color = C.amber })

  for a = 1, Constants.ACTS do
    local r = act_tab_rect(a)
    local active_tab = (self.view_act == a)
    Ui.button_rect(r, tr('act_tag', a), {
      primary = active_tab,
      color = active_tab and C.white or (a == cur_act and C.amber or C.dim),
    }, App.mouse)
  end

  local fuse_on = (run.fuse or 0) > 0
  local fuse_rect = { x = 316, y = HEADER_Y, w = 58, h = 14 }
  Ui.rect(fuse_rect.x, fuse_rect.y, fuse_rect.w, fuse_rect.h, C.shade)
  Ui.frame(fuse_rect.x, fuse_rect.y, fuse_rect.w, fuse_rect.h, fuse_on and C.green or C.line)
  Ui.icon('insurance', fuse_rect.x + 6, fuse_rect.y + 7, 1, fuse_on and C.green or C.dim)
  Text.fit_text(
    I18n.t('shop.' .. (fuse_on and 'fuse_ready' or 'fuse_spent')),
    fuse_rect.x + 12,
    header_text_y,
    fuse_rect.w - 14,
    { color = fuse_on and C.green or C.dim }
  )

  local nodes = self.nodes
  self:draw_rails(nodes)
  self:draw_nodes(nodes)
  self:draw_legend()
  self:draw_intel()
  self:draw_action_panel()

  Ui.footer(nil, tr(self:can_select_fork() and 'hint_fork' or 'hint_move'))
  local title_hot = not self.quit_confirm and Ui.hit(TITLE_BTN, App.mouse.x, App.mouse.y)
  Ui.button_rect(TITLE_BTN, '', { hover = title_hot }, App.mouse)
  Ui.icon('arrowL', TITLE_BTN.x + 9, TITLE_BTN.y + 9, 1, title_hot and C.white or C.dim)
  if not self.quit_confirm then
    Ui.tooltip.register(TITLE_BTN, I18n.t('battle.quit_title'), I18n.t('battle.quit_confirm'), {
      icon = 'arrowL',
      color = C.paper,
    })
  end

  if self.quit_confirm then
    Ui.begin_frame(App.mouse)
    Ui.dialogs.quit_confirm.draw(App.mouse)
  end
end

return Map
