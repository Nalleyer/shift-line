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

local function list_lua_files(dir)
  local p = assert(io.popen("find '" .. dir .. "' -type f -name '*.lua' | sort"))
  local out = {}
  for line in p:lines() do
    out[#out + 1] = line
  end
  p:close()
  return out
end

local function read_all(path)
  local f = assert(io.open(path, 'rb'), 'cannot read ' .. path)
  local body = f:read('*a')
  f:close()
  return body
end

-- 1. Headless pure-Lua invariant: data.*, core.*, i18n.* load with _G.love = nil
local orig_love = _G.love
local pure_modules = {
  'data.constants', 'data.traits', 'data.units', 'data.items',
  'data.encounters', 'data.font_map', 'data.sprite_map',
  'core.util', 'core.rng', 'core.unit', 'core.encounter',
  'core.battle', 'core.camp', 'core.run',
  'i18n.en', 'i18n.zh', 'i18n',
}
local ok_pure, err_pure = xpcall(function()
  _G.love = nil
  for _, m in ipairs(pure_modules) do
    package.loaded[m] = nil
  end
  for _, m in ipairs(pure_modules) do
    assert_true(require(m) ~= nil, 'failed to load pure module ' .. m)
  end
end, debug.traceback)
_G.love = orig_love
if not ok_pure then error(err_pure, 0) end

-- 2. Static boundary & hygiene scans across src/
local ui_files = list_lua_files('src/ui')
assert_true(#ui_files >= 9, 'expected modular ui files')
for _, path in ipairs(ui_files) do
  local src = read_all(path)
  assert_true(not src:match("require%s*%(?%s*['\"]app['\"]"), 'UI must not depend on app: ' .. path)
  assert_true(not src:match("require%s*%(?%s*['\"]screens"), 'UI must not depend on screens: ' .. path)
end

local all_src_files = list_lua_files('src')
local forbidden = { 'shots', 'autorun', 'qa_policy', 'playtest', 'experiments', 'screens%.node', 'screens%.deploy' }
for _, path in ipairs(all_src_files) do
  local src = read_all(path)
  assert_true(not src:match("require%s*%(?%s*['\"]src%."), 'non-canonical src.* require in ' .. path)
  for _, pat in ipairs(forbidden) do
    assert_true(not src:match(pat), 'forbidden legacy reference (' .. pat .. ') in ' .. path)
  end
end

-- 3. i18n dead-key check: every En.ui key must be reachable from src/ (excluding i18n/*.lua literals)
local En = require('i18n.en')
local Traits = require('data.traits')
local literals = {}
local map_src = ''
local camp_src = ''

for _, path in ipairs(all_src_files) do
  if not path:match('^src/i18n/') then
    local body = read_all(path)
    if path == 'src/screens/map.lua' then
      map_src = body
    elseif path:match('^src/screens/camp/') then
      camp_src = camp_src .. '\n' .. body
    end
    for lit in body:gmatch("'([%w_%.]+)'") do
      literals[lit] = true
    end
    for lit in body:gmatch('"([%w_%.]+)"') do
      literals[lit] = true
    end
  end
end

local dynamic_referenced = {
  ['common.en'] = true, ['common.zh'] = true,
  ['threat.guard'] = true, ['threat.cleave'] = true, ['threat.pierce'] = true,
  ['threat.armor'] = true, ['threat.taunt'] = true, ['threat.volley'] = true,
  ['threat.momentum'] = true, ['threat.intercept'] = true,
  ['ui.guard_range'] = true, ['ui.heal_range'] = true, ['ui.charge_range'] = true,
  ['shop.rarity_common'] = true, ['shop.rarity_rare'] = true, ['shop.rarity_epic'] = true, ['shop.rarity_legendary'] = true,
  ['shop.node_threats'] = true, ['shop.node_threat_none'] = true, ['shop.node_cleared'] = true,
  ['shop.node_act'] = true, ['shop.node_wave'] = true, ['shop.node_boss'] = true, ['shop.node_title'] = true,
  ['shop.fuse_ready'] = true, ['shop.fuse_spent'] = true,
  ['offer.recruit'] = true, ['offer.recruit_title'] = true, ['offer.recruit_stats'] = true,
  ['offer.sharp'] = true, ['offer.sharp_detail'] = true,
  ['offer.fortify'] = true, ['offer.fortify_detail'] = true,
  ['offer.defense'] = true, ['offer.defense_detail'] = true,
  ['offer.dismiss'] = true, ['offer.dismiss_detail'] = true,
  ['offer.swap'] = true, ['offer.swap_detail'] = true, ['offer.swap_free'] = true, ['offer.swap_free_detail'] = true,
}
for id in pairs(Traits.definitions) do
  dynamic_referenced['trait.' .. id .. '.name'] = true
  dynamic_referenced['trait.' .. id .. '.detail'] = true
end
for suffix in map_src:gmatch("tr%('([%w_]+)'") do
  dynamic_referenced['map.' .. suffix] = true
end
for suffix in camp_src:gmatch("tr%('([%w_]+)'") do
  dynamic_referenced['shop.' .. suffix] = true
end

-- Check battle/map/camp dynamic title keys in literals (e.g. 'battle.shift_left', 'action_boss', etc.)
local unused = {}
for k in pairs(En.ui) do
  local ok_ref = literals[k] or dynamic_referenced[k]
  if not ok_ref then
    -- Check suffix after 'map.' or 'shop.' against literal strings constructed in map/camp files
    local map_suffix = k:match('^map%.([%w_]+)$')
    local shop_suffix = k:match('^shop%.([%w_]+)$')
    local threat_suffix = k:match('^threat%.([%w_]+)$')
    local battle_suffix = k:match('^battle%.([%w_]+)$')
    if map_suffix and literals[map_suffix] then
      ok_ref = true
    elseif shop_suffix and literals[shop_suffix] then
      ok_ref = true
    elseif threat_suffix and literals[threat_suffix] then
      ok_ref = true
    elseif battle_suffix and literals[battle_suffix] then
      ok_ref = true
    end
  end
  if not ok_ref then
    unused[#unused + 1] = k
  end
end
table.sort(unused)
assert_eq(#unused, 0, 'unused En.ui keys found: ' .. table.concat(unused, ', '))

-- 4. conf.lua metadata validation
local conf_env = { love = {} }
local conf_chunk = assert(loadfile('conf.lua'))
setfenv(conf_chunk, conf_env)
conf_chunk()
local t = { window = {}, modules = {} }
conf_env.love.conf(t)
assert_eq(t.version, '11.4', 'conf.lua version must be 11.4')
assert_eq(t.identity, 'shiftline', 'conf.lua identity')
assert_eq(t.window.title, 'SHIFTLINE', 'conf.lua window title')

-- 5. main.lua boot test with stubbed LÖVE and --lang zh
local loaded_before = {}
for k in pairs(package.loaded) do loaded_before[k] = true end
local ok_boot, err_boot = xpcall(function()
  local fake_font = function()
    return { setFilter = function() end, getWidth = function(_, s) return #tostring(s) * 6 end, getHeight = function() return 12 end }
  end
  local fake_img = function(w, h)
    return { setFilter = function() end, getDimensions = function() return w or 128, h or 128 end }
  end
  local fake_src = function()
    return {
      clone = function(self) return self end,
      setVolume = function() end,
      setPitch = function() end,
      setLooping = function() end,
      play = function() end,
      stop = function() end,
      isPlaying = function() return false end,
    }
  end
  _G.love = {
    filesystem = {
      setRequirePath = function() end,
      getInfo = function() return nil end,
      read = function() return nil end,
      write = function() return true end,
    },
    graphics = {
      setDefaultFilter = function() end,
      newCanvas = function(w, h) return fake_img(w, h) end,
      newImage = function(p) return tostring(p):find('font') and fake_img(48, 64) or fake_img(128, 128) end,
      newQuad = function(...) return { ... } end,
      newFont = fake_font,
      getFont = fake_font,
      getDimensions = function() return 768, 576 end,
      setCanvas = function() end,
      clear = function() end,
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
      setLineWidth = function() end,
      setScissor = function() end,
      push = function() end,
      pop = function() end,
      translate = function() end,
      scale = function() end,
    },
    keyboard = { setKeyRepeat = function() end, isDown = function() return false end },
    audio = { newSource = fake_src },
    window = { getFullscreen = function() return false end, setFullscreen = function() end },
    math = { random = function(a) return a or 0 end },
    event = { quit = function() end },
  }

  -- Reload clean modules before running main.lua
  local reset_mods = {
    'app', 'platform.audio', 'platform.settings', 'platform.viewport',
    'ui', 'ui.assets', 'i18n',
    'screens.title', 'screens.settings', 'screens.map', 'screens.camp',
    'screens.battle', 'screens.result', 'screens.ending',
  }
  for _, m in ipairs(reset_mods) do package.loaded[m] = nil end

  dofile('main.lua')
  love.load({})
  local I18n = require('i18n')
  assert_eq(I18n.locale, 'en', 'main.lua defaults to English when no settings or --lang arg exist')
  assert_true(not I18n.is_zh(), 'default locale is not zh')

  love.load({ '--lang', 'zh' })

  local App = require('app')
  assert_true(I18n.is_zh(), '--lang zh overrides locale at boot')
  assert_eq(App.current_name, 'title', 'main.lua boots to title screen')
  for _, s in ipairs({ 'title', 'settings', 'map', 'camp', 'battle', 'result', 'ending' }) do
    assert_true(App.screens[s] ~= nil, 'screen registered at boot: ' .. s)
  end
  love.update(0.016)
  love.draw()
end, debug.traceback)
_G.love = orig_love
for k in pairs(package.loaded) do
  if not loaded_before[k] then
    package.loaded[k] = nil
  end
end
require('i18n').set_locale('en')
if not ok_boot then error(err_boot, 0) end

print('architecture_test.lua: ALL PASSED')
