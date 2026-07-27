-- Retro Cassette — warm, analog, cassette-era preset.
--
-- Brown/amber palette evoking wood-paneled hi-fi gear and cassette shells,
-- serif type for a print-era feel, a classic (non-waveform) seeker, and a
-- slide transition instead of the app's default scale-pop — everything
-- tuned to feel unhurried rather than snappy/modern.

local function shade(hex, amount)
  local r = tonumber(hex:sub(2, 3), 16)
  local g = tonumber(hex:sub(4, 5), 16)
  local b = tonumber(hex:sub(6, 7), 16)
  local function adjust(c)
    if amount >= 0 then c = c + (255 - c) * amount else c = c + c * amount end
    c = math.floor(c + 0.5)
    if c < 0 then c = 0 end
    if c > 255 then c = 255 end
    return c
  end
  return string.format("#%02X%02X%02X", adjust(r), adjust(g), adjust(b))
end

-- Base "wood veneer" brown, with surface/elevated tones stepped up in
-- even increments — mirrors how a physical cassette deck's panel, buttons,
-- and raised trim get progressively lighter.
local background = "#2A1D14"
local step = 0.10
local surface = shade(background, step)
local elevated_surface = shade(background, step * 2)

local accent = "#D97B3F"      -- burnt-orange dial indicator
local accent_secondary = "#C4A15A" -- brushed-brass trim

theme = {
  meta = {
    id = "retro_skeuomorphic",
    name = "Retro Cassette",
    description = "Warm wood-and-brass tones, serif type, unhurried transitions — a cassette-deck-era look.",
  },
  colors = {
    accent = accent,
    accent_secondary = accent_secondary,
    text_primary = "#F4E9D8",
    text_secondary = "#C9B79A",
    background = background,
    surface = surface,
    elevated_surface = elevated_surface,
  },
  style = {
    font_style = "serif",
    panel_material = "solid",
    launch_screen_style = "aurora",
    tab_transition_style = "slide",
    artwork_style = "radarSweep",
    seeker_style = "classic",
    card_style = "card",
    panel_opacity = 1.0,
    corner_radius_scale = 0.9,
    spacing_scale = 1.05,
  },
  glass = {
    tint_strength = 0.15,
    tint_hue = 0.08,
    use_accent_tint = true,
    translucency = 0.85,
  },
  flags = {
    reduce_motion = true,
    show_bpm_badges = true,
    aggressive_prefetch = false,
    haptic_feedback = true,
  },
  hooks = {
    library_default_sort = "artist",
    pin_favorites_first = false,
    library_default_columns = 1,
  },
}
