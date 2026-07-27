-- Neon Cyberdeck — dark, neon, monospaced preset.
--
-- Near-black indigo background, hot magenta/cyan neon accent pairing,
-- monospaced type (the one preset that uses it, matching a "terminal/HUD"
-- identity), a neon-line seeker, and the heaviest glass tint of any preset
-- here — every "loud" flag on, matching a fast, alert, high-energy feel
-- distinct from Vibrant Pulse's warmer, friendlier energy.

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

local background = "#060014"
local surface = shade(background, 0.10)
local elevated_surface = shade(background, 0.22)

local accent = "#FF2AF0"
local accent_secondary = "#2AFCFF"

-- Neon intensity drives glass tint strength directly — the brightest of
-- every preset in this set.
local neon_intensity = 0.4

theme = {
  meta = {
    id = "cyberpunk_neon",
    name = "Neon Cyberdeck",
    description = "Near-black indigo with magenta/cyan neon and monospaced type — a fast, alert, terminal-HUD look.",
  },
  colors = {
    accent = accent,
    accent_secondary = accent_secondary,
    text_primary = "#E8FFFB",
    text_secondary = "#7FD8D6",
    background = background,
    surface = surface,
    elevated_surface = elevated_surface,
  },
  style = {
    font_style = "monospacedDisplay",
    panel_material = "frostedGlass",
    launch_screen_style = "aurora",
    tab_transition_style = "scalePop",
    artwork_style = "circuitPulse",
    seeker_style = "neonLine",
    card_style = "card",
    panel_opacity = 0.85,
    corner_radius_scale = 0.7,
    spacing_scale = 1.0,
  },
  glass = {
    tint_strength = neon_intensity,
    tint_hue = 0.85,
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
