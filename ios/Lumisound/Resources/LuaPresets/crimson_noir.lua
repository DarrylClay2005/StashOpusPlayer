-- Crimson Noir — the first red-accent preset (no existing preset uses red
-- as its primary color). Deep black background with a blood-red accent for
-- a phonk/Memphis-rap aesthetic, pairing with the vhsScanGlitch artwork
-- style (currently unused by any preset) and a sharper corner scale than
-- any of the 10 existing presets use.

local background = "#050000"
local surface = "#140404"
local elevated_surface = "#220707"

local accent = "#C4102B"
local accent_secondary = "#7A0E1E"

theme = {
  meta = {
    id = "crimson_noir",
    name = "Crimson Noir",
    description = "Blood-red accent on near-pure black — a harsh, high-contrast phonk/Memphis-rap look distinct from every warmer or cooler preset here.",
  },
  colors = {
    accent = accent,
    accent_secondary = accent_secondary,
    text_primary = "#F5E6E6",
    text_secondary = "#9E6E6E",
    background = background,
    surface = surface,
    elevated_surface = elevated_surface,
  },
  style = {
    font_style = "monospacedDisplay",
    panel_material = "solid",
    launch_screen_style = "minimalist",
    tab_transition_style = "fadeOnly",
    artwork_style = "vhsScanGlitch",
    seeker_style = "neonLine",
    card_style = "compact",
    panel_opacity = 1.0,
    corner_radius_scale = 0.6,
    spacing_scale = 0.95,
  },
  glass = {
    tint_strength = 0.15,
    tint_hue = 0.0,
    use_accent_tint = true,
    translucency = 0.95,
  },
  flags = {
    reduce_motion = false,
    show_bpm_badges = true,
    aggressive_prefetch = false,
    haptic_feedback = true,
  },
  hooks = {
    library_default_sort = "dateAdded",
    pin_favorites_first = false,
    library_default_columns = 1,
  },
}
