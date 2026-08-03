-- Deep Ocean — the first blue-accent preset (existing 10 use cyan, magenta,
-- green, yellow, gray, white, lavender, orange/brown, pink-orange, and
-- pink/purple, but none commit to a true blue). Near-black navy background
-- with a bright oceanic blue accent, paired with the bioluminescentTide
-- artwork style (an existing style with no preset currently pairing it).

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

local background = "#020C18"
local surface = shade(background, 0.25)
local elevated_surface = shade(background, 0.4)

local accent = "#2E9EFF"
local accent_secondary = "#00E0C6"

theme = {
  meta = {
    id = "deep_ocean",
    name = "Deep Ocean",
    description = "Bright oceanic blue and teal over a near-black navy depth — calm, cool, and deliberately different from every warm/neutral preset here.",
  },
  colors = {
    accent = accent,
    accent_secondary = accent_secondary,
    text_primary = "#EAF6FF",
    text_secondary = "#7FA8C9",
    background = background,
    surface = surface,
    elevated_surface = elevated_surface,
  },
  style = {
    font_style = "system",
    panel_material = "frostedGlass",
    launch_screen_style = "aurora",
    tab_transition_style = "fadeOnly",
    artwork_style = "bioluminescentTide",
    seeker_style = "waveform",
    card_style = "comfortable",
    panel_opacity = 0.88,
    corner_radius_scale = 1.05,
    spacing_scale = 1.0,
  },
  glass = {
    tint_strength = 0.25,
    tint_hue = 0.58,
    use_accent_tint = true,
    translucency = 0.85,
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
