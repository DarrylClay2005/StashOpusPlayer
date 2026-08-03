-- Solar Daylight — a genuinely bright, high-key preset. minimalist and
-- pastel_dream are both muted/soft; this one commits to a true near-white
-- background with deep-navy text and a gold accent, for outdoor/daylight
-- readability none of the other 10 presets target.

local background = "#FFFDF7"
local surface = "#FFF6E0"
local elevated_surface = "#FFEFC7"

local accent = "#D89A00"
local accent_secondary = "#1B2A4A"

theme = {
  meta = {
    id = "solar_daylight",
    name = "Solar Daylight",
    description = "Near-white and gold, built for bright outdoor/daylight readability — brighter and higher-contrast than the muted minimalist or pastel presets.",
  },
  colors = {
    accent = accent,
    accent_secondary = accent_secondary,
    text_primary = "#1B2A4A",
    text_secondary = "#6B6250",
    background = background,
    surface = surface,
    elevated_surface = elevated_surface,
  },
  style = {
    font_style = "rounded",
    panel_material = "solid",
    launch_screen_style = "minimalist",
    tab_transition_style = "scalePop",
    artwork_style = "paperLayersParallax",
    seeker_style = "pill",
    card_style = "comfortable",
    panel_opacity = 1.0,
    corner_radius_scale = 1.15,
    spacing_scale = 1.05,
  },
  glass = {
    tint_strength = 0.05,
    tint_hue = 0.12,
    use_accent_tint = false,
    translucency = 1.0,
  },
  flags = {
    reduce_motion = false,
    show_bpm_badges = false,
    aggressive_prefetch = false,
    haptic_feedback = true,
  },
  hooks = {
    library_default_sort = "title",
    pin_favorites_first = true,
    library_default_columns = 2,
  },
}
