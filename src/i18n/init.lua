-- Localization lookup and content formatting (English & Simplified Chinese).
local Units = require('data.units')
local Items = require('data.items')
local Traits = require('data.traits')
local Unit = require('core.unit')
local Encounter = require('core.encounter')
local En = require('i18n.en')
local Zh = require('i18n.zh')

local I18n = {}

I18n.locale = 'en'
I18n.LOCALES = { 'en', 'zh' }

function I18n.is_zh()
  return I18n.locale == 'zh'
end

function I18n.set_locale(locale)
  if locale ~= 'en' and locale ~= 'zh' then
    return false
  end
  I18n.locale = locale
  return true
end

function I18n.t(key, ...)
  local text
  if I18n.locale == 'zh' then
    text = Zh.ui[key]
  end
  text = text or En.ui[key]
  if not text then
    return key
  end
  if select('#', ...) > 0 then
    local ok, formatted = pcall(string.format, text, ...)
    return ok and formatted or text
  end
  return text
end

function I18n.table(locale)
  return locale == 'zh' and Zh.ui or En.ui
end

function I18n.keys()
  local out = {}
  for key in pairs(En.ui) do
    out[#out + 1] = key
  end
  table.sort(out)
  return out
end

function I18n.has_key(key)
  return En.ui[key] ~= nil
end

function I18n.language_name()
  return I18n.is_zh() and Zh.ui['common.zh'] or En.ui['common.en']
end

function I18n.other_locale()
  return I18n.is_zh() and 'en' or 'zh'
end

function I18n.unit_name(kind)
  local u = type(kind) == 'table' and kind or nil
  local k = u and u.kind or kind
  local stage = u and Unit.growth_stage(u)
  if stage then
    if I18n.is_zh() and stage.form and Zh.units[k .. '_' .. stage.form] then
      return Zh.units[k .. '_' .. stage.form][1]
    end
    return stage.name
  end
  if I18n.is_zh() and Zh.units[k] then
    return Zh.units[k][1]
  end
  local def = Units.ALLIES[k] or Units.ENEMIES[k]
  return def and def.name or tostring(k)
end

function I18n.unit_blurb(kind)
  local u = type(kind) == 'table' and kind or nil
  local k = u and u.kind or kind
  local stage = u and Unit.growth_stage(u)
  if stage then
    if I18n.is_zh() and stage.form and Zh.units[k .. '_' .. stage.form] then
      return Zh.units[k .. '_' .. stage.form][2]
    end
    return stage.blurb
  end
  if I18n.is_zh() and Zh.units[k] and Zh.units[k][2] then
    return Zh.units[k][2]
  end
  local def = Units.ALLIES[k]
  return def and def.blurb or ''
end

function I18n.relic(id)
  local d = Items.RELICS[id]
  if I18n.is_zh() and Zh.relics[id] then
    local z = Zh.relics[id]
    local translated = {}
    for k, v in pairs(d or {}) do
      translated[k] = v
    end
    translated.name, translated.short, translated.description = z[1], z[2], z[3]
    return translated
  end
  return d
end

function I18n.relic_name(id)
  local d = I18n.relic(id)
  return d and d.name or tostring(id)
end

function I18n.relic_description(id, count)
  if count and count > 1 then
    local tmpl = I18n.is_zh() and Zh.stacked_relics[id] or En.stacked_relics[id]
    if tmpl then
      local amount = id == 'navigator' and count * 3 or id == 'far_lens' and 1 or count
      return string.format(tmpl, amount)
    end
  end
  local d = I18n.relic(id)
  return d and (d.description or d.short) or ''
end

function I18n.active(id)
  local d = Items.ACTIVES[id]
  if I18n.is_zh() and Zh.actives[id] then
    local z = Zh.actives[id]
    local translated = {}
    for k, v in pairs(d or {}) do
      translated[k] = v
    end
    translated.name, translated.short, translated.description = z[1], z[2], z[3]
    return translated
  end
  return d
end

function I18n.active_name(id)
  local d = I18n.active(id)
  return d and d.name or tostring(id)
end

function I18n.active_description(id)
  local d = I18n.active(id)
  return d and (d.description or d.short) or ''
end

function I18n.wave_name(name)
  if not name then
    return ''
  end
  if I18n.is_zh() and Zh.waves[name] then
    return Zh.waves[name]
  end
  return name
end

function I18n.pattern_desc(pattern)
  local counts = Encounter.pattern_counts(pattern)
  local parts = {}
  for _, kind in ipairs(Units.ENEMY_ORDER) do
    local n = counts[kind]
    if n > 0 then
      if I18n.is_zh() then
        parts[#parts + 1] = tostring(n) .. ' ' .. I18n.unit_name(kind)
      else
        local name = Units.ENEMIES[kind].name
        parts[#parts + 1] = tostring(n) .. ' ' .. name .. (n > 1 and 'S' or '')
      end
    end
  end
  return table.concat(parts, '  ')
end

function I18n.reason(text)
  if I18n.is_zh() and text and Zh.reasons[text] then
    return Zh.reasons[text]
  end
  return text
end

function I18n.label(text)
  if not text or not I18n.is_zh() then
    return text
  end
  if Zh.labels[text] then
    return Zh.labels[text]
  end
  for id, d in pairs(Items.RELICS) do
    if d.name == text and Zh.relics[id] then
      return Zh.relics[id][1]
    end
  end
  for id, d in pairs(Items.ACTIVES) do
    if d.name == text and Zh.actives[id] then
      return Zh.actives[id][1]
    end
  end
  return text
end

local UPGRADE_KEY = { atk = 'sharp', hp = 'fortify', def = 'defense' }

function I18n.offer_title(offer)
  if offer.kind == 'recruit' and offer.class then
    return I18n.t('offer.recruit_title', I18n.unit_name(offer.class))
  elseif offer.kind == 'upgrade' and UPGRADE_KEY[offer.mode] then
    return I18n.t('offer.' .. UPGRADE_KEY[offer.mode])
  elseif offer.kind == 'relic' and Items.RELICS[offer.id] then
    return I18n.relic_name(offer.id)
  elseif offer.kind == 'active' and Items.ACTIVES[offer.id] then
    return I18n.active_name(offer.id)
  elseif offer.kind == 'trait' and Traits.shop[offer.id] then
    return I18n.t('trait.' .. offer.id .. '.name')
  elseif offer.kind == 'swap' and offer.free then
    return I18n.t('offer.swap_free')
  elseif offer.kind == 'swap' or offer.kind == 'dismiss' then
    return I18n.t('offer.' .. offer.kind)
  end
  return offer.title or tostring(offer.kind)
end

function I18n.offer_detail(offer)
  if offer.kind == 'recruit' and offer.class then
    local d = Units.ALLIES[offer.class]
    return I18n.t('offer.recruit_stats', d.hp, d.atk)
  elseif offer.kind == 'upgrade' and UPGRADE_KEY[offer.mode] then
    return I18n.t('offer.' .. UPGRADE_KEY[offer.mode] .. '_detail')
  elseif offer.kind == 'relic' and Items.RELICS[offer.id] then
    return I18n.relic_description(offer.id)
  elseif offer.kind == 'active' and Items.ACTIVES[offer.id] then
    return I18n.active_description(offer.id)
  elseif offer.kind == 'trait' and Traits.shop[offer.id] then
    return I18n.t('trait.' .. offer.id .. '.detail')
  elseif offer.kind == 'swap' and offer.free then
    return I18n.t('offer.swap_free_detail')
  elseif offer.kind == 'swap' or offer.kind == 'dismiss' then
    return I18n.t('offer.' .. offer.kind .. '_detail')
  end
  return offer.detail or ''
end

return I18n
