-- LÖVE audio wrapper: pooled one-shot SFX sources plus one looping music channel.
local Audio = {}

Audio.sfx_volume = 0.95
Audio.music_volume = 0.55
Audio.sfx_on = true
Audio.music_on = true
Audio.active = {}
Audio.sfx = {}
Audio.music_src = {}
Audio.current = nil
Audio.current_name = nil

local SFX_NAMES = {
  'ui_move',
  'ui_select',
  'ui_deny',
  'shift',
  'fight',
  'hit',
  'hit_big',
  'heal',
  'death',
  'break',
  'core_hit',
  'wave_start',
  'win',
  'lose',
  'tick',
  'node',
}

local MUSIC_NAMES = { 'title', 'battle', 'shop', 'boss' }

function Audio.load()
  if type(love) ~= 'table' or not love.audio or type(love.audio.newSource) ~= 'function' then
    return
  end
  for _, name in ipairs(SFX_NAMES) do
    local ok, src = pcall(love.audio.newSource, 'assets/sfx/' .. name .. '.wav', 'static')
    if ok then
      Audio.sfx[name] = src
    end
  end
  for _, name in ipairs(MUSIC_NAMES) do
    local path = 'assets/music/' .. name .. '.ogg'
    if not (love.filesystem and love.filesystem.getInfo and love.filesystem.getInfo(path)) then
      path = 'assets/music/' .. name .. '.wav'
    end
    local ok, src = pcall(love.audio.newSource, path, 'static')
    if ok then
      src:setLooping(true)
      Audio.music_src[name] = src
    end
  end
end

function Audio.set_music_on(enabled)
  Audio.music_on = not not enabled
  if Audio.current then
    if Audio.music_on then
      Audio.current:setVolume(Audio.music_volume)
      if not Audio.current:isPlaying() then
        pcall(Audio.current.play, Audio.current)
      end
    else
      Audio.current:setVolume(0)
      pcall(Audio.current.stop, Audio.current)
    end
  end
end

function Audio.set_sfx_on(enabled)
  Audio.sfx_on = not not enabled
end

function Audio.unlock()
  if Audio.music_on and Audio.current and not Audio.current:isPlaying() then
    Audio.current:setVolume(Audio.music_volume)
    pcall(Audio.current.play, Audio.current)
  end
end

function Audio.play(name, volume, pitch)
  if not Audio.sfx_on then
    return
  end
  local base = Audio.sfx[name]
  if not base then
    return
  end
  local ok, src = pcall(base.clone, base)
  if not ok or not src then
    return
  end
  src:setVolume(Audio.sfx_volume * (volume or 1))
  if pitch then
    src:setPitch(pitch)
  end
  pcall(src.play, src)
  Audio.active[#Audio.active + 1] = src
  if #Audio.active > 48 then
    table.remove(Audio.active, 1)
  end
end

function Audio.music(name)
  if Audio.current_name == name then
    if Audio.current and Audio.music_on and not Audio.current:isPlaying() then
      Audio.current:setVolume(Audio.music_volume)
      pcall(Audio.current.play, Audio.current)
    end
    return
  end
  if Audio.current then
    pcall(Audio.current.stop, Audio.current)
  end
  Audio.current_name = name
  Audio.current = Audio.music_src[name]
  if Audio.current then
    if Audio.music_on then
      Audio.current:setVolume(Audio.music_volume)
      pcall(Audio.current.play, Audio.current)
    else
      Audio.current:setVolume(0)
    end
  end
end

function Audio.stop_music()
  if Audio.current then
    Audio.current:stop()
  end
  Audio.current = nil
  Audio.current_name = nil
end

function Audio.update()
  for i = #Audio.active, 1, -1 do
    if not Audio.active[i]:isPlaying() then
      table.remove(Audio.active, i)
    end
  end
end

return Audio
