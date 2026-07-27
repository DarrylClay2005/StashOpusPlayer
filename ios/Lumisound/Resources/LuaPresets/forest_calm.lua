-- Forest Calm — calm greens, natural-tones preset.
--
-- Distinct from the built-in "Forest" AppBackgroundTheme swatch (which this
-- preset intentionally doesn't reuse) — warmer, slightly deeper greens, a
-- serif face, waveform seeker, and every "loud" flag off to match a calm,
-- unhurried identity.

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

local background = "#12211B"
local surface = shade(background, 0.18)
local elevated_surface = shade(background, 0.35)

local accent = "#5FA777"
local accent_secondary = "#A9C686"

theme = {
  meta = {
    id = "forest_calm",
    name = "Forest Calm",
    description = "Deep, warm greens with a serif face and waveform seeker — an unhurried, natural look.",
  },
  colors = {
    accent = accent,
    accent_secondary = accent_secondary,
    text_primary = "#E8F0E3",
    text_secondary = "#AABF9F",
    background = background,
    surface = surface,
    elevated_surface = elevated_surface,
  },
  style = {
    font_style = "serif",
    panel_material = "solid",
    launch_screen_style = "minimalist",
    tab_transition_style = "fadeOnly",
    artwork_style = "bioluminescentTide",
    seeker_style = "waveform",
    card_style = "comfortable",
    panel_opacity = 0.9,
    corner_radius_scale = 1.1,
    spacing_scale = 1.05,
  },
  glass = {
    tint_strength = 0.1,
    tint_hue = 0.33,
    use_accent_tint = true,
    translucency = 0.8,
  },
  flags = {
    reduce_motion = true,
    show_bpm_badges = false,
    aggressive_prefetch = false,
    haptic_feedback = false,
  },
  hooks = {
    library_default_sort = "dateAdded",
    pin_favorites_first = false,
    library_default_columns = 1,
  },
}
