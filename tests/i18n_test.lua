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

local Units = require('data.units')
local Items = require('data.items')
local Traits = require('data.traits')
local Encounters = require('data.encounters')
local SpriteMap = require('data.sprite_map')
local FontMap = require('data.font_map')
local En = require('i18n.en')
local Zh = require('i18n.zh')
local I18n = require('i18n')
local Text = require('ui.text')
local Assets = require('ui.assets')
local CjkGlyphs = dofile('tests/cjk_glyphs.lua')

-- 1. EN / ZH UI key parity & pure-ASCII EN check
for k, v in pairs(En.ui) do
  assert_true(Zh.ui[k] ~= nil, 'missing Zh.ui key: ' .. k)
  assert_eq(type(v), 'string', 'En.ui value must be string: ' .. k)
  for i = 1, #v do
    assert_true(v:byte(i) < 128, 'En.ui must be pure ASCII at key ' .. k)
  end
end
for k in pairs(Zh.ui) do
  assert_true(En.ui[k] ~= nil, 'extra Zh.ui key not in En.ui: ' .. k)
end

-- 2. Every non-ASCII glyph in Zh.* exists in tests/cjk_glyphs.lua and shiftline-cjk.ttf exists
local glyph_set = {}
for _, ch in ipairs(Text.chars(CjkGlyphs.chars)) do
  glyph_set[ch] = true
end

local function scan_zh(tbl, path)
  for k, v in pairs(tbl) do
    local p = path .. '.' .. tostring(k)
    if type(v) == 'string' then
      for _, ch in ipairs(Text.chars(v)) do
        if ch:byte(1) >= 128 then
          assert_true(glyph_set[ch], 'missing CJK glyph ' .. ch .. ' at ' .. p)
        end
      end
    elseif type(v) == 'table' then
      scan_zh(v, p)
    end
  end
end
scan_zh(Zh, 'Zh')

local font_f = assert(io.open('assets/fonts/shiftline-cjk.ttf', 'rb'), 'missing shiftline-cjk.ttf')
local font_size = font_f:seek('end')
font_f:close()
assert_true(font_size > 1000, 'shiftline-cjk.ttf non-empty')

-- 3. Sprite & icon completeness across data layers
for _, k in ipairs(Units.ALLY_ORDER) do
  assert_true(SpriteMap.unit[k] ~= nil, 'missing unit sprite for ally ' .. k)
end
for _, k in ipairs({ 'A_mature', 'D_drake', 'D_mature', 'N_mature' }) do
  assert_true(SpriteMap.unit[k] ~= nil, 'missing unit sprite for evolved form ' .. k)
end
for _, k in ipairs(Units.ENEMY_ORDER) do
  assert_true(SpriteMap.unit[k] ~= nil, 'missing unit sprite for enemy ' .. k)
end

assert_true(SpriteMap.icon.attack ~= nil, 'missing attack icon in sprite_map')
for id, t in pairs(Traits.definitions) do
  assert_true(SpriteMap.icon[t.icon] ~= nil, 'missing icon ' .. tostring(t.icon) .. ' for trait ' .. id)
end

local seen_icons = {}
for _, id in ipairs(Items.RELIC_ORDER) do
  local r = Items.RELICS[id]
  assert_true(SpriteMap.icon[r.icon] ~= nil, 'missing icon for relic ' .. id)
  assert_true(not seen_icons[r.icon], 'relic icon must be distinct: ' .. r.icon)
  seen_icons[r.icon] = id
end
for _, id in ipairs(Items.ACTIVE_ORDER) do
  local a = Items.ACTIVES[id]
  assert_true(SpriteMap.icon[a.icon] ~= nil, 'missing icon for active ' .. id)
  assert_true(not seen_icons[a.icon], 'active icon must be distinct: ' .. a.icon)
  seen_icons[a.icon] = id
end
assert_true(SpriteMap.icon[Items.ACTIVES.core_cell.icon] ~= nil, 'core_cell icon present')

-- 4. Zh completeness for units, relics, actives, wave names
for _, k in ipairs(Units.ALLY_ORDER) do
  assert_true(Zh.units[k] ~= nil, 'Zh.units missing ' .. k)
end
for _, k in ipairs(Units.ENEMY_ORDER) do
  assert_true(Zh.units[k] ~= nil, 'Zh.units missing enemy ' .. k)
end
for _, id in ipairs(Items.RELIC_ORDER) do
  assert_true(Zh.relics[id] ~= nil, 'Zh.relics missing ' .. id)
end
for id in pairs(Items.ACTIVES) do
  assert_true(Zh.actives[id] ~= nil, 'Zh.actives missing ' .. id)
