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
    local ok, src = pcall(love.audio.newSource, 'assets/music/' .. name .. '.wav', 'static')
    if ok then
      src:setLooping(true)
      Audio.music_src[name] = src
    end
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
  local src = base:clone()
  src:setVolume(Audio.sfx_volume * (volume or 1))
  if pitch then
    src:setPitch(pitch)
  end
  src:play()
  Audio.active[#Audio.active + 1] = src
  if #Audio.active > 48 then
    table.remove(Audio.active, 1)
  end
end

function Audio.music(name)
  if Audio.current_name == name then
    if Audio.current and not Audio.current:isPlaying() then
      Audio.current:setVolume(Audio.music_on and Audio.music_volume or 0)
      Audio.current:play()
    end
    return
  end
  if Audio.current then
    Audio.current:stop()
  end
  Audio.current_name = name
  Audio.current = Audio.music_src[name]
  if Audio.current then
    Audio.current:setVolume(Audio.music_on and Audio.music_volume or 0)
    Audio.current:play()
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
