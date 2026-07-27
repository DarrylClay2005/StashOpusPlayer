-- High Contrast — accessibility-first preset.
--
-- Pure black background with a near-white/high-visibility yellow accent
-- (chosen over the app's default pink for its much higher contrast ratio
-- against both black and white), motion disabled, and slightly larger
-- corner radii + spacing for easier hit-targets and less visual clutter.
--
-- Loaded by Theme/LuaThemeEngine.swift, which appends
-- `return json.encode(theme)` after this file runs — every preset script
-- just needs to assign the `theme` table below.

-- Lighten/darken a "#RRGGBB" hex color by `amount` (-1.0 .. 1.0). Positive
-- lightens toward white, negative darkens toward black. Used below to
-- derive the elevated surface tone from the base surface tone instead of
-- hardcoding a third literal that could drift out of sync.
local function shade(hex, amount)
  local r = tonumber(hex:sub(2, 3), 16)
  local g = tonumber(hex:sub(4, 5), 16)
  local b = tonumber(hex:sub(6, 7), 16)
  local function adjust(c)
    if amount >= 0 then
      c = c + (255 - c) * amount
    else
      c = c + c * amount
    end
    c = math.floor(c + 0.5)
    if c < 0 then c = 0 end
    if c > 255 then c = 255 end
    return c
  end
  return string.format("#%02X%02X%02X", adjust(r), adjust(g), adjust(b))
end

local background = "#000000"
local surface = shade(background, 0.05)          -- barely lifted off pure black
local elevated_surface = shade(surface, 0.06)

-- High-visibility accent: bright yellow reads reliably against both the
-- black background and white text, unlike the app's default pink at low
-- brightness settings.
local accent = "#FFD400"
local accent_secondary = "#FFFFFF"

-- A little extra padding room helps hit-targets and legibility — computed
-- here (rather than a bare literal) so the "why 1.15?" reasoning travels
-- with the number.
local base_spacing_scale = 1.0
local accessibility_padding_boost = 0.15
local spacing_scale = base_spacing_scale + accessibility_padding_boost

theme = {
  meta = {
    id = "high_contrast",
    name = "High Contrast",
    description = "Maximum-contrast black/yellow theme with motion disabled — built for low-vision and glare-heavy conditions.",
  },
  colors = {
    accent = accent,
    accent_secondary = accent_secondary,
    text_primary = "#FFFFFF",
    text_secondary = "#E0E0E0",
    background = background,
    surface = surface,
    elevated_surface = elevated_surface,
  },
  style = {
    font_style = "system",
    panel_material = "solid",       -- no translucency — keeps text edges crisp
    launch_screen_style = "minimalist",
    tab_transition_style = "fadeOnly",
    artwork_style = "equalizerCutout",
    seeker_style = "bars",
    card_style = "comfortable",
    panel_opacity = 1.0,
    corner_radius_scale = 0.6,       -- sharper corners read more clearly at a glance
    spacing_scale = spacing_scale,
  },
  glass = {
    tint_strength = 0.0,             -- no glass tint — solid fills only
    tint_hue = 0.0,
    use_accent_tint = false,
    translucency = 1.0,
  },
  flags = {
    reduce_motion = true,
    show_bpm_badges = true,
    aggressive_prefetch = false,
    haptic_feedback = true,          -- haptics are a useful non-visual signal here
  },
  hooks = {
    library_default_sort = "title",
    pin_favorites_first = false,
    library_default_columns = 1,     -- single column reads more reliably than a grid
  },
}