end
local function check_wave_list(list)
  for _, entry in ipairs(list) do
    local name = type(entry) == 'table' and entry.name or nil
    if name then
      assert_true(Zh.waves[name] ~= nil, 'Zh.waves missing ' .. name)
    end
  end
end
for _, w in ipairs(Encounters.WAVES) do check_wave_list(w) end
for _, mb in ipairs(Encounters.MINI_BOSSES_1) do assert_true(Zh.waves[mb.name] ~= nil, 'Zh.waves missing ' .. mb.name) end
for _, mb in ipairs(Encounters.MINI_BOSSES_2) do assert_true(Zh.waves[mb.name] ~= nil, 'Zh.waves missing ' .. mb.name) end
for _, b in ipairs(Encounters.BOSSES) do assert_true(Zh.waves[b.name] ~= nil, 'Zh.waves missing ' .. b.name) end
for _, f in ipairs(Encounters.FORKS) do check_wave_list(f) end

-- 5. I18n helpers & formatting in EN and ZH
I18n.set_locale('en')
assert_eq(I18n.unit_name({ kind = 'S' }), 'BLADE', 'EN unit_name')
assert_true(#I18n.offer_title({ kind = 'dismiss' }) > 0, 'EN offer_title dismiss')
assert_true(#I18n.offer_detail({ kind = 'upgrade', mode = 'atk' }) > 0, 'EN offer_detail upgrade atk')
assert_eq(I18n.reason('core full'), 'core full', 'EN reason returns key string')

I18n.set_locale('zh')
assert_true(I18n.is_zh(), 'set_locale zh activates zh')
assert_true(I18n.unit_name({ kind = 'S' }) ~= 'BLADE', 'ZH unit_name translated')
assert_eq(I18n.reason('core full'), Zh.reasons['core full'], 'ZH reason translated')
assert_eq(I18n.label('BOSS SHIFT'), Zh.labels['BOSS SHIFT'], 'ZH label translated')
assert_eq(I18n.wave_name('GATEKEEPER'), Zh.waves['GATEKEEPER'], 'ZH wave_name translated')
assert_true(#I18n.relic_description('whetstone', 2) > 0, 'ZH stacked relic description works')
assert_true(#I18n.active_description('core_cell') > 0, 'ZH active_description works')
I18n.set_locale('en')

-- 6. Text width & wrapping (ASCII word wrap + CJK kinsoku line-start punctuation guard)
assert_eq(Text.width('ABC', 1, true), 3 * FontMap.cell_w - 1, 'bitmap width formula')
local en_lines = Text.wrap_lines('HELLO WORLD FROM SHIFTLINE', 60, { scale = 1 })
assert_true(#en_lines >= 2, 'ASCII text wraps within 60px')

local prev_cjk = Assets.cjk
Assets.set_cjk(true)
local zh_lines = Text.wrap_lines('前排单位，受到伤害。', 48, { scale = 1 }) -- 48px = 4 CJK chars -> comma lands at pos 5 unless held
assert_true(#zh_lines >= 2, 'CJK text wraps')
local first_char_second_line = Text.chars(zh_lines[2])[1]
assert_true(first_char_second_line ~= '，' and first_char_second_line ~= '。', 'kinsoku keeps punctuation off line start')
Assets.set_cjk(prev_cjk)

-- 7. Settings persistence round-trip with getInfo guard + corrupt fallback
local orig_love = _G.love
local ok, err = xpcall(function()
  local store = {}
  _G.love = {
    filesystem = {
      getInfo = function(path)
        return store[path] and { type = 'file' } or nil
      end,
      read = function(path)
        if not store[path] then error('missing file') end
        return store[path]
      end,
      write = function(path, body)
        store[path] = body
        return true
      end,
    },
  }
  package.loaded['platform.settings'] = nil
  local Settings = require('platform.settings')
  assert_eq(Settings.load(), 'en', 'missing settings.cfg defaults to en without error')
  assert_true(Settings.set_locale('zh'), 'set_locale zh succeeds')
  assert_true(store[Settings.file] ~= nil, 'settings.cfg persisted')

  Settings.locale = nil
  I18n.set_locale('en')
  assert_eq(Settings.load(), 'zh', 'reloading settings.cfg restores zh')

  store[Settings.file] = 'return {{{ broken lua'
  assert_eq(Settings.load(), 'en', 'corrupt settings.cfg falls back cleanly to en')
end, debug.traceback)
_G.love = orig_love
package.loaded['platform.settings'] = nil
I18n.set_locale('en')
if not ok then error(err, 0) end

print('i18n_test.lua: ALL PASSED')
