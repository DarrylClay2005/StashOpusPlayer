-- Monochrome Editorial — grayscale, editorial, serif preset.
--
-- White-on-charcoal grayscale only — no hue anywhere, including the accent
-- itself (pure white, at maximum contrast against the dark surfaces) — a
-- serif face, a sharp/minimal card style, and no glass tint at all, aiming
-- for a print-magazine, "content first" feel.

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

-- Build every color from a single gray value + shade() so the whole palette
-- is provably monochrome (r == g == b for every layer) rather than trusting
-- separately hand-picked hex literals to happen to match.
local base_gray = "#121212"
local surface = shade(base_gray, 0.20)
local elevated_surface = shade(base_gray, 0.35)

local accent = "#FFFFFF"
local accent_secondary = shade(base_gray, 0.55) -- mid-gray secondary, never a hue

theme = {
  meta = {
    id = "monochrome_editorial",
    name = "Monochrome Editorial",
    description = "Strict grayscale, serif type, sharp corners — a print-magazine, content-first look.",
  },
  colors = {
    accent = accent,
    accent_secondary = accent_secondary,
    text_primary = "#F2F2F2",
    text_secondary = "#9A9A9A",
    background = base_gray,
    surface = surface,
    elevated_surface = elevated_surface,
  },
  style = {
    font_style = "serif",
    panel_material = "solid",
    launch_screen_style = "minimalist",
    tab_transition_style = "fadeOnly",
    artwork_style = "mosaicShatter",
    seeker_style = "classic",
    card_style = "minimal",
    panel_opacity = 1.0,
    corner_radius_scale = 0.5,
    spacing_scale = 1.15,
  },
  glass = {
    tint_strength = 0.0,
    tint_hue = 0.0,
    use_accent_tint = false,
    translucency = 1.0,
  },
  flags = {
    reduce_motion = true,
    show_bpm_badges = false,
    aggressive_prefetch = false,
    haptic_feedback = false,
  },
  hooks = {
    library_default_sort = "artist",
    pin_favorites_first = false,
    library_default_columns = 1,
  },
}
