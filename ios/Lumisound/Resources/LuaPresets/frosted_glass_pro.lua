-- Frosted Glass Pro — pushes the "glass" mechanism harder than any of the
-- 10 existing presets: all of them keep panel_opacity >= 0.8 and modest
-- translucency, so none feel truly glass-forward. This one drops opacity
-- and tint_strength low with translucency at its max, for a near-transparent
-- panel look, paired with a neutral silver/graphite accent (no other preset
-- uses an achromatic accent).

local background = "#101214"
local surface = "#1B1E21"
local elevated_surface = "#26292D"

local accent = "#C7CCD1"
local accent_secondary = "#8A9099"

theme = {
  meta = {
    id = "frosted_glass_pro",
    name = "Frosted Glass Pro",
    description = "Near-transparent frosted panels over graphite, with a neutral silver accent — the most glass-forward preset here, pushing translucency further than any of the other 10.",
  },
  colors = {
    accent = accent,
    accent_secondary = accent_secondary,
    text_primary = "#F2F3F5",
    text_secondary = "#9AA0A6",
    background = background,
    surface = surface,
    elevated_surface = elevated_surface,
  },
  style = {
    font_style = "system",
    panel_material = "frostedGlass",
    launch_screen_style = "aurora",
    tab_transition_style = "slide",
    artwork_style = "frostedIceCrystal",
    seeker_style = "ring",
    card_style = "card",
    panel_opacity = 0.55,
    corner_radius_scale = 1.1,
    spacing_scale = 1.0,
  },
  glass = {
    tint_strength = 0.08,
    tint_hue = 0.6,
    use_accent_tint = false,
    translucency = 1.0,
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
    library_default_columns = 2,
  },
}
