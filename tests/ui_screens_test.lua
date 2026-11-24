package.path = './src/?.lua;./src/?/init.lua;' .. package.path

local function assert_eq(a, b, msg)
  if a ~= b then
    error((msg or 'assert_eq failed') .. ': got ' .. tostring(a) .. ', expected ' .. tostring(b), 2)
  end
end

local function assert_true(v, msg)
  if not v then
    error(msg or 'assert_true failed', 2)
  end
end

local orig_love = _G.love
local tracked_modules = {
  'app', 'platform.audio', 'platform.settings', 'platform.viewport',
  'ui', 'ui.theme', 'ui.assets', 'ui.text', 'ui.draw', 'ui.dialogs',
  'ui.tooltip', 'ui.inspector', 'ui.hud', 'ui.roster',
  'screens.title', 'screens.settings', 'screens.map',
  'screens.camp', 'screens.camp.cards', 'screens.camp.views',
  'screens.battle', 'screens.battle.fx', 'screens.battle.timeline', 'screens.battle.render',
  'screens.result', 'screens.ending',
}
for _, m in ipairs(tracked_modules) do
  package.loaded[m] = nil
end

local function fake_font()
  return {
    setFilter = function() end,
    getWidth = function(_, s) return #tostring(s) * 6 end,
    getHeight = function() return 12 end,
  }
end

local function fake_image(w, h)
  return {
    setFilter = function() end,
    getDimensions = function() return w or 128, h or 128 end,
    getWidth = function() return w or 128 end,
    getHeight = function() return h or 128 end,
  }
end

local audio_log = { sfx = {}, music = {} }

