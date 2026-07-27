-- Vibrant Pulse — bright, bold, high-energy preset.
--
-- Deep violet background so the hot pink/amber accents pop, rounded font
-- for a friendly feel, frosted glass + heavy tint for a "glowing" chrome
-- look, and every behavior flag turned up: motion on, BPM badges on,
-- aggressive prefetch on (favorites-pinned + play-count sort assumes the
-- user is actively jumping around a lot).

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

local background = "#1A0B2E"
local surface = shade(background, 0.25)
local elevated_surface = shade(surface, 0.20)

local accent = "#FF3D7A"
local accent_secondary = "#FFB800"

-- Glass tint strength scales with how "energetic" this preset wants to feel
-- — kept as a named variable rather than a bare literal in the table below.
local energy_level = 0.35

theme = {
  meta = {
    id = "vibrant_energetic",
    name = "Vibrant Pulse",
    description = "Hot pink & amber over deep violet, rounded type, heavy glass glow — built for energetic, hands-on listening sessions.",
  },
  colors = {
    accent = accent,
    accent_secondary = accent_secondary,
    text_primary = "#FFFFFF",
    text_secondary = "#FFD9E8",
    background = background,
    surface = surface,
    elevated_surface = elevated_surface,
  },
  style = {
    font_style = "rounded",
    panel_material = "frostedGlass",
    launch_screen_style = "aurora",
    tab_transition_style = "scalePop",
    artwork_style = "discoMirrorBall",
    seeker_style = "ring",
    card_style = "card",
    panel_opacity = 0.9,
    corner_radius_scale = 1.3,
    spacing_scale = 1.0,
  },
  glass = {
    tint_strength = energy_level,
    tint_hue = 0.9,
    use_accent_tint = true,
    translucency = 1.0,
  },
  flags = {
    reduce_motion = false,
    show_bpm_badges = true,
    aggressive_prefetch = true,
    haptic_feedback = true,
  },
  hooks = {
    library_default_sort = "playCount",
    pin_favorites_first = true,
    library_default_columns = 2,
  },
}
