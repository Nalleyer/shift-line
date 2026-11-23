-- Sprite sheets, bitmap font quads, and CJK pixel font loading.
local FontMap = require('data.font_map')
local SpriteMap = require('data.sprite_map')
local I18n = require('i18n')

local Assets = {
  cjk = false,
  cjkFont = nil,
  line_h = 10,
  text_h = 7,
  fontImg = nil,
  unitImg = nil,
  iconImg = nil,
  fontQuad = {},
  unitQuad = {},
  iconQuad = {},
}

local CJK_FONT_PATH = 'assets/fonts/shiftline-cjk.ttf'
local CJK_FONT_SIZE = 12

function Assets.load_cjk_font()
  if Assets.cjkFont then
    return true
  end
  if type(love) ~= 'table' or not love.graphics or type(love.graphics.newFont) ~= 'function' then
    return false
  end
  local ok, font = pcall(love.graphics.newFont, CJK_FONT_PATH, CJK_FONT_SIZE)
  if not ok or not font then
    print('[ui] missing CJK font ' .. CJK_FONT_PATH .. ' -- run ./run.sh --fonts')
    return false
  end
  font:setFilter('nearest', 'nearest')
  Assets.cjkFont = font
  return true
end

function Assets.set_cjk(enabled)
  Assets.cjk = not not enabled
  Assets.line_h = Assets.cjk and 13 or 10
  Assets.text_h = Assets.cjk and 12 or 7
end

function Assets.set_locale(locale)
  if locale then
    I18n.set_locale(locale)
  end
  local want_cjk = I18n.is_zh()
  if want_cjk and not Assets.load_cjk_font() then
    I18n.set_locale('en')
    want_cjk = false
  end
  Assets.set_cjk(want_cjk)
end

function Assets.load()
  Assets.fontImg = love.graphics.newImage('assets/font.png')
  Assets.unitImg = love.graphics.newImage('assets/units.png')
  Assets.iconImg = love.graphics.newImage('assets/icons.png')
  for _, img in ipairs({ Assets.fontImg, Assets.unitImg, Assets.iconImg }) do
    img:setFilter('nearest', 'nearest')
  end

  Assets.set_locale()

  local fw, fh = Assets.fontImg:getDimensions()
  for i = 1, #FontMap.chars do
    local gx = ((i - 1) % FontMap.cols) * FontMap.cell_w
    local gy = math.floor((i - 1) / FontMap.cols) * FontMap.cell_h
    Assets.fontQuad[i] = love.graphics.newQuad(gx, gy, FontMap.cell_w, FontMap.cell_h, fw, fh)
  end

  local uw, uh = Assets.unitImg:getDimensions()
  for i = 0, (SpriteMap.unit_count or SpriteMap.unit_cols) - 1 do
    local gx = (i % SpriteMap.unit_cols) * SpriteMap.unit_size
    local gy = math.floor(i / SpriteMap.unit_cols) * SpriteMap.unit_size
    Assets.unitQuad[i] = love.graphics.newQuad(gx, gy, SpriteMap.unit_size, SpriteMap.unit_size, uw, uh)
  end

  local iw, ih = Assets.iconImg:getDimensions()
  for i = 0, (SpriteMap.icon_count or 16) - 1 do
    local gx = (i % SpriteMap.icon_cols) * SpriteMap.icon_size
    local gy = math.floor(i / SpriteMap.icon_cols) * SpriteMap.icon_size
    Assets.iconQuad[i] = love.graphics.newQuad(gx, gy, SpriteMap.icon_size, SpriteMap.icon_size, iw, ih)
  end
end

return Assets