local function install_stubs()
  _G.love = {
    graphics = {
      newImage = function(path)
        if tostring(path):find('font') then return fake_image(48, 64) end
        return fake_image(128, 128)
      end,
      newQuad = function(...) return { ... } end,
      newFont = function() return fake_font() end,
      setColor = function() end,
      rectangle = function() end,
      circle = function() end,
      line = function() end,
      polygon = function() end,
      points = function() end,
      draw = function() end,
      print = function() end,
      printf = function() end,
      setFont = function() end,
      getFont = function() return fake_font() end,
      setLineWidth = function() end,
      setScissor = function() end,
      intersectScissor = function() end,
      getScissor = function() return nil end,
      transformPoint = function(x, y) return x, y end,
      push = function() end,
      pop = function() end,
      translate = function() end,
      scale = function() end,
      clear = function() end,
      setCanvas = function() end,
      newCanvas = function() return fake_image(384, 288) end,
      getDimensions = function() return 768, 576 end,
    },
    keyboard = { isDown = function() return false end },
    mouse = { getPosition = function() return 0, 0 end, isDown = function() return false end },
    timer = { getTime = function() return 0 end },
    window = { getDesktopDimensions = function() return 1920, 1080 end },
    math = { random = function(a, b) return a or 0 end },
    event = { quit = function() end },
    filesystem = {
      getInfo = function() return nil end,
      read = function() return nil end,
      write = function() return true end,
    },
    audio = { stop = function() end },
  }
  package.loaded['platform.audio'] = {
    load = function() end,
    play = function(id, vol)
      audio_log.sfx[#audio_log.sfx + 1] = { id = id, vol = vol }
    end,
    music = function(track)
      audio_log.music[#audio_log.music + 1] = track
    end,
    stop_music = function() end,
    set_muted = function() end,
  }
end

local function cleanup()
  _G.love = orig_love
  for _, m in ipairs(tracked_modules) do
    package.loaded[m] = nil
  end
end

local ok, err = xpcall(function()
  install_stubs()

  local Run = require('core.run')
  local Encounter = require('core.encounter')
  local BattleRules = require('core.battle')
  local Ui = require('ui')
  local App = require('app')

  Ui.load()

  local screen_names = {
    'title', 'settings', 'map', 'camp', 'battle', 'result', 'ending'
  }
  for _, name in ipairs(screen_names) do
    App.register(name, require('screens.' .. name))
  end

  local Battle = require('screens.battle')
  local Camp = require('screens.camp')
  local Map = require('screens.map')

  -- 1. Battle screen flow: intro skip, deploy shift, fight/playback/fx, shift_both_3 modal, navigator, boss music, inspector
  local run = Run.new(101)
  run.encounters[1] = '..b...' -- Brute in col 3 survives round 1 against starter S so Battle enters 'intervene' phase
  run.relics = { 'navigator' }
  run.inventory = { 'shift_both_3', 'medkit', 'core_patch' }
  run.roster[2] = { kind = 'G', hp = 6, max_hp = 6 }
  run.charge = 2
  App.run = run
  App.go('battle')
  assert_eq(Battle.phase, 'intro', 'battle starts in intro phase')
  Battle:keypressed('return')
  Battle:update(0.01)
  assert_eq(Battle.phase, 'choose', 'pressing return finishes intro into deploy choose phase')

  local before_offset = Battle.state.offset
  Battle:keypressed('a')
  assert_true(Battle.state.offset ~= before_offset, 'deploy shift left changes offset')
  Battle:keypressed('d')
  assert_eq(Battle.state.offset, before_offset, 'deploy shift right restores offset')

  -- Fight round 1 & skip playback into 'intervene' (round_no == 1) so active shift items & navigator are enabled
  Battle:keypressed('return')
  assert_eq(Battle.phase, 'playback', 'try_fight begins playback')
  Battle:skip_playback()
  Battle:finish()
  assert_eq(Battle.phase, 'intervene', 'round 1 ends in intervene phase')

  -- Use shift_both_3 active item modal & test step, limit pulse, cancel, then confirm
  assert_true(Battle:use_item(1), 'open shift_both_3 modal')
  assert_true(Battle.modal ~= nil and Battle.modal.def.id == 'shift_both_3', 'shift_both_3 modal opened')
  Battle:mousepressed(26 + 50, 215, 1) -- Shift A button
  Battle:mousepressed(26 + 50, 215, 1)
  Battle:mousepressed(26 + 50, 215, 1)
  assert_eq(Battle.modal.remaining, 0, '3 steps exhausted')
  Battle:mousepressed(26 + 50, 215, 1) -- exceeds limit -> pulse!
  assert_true((Battle.range_pulse or 0) > 0, 'exceeding shift_both_3 limit triggers range_pulse')
  Battle:mousepressed(60, 240, 1) -- Back (cancel)
  assert_true(Battle.modal == nil and #Battle.state.inventory == 3, 'cancel closes modal and preserves shift_both_3')

  -- Confirm a 1-step shift
  assert_true(Battle:use_item(1), 'reopen shift_both_3')
  Battle:mousepressed(256 + 50, 215, 1) -- Shift D
  Battle:mousepressed(210, 240, 1) -- Confirm
  assert_true(Battle.modal == nil and #Battle.state.inventory == 2, 'confirming shift_both_3 consumes item')

  -- Navigator shift during intervene
  assert_true(Battle:try_shift(1), 'navigator shift succeeds during intervene phase')

  -- Enemy shift FX populates Battle.fx.motion.enemy
  local shift_frames = Battle:build_frames({
    { type = 'reposition', side = 'enemy', delta = 1, line = Battle.state.line, enemies = Battle.state.enemies, label = 'ENEMY SHIFT' }
  })
  assert_true(#shift_frames >= 1, 'build_frames emits reposition frame')
  Battle.enemies = { [1] = { uid = 'g1', kind = 'g', hp = 2, max = 2 } }
  shift_frames[1].ev.enemies = { [2] = { uid = 'g1', kind = 'g', hp = 2, max = 2 } }
  Battle:apply_frame(shift_frames[1])
  assert_true(Battle.fx.motion.enemy.g1 ~= nil, 'apply_frame starts enemy slide fx motion')

  -- Test Unit Inspector modal open / keyboard nav / close
  local inspect_unit = Battle.line[3] or Battle.line[2] or run.roster[3]
  Ui.inspector.open(inspect_unit, { battle = Battle.state })
  assert_true(Ui.inspector.active ~= nil, 'inspector opens')
  App.keypressed('escape')
  assert_true(Ui.inspector.active == nil, 'escape closes inspector')

  -- Boss fight triggers boss music track
  local boss_run = Run.new(102)
  boss_run.wave = 5
  App.run = boss_run
  audio_log.music = {}
  App.go('battle')
  assert_eq(audio_log.music[#audio_log.music], 'boss', 'wave 5 boss battle plays boss music')

  -- 2. Camp screen: topbar active use, sell slots bounds, compact relics (>3 distinct), long-press Leave Camp
  local camp_run = Run.new(202)
  camp_run.wave = 2
  camp_run.core = 5
  camp_run.relics = { 'whetstone', 'padding', 'far_lens', 'bounty' } -- 4 distinct -> compact mode
  camp_run.inventory = { 'core_patch', 'medkit' }
  camp_run:open_camp(0, false)
  App.run = camp_run
  App.go('camp')

  local slots = Ui.hud.loadout_slots(App.ui_context())
  assert_true(slots[1].compact, '>3 distinct relics switches topbar relics to compact mode')

  -- Topbar item click at x=290, y=6 activates slot 1 (core_patch)
  App.mousepressed(290, 6, 1)
  assert_eq(Camp.step, 'use', 'clicking usable active in topbar enters camp use step')
  Camp.step = 'choose'

  -- Sell slots fit completely inside screen and above bottom rail
  local sell_slots = Camp:sell_slots()
  assert_true(#sell_slots >= 5, 'sell_slots exposes relics + actives')
  for _, s in ipairs(sell_slots) do
    assert_true(s.rect.x >= 0 and s.rect.x + s.rect.w <= Ui.T.W, 'sell slot within horizontal bounds')
    assert_true(s.rect.y >= 0 and s.rect.y + s.rect.h < 227, 'sell slot clear of bottom button rail')
  end

  -- Leave Camp confirmation modal: cancel keeps player in camp; confirm navigates to map
  Camp:mousepressed(334, 260, 1)
  assert_true(Camp.leave_confirm, 'clicking Leave Camp opens confirmation dialog')
  App.draw()
  Camp:mousepressed(105, 150, 1) -- Cancel
  assert_true(not Camp.leave_confirm and App.current_name == 'camp', 'Cancel keeps player in camp')
  Camp:mousepressed(334, 260, 1)
  Camp:keypressed('escape')
  assert_true(not Camp.leave_confirm and App.current_name == 'camp', 'ESC closes Leave Camp dialog')
  Camp:mousepressed(334, 260, 1)
  Camp:mousepressed(259, 150, 1) -- Confirm
  assert_eq(App.current_name, 'map', 'Confirming Leave Camp dialog navigates to map')

  -- 3. Map screen: quit confirm modal, Back to Camp, Act 2/3 scouting tabs, fork commit & launch
  local map_run = Run.new(303)
  map_run.wave = 3 -- fork wave
  map_run.phase = 'camp'
  map_run:open_camp(0, false)
  App.run = map_run
  App.go('map', { from_camp = true })

  -- Quit confirm cancel vs confirm
  Map:mousepressed(17, 272, 1) -- TITLE_BTN
  assert_true(Map.quit_confirm, 'clicking Quit opens confirmation dialog')
  Map:mousepressed(105, 150, 1) -- Cancel
  assert_true(not Map.quit_confirm and App.current_name == 'map', 'Cancel keeps player on map')
  Map:mousepressed(17, 272, 1)
  Map:mousepressed(259, 150, 1) -- Confirm
  assert_eq(App.current_name, 'title', 'Confirm returns to title screen')

  -- Re-enter map from camp, test Back to Camp, then Act 2/3 scouting tabs & pre-fork camps
  App.run = map_run
  App.go('map', { from_camp = true })
  Map:mousepressed(330, 162, 1) -- CAMP_BTN
  assert_eq(App.current_name, 'camp', 'CAMP_BTN returns directly to camp when entered from_camp')

  App.go('map', { from_camp = true })
  Map:mousepressed(218, 30, 1) -- Act 2 tab
  assert_eq(Map.view_act, 2, 'clicking Act 2 tab switches view_act')
  assert_eq(Map.nodes[1].kind, 'camp', 'Act 2 begins with a camp node')
  Map:mousepressed(275, 30, 1) -- Act 3 tab
  assert_eq(Map.view_act, 3, 'clicking Act 3 tab switches view_act')
  Map:mousepressed(160, 30, 1) -- Back to Act 1 tab
  assert_eq(Map.view_act, 1, 'clicking Act 1 tab switches back to Act 1')

  -- Select Act 1 gauntlet fork node (col 5, branch 2: x=192, y=122) and launch battle
  Map:mousepressed(192, 122, 1)
  assert_eq(Map.selected_branch, 2, 'clicking gauntlet node selects branch 2')
  Map:mousepressed(330, 230, 1) -- ACT_BTN launch
  assert_eq(map_run:fork_choice(3), 2, 'launching from map commits selected fork choice')
  assert_eq(App.current_name, 'battle', 'ACT_BTN enters battle')

  -- 4. UI toolkit checks: segmented health bar & live ATK in unit_details tooltip
  Ui.begin_frame({ x = 0, y = 0 })
  Ui.draw.health_bar(10, 10, 40, 5, 3, 6, { shield = 2, ghost = 5 })
  Ui.draw.rect(0, 0, 10, 10, Ui.C.ink)

  local mom_unit = { kind = 'V', hp = 5, max = 5 }
  local sim_state = BattleRules.new({ [1] = mom_unit }, 'b.....', 0, 8)
  sim_state.shifted_this_round = true
  local _, lines = Ui.tooltip.unit_details(mom_unit, { state = sim_state, col = 1 })
  assert_true(lines[2]:find('5'), 'unit_details displays live buffed ATK (2 base + 3 momentum = 5)')

  -- 5. Full screen draw & transition coverage (Title, Settings, Map, Camp, Battle, Result, Ending) in EN & ZH
  local I18n = require('i18n')
  for _, lang in ipairs({ 'en', 'zh' }) do
    I18n.set_locale(lang)
    Ui.set_locale(lang)

    App.go('title')
    App.current:toggle_fixed()
    App.update(0.1)
    App.draw()
    App.current:toggle_fixed()

    App.go('settings')
    App.update(0.1)
    App.draw()

    local r = Run.new(42, {
      [1] = { kind = 'S', hp = 3 },
      [2] = { kind = 'A', hp = 2, growth_wins = 4 },
      [3] = { kind = 'D', hp = 4, growth_wins = 6 },
      [4] = { kind = 'N', hp = 4, growth_wins = 3 },
      [5] = { kind = 'K', hp = 5 },
      [6] = { kind = 'W', hp = 7 },
    })
    r.wave = 5
    r.gold = 30
    r.charge = 4
    r.core = 5
    r.relics = { 'whetstone', 'padding', 'far_lens', 'bounty' }
    r.inventory = { 'shift_both_3', 'medkit', 'swap_kit' }
    App.run = r

    App.go('map')
    for a = 1, 3 do
      Map:show_act(a)
      App.update(0.1)
      App.draw()
    end

    r:open_draft(3)
    App.go('camp')
    App.update(0.1)
    App.draw()
    for i = 1, #r:node_offers() do
      Camp.sel = i
      Camp:confirm()
      if Camp.targets and Camp.targets[1] then
        Camp.target = Camp.targets[1]
      end
      App.draw()
      Camp:keypressed('escape')
    end

    r:open_camp(0, false)
    App.go('camp')
    App.update(0.1)
    App.draw()
    Camp.leave_confirm = true
    App.draw()
    Camp.leave_confirm = false
    Camp.step = 'sell'
    App.draw()
    Camp.step = 'choose'
    Camp:use_item(2)
    App.draw()
    Camp.step = 'choose'
    for i = 1, #r:node_offers() do
      Camp.sel = i
      Camp:confirm()
      if Camp.targets and Camp.targets[1] then
        Camp.target = Camp.targets[1]
      end
      App.draw()
      Camp:keypressed('escape')
    end

    r.phase = 'battle'
    App.go('battle')
    App.update(0.1)
    App.draw()
    Battle.intro_t = 99
    App.update(0.1)
    App.draw()
    App.mousemoved(28 + 10, 114 + 10)
    App.draw()
    Battle:try_fight()
    App.update(0.1)
    App.draw()
    Battle:skip_playback()
    Battle:finish()
    App.draw()
    Battle.paused = true
    App.draw()
    Battle.paused = false

    r:commit(r:fight(0))
    App.go('result')
    App.update(0.1)
    App.draw()
    r.summary.fuse_triggered = true
    App.draw()

    App.go('ending', 'victory')
    App.update(0.1)
    App.draw()
    App.go('ending', 'defeat')
    App.update(0.1)
    App.draw()
  end
  I18n.set_locale('en')
  Ui.set_locale('en')
end, debug.traceback)

cleanup()

if not ok then
  error(err, 0)
end

print('ui_screens_test.lua: ALL PASSED')
