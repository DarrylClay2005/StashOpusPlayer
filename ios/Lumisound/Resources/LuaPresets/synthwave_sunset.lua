-- Synthwave Sunset — retrowave pink & orange gradient preset.
--
-- Deep purple night sky background with a pink-to-orange "sunset" accent
-- gradient (paired via the app's existing dynamic-accent-gradient
-- mechanism), the dedicated synthwave-horizon artwork style, and a digital
-- seeker to complete the 80s-retrofuturist look — distinct from both
-- Cyberpunk Neon's cooler magenta/cyan HUD feel and Vibrant Pulse's
-- brighter violet.

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

local background = "#1B0A2E"
local surface = shade(background, 0.22)
local elevated_surface = shade(background, 0.35)

local accent = "#FF6AD5"          -- sunset pink
local accent_secondary = "#FFB86B" -- sunset orange

theme = {
  meta = {
    id = "synthwave_sunset",
    name = "Synthwave Sunset",
    description = "Pink-to-orange sunset gradient over a deep purple night sky — retrowave, 80s-inspired.",
  },
  colors = {
    accent = accent,
    accent_secondary = accent_secondary,
    text_primary = "#FFF0F7",
    text_secondary = "#E5A8C9",
    background = background,
    surface = surface,
    elevated_surface = elevated_surface,
  },
  style = {
    font_style = "rounded",
    panel_material = "frostedGlass",
    launch_screen_style = "aurora",
    tab_transition_style = "slide",
    artwork_style = "synthwaveHorizon",
    seeker_style = "digital",
    card_style = "card",
    panel_opacity = 0.85,
    corner_radius_scale = 1.2,
    spacing_scale = 1.0,
  },
  glass = {
    tint_strength = 0.3,
    tint_hue = 0.95,
    use_accent_tint = true,
    translucency = 0.9,
  },
  flags = {
    reduce_motion = false,
    show_bpm_badges = true,
    aggressive_prefetch = true,
    haptic_feedback = true,
  },
  hooks = {
    library_default_sort = "dateAdded",
    pin_favorites_first = true,
    library_default_columns = 2,
  },
}
