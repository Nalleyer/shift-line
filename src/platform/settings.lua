-- Persistent player preferences in LÖVE's save directory.
-- Filesystem calls are guarded for both headless tests and love.js compatibility.
local I18n = require('i18n')
local Audio = require('platform.audio')

local Settings = {}

Settings.file = 'settings.cfg'
Settings.locale = nil
Settings.music_on = true
Settings.sfx_on = true
Settings.data = {}

local function love_fs()
  return type(love) == 'table' and love.filesystem and type(love.filesystem.read) == 'function'
end

function Settings.detect_locale()
  return 'en'
end

function Settings.valid(locale)
  return locale == 'en' or locale == 'zh'
end

function Settings.load()
  local data = {}
  if love_fs() and (not love.filesystem.getInfo or love.filesystem.getInfo(Settings.file)) then
    local ok, content = pcall(love.filesystem.read, Settings.file)
    if ok and type(content) == 'string' and #content > 0 then
      local loader = loadstring or load
      local chunk = loader(content, '@' .. Settings.file)
      if chunk then
        local parsed, value = pcall(chunk)
        if parsed and type(value) == 'table' then
          data = value
        end
      end
    end
  end
  Settings.data = data
  local locale = Settings.valid(data.locale) and data.locale or Settings.detect_locale()
  Settings.locale = locale
  I18n.set_locale(locale)

  Settings.music_on = data.music_on ~= false
  Settings.sfx_on = data.sfx_on ~= false
  if Audio.set_music_on then
    Audio.set_music_on(Settings.music_on)
  else
    Audio.music_on = Settings.music_on
  end
  if Audio.set_sfx_on then
    Audio.set_sfx_on(Settings.sfx_on)
  else
    Audio.sfx_on = Settings.sfx_on
  end
  return locale
end

function Settings.save()
  if not love_fs() then
    return false
  end
  Settings.locale = Settings.locale or I18n.locale or 'en'
  local body = string.format(
    'return { locale = %q, music_on = %s, sfx_on = %s }\n',
    Settings.locale,
    tostring(Settings.music_on ~= false),
    tostring(Settings.sfx_on ~= false)
  )
  local ok, success, err = pcall(love.filesystem.write, Settings.file, body)
  if not ok or not success then
    local dir = love.filesystem.getSaveDirectory and love.filesystem.getSaveDirectory() or '?'
    print('[settings] could not save ' .. tostring(Settings.file) .. ' in ' .. tostring(dir) .. ': ' .. tostring(ok and err or success))
    return false
  end
  return true
end

function Settings.set_music_on(enabled)
  Settings.music_on = not not enabled
  if Audio.set_music_on then
    Audio.set_music_on(Settings.music_on)
  else
    Audio.music_on = Settings.music_on
  end
  Settings.save()
  return Settings.music_on
end

function Settings.toggle_music()
  return Settings.set_music_on(not Settings.music_on)
end

function Settings.set_sfx_on(enabled)
  Settings.sfx_on = not not enabled
  if Audio.set_sfx_on then
    Audio.set_sfx_on(Settings.sfx_on)
  else
    Audio.sfx_on = Settings.sfx_on
  end
  Settings.save()
  return Settings.sfx_on
end

function Settings.toggle_sfx()
  return Settings.set_sfx_on(not Settings.sfx_on)
end

function Settings.set_locale(locale)
  if not Settings.valid(locale) then
    return false
  end
  Settings.locale = locale
  I18n.set_locale(locale)
  Settings.save()
  return true
end

function Settings.toggle_locale()
  return Settings.set_locale(I18n.other_locale())
end

return Settings
