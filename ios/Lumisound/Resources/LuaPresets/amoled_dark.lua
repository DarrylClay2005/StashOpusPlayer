-- AMOLED Midnight — true-black, battery-friendly preset.
--
-- Every background layer is at or extremely close to #000000 (real
-- black pixels draw ~zero power on an OLED panel) with a cool cyan/violet
-- accent pairing for a "midnight console" feel. Deliberately restrained on
-- motion/glass so nothing washes out the true blacks with a translucent
-- overlay.

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

local background = "#000000"
-- Each layer only lifts a couple of percent off pure black — enough for the
-- surface/elevated-surface hierarchy to still read, without meaningfully
-- hurting the OLED power savings that are the whole point of this preset.
local surface = shade(background, 0.02)
local elevated_surface = shade(background, 0.05)

local accent = "#00E5FF"
local accent_secondary = "#7C4DFF"

theme = {
  meta = {
    id = "amoled_dark",
    name = "AMOLED Midnight",
    description = "Near-pure-black at every layer with a cool cyan/violet accent — saves battery on OLED screens, easy on the eyes at night.",
  },
  colors = {
    accent = accent,
    accent_secondary = accent_secondary,
    text_primary = "#F5F5F5",
    text_secondary = "#9E9E9E",
    background = background,
    surface = surface,
    elevated_surface = elevated_surface,
  },
  style = {
    font_style = "system",
    panel_material = "solid",
    launch_screen_style = "minimalist",
    tab_transition_style = "fadeOnly",
    artwork_style = "circuitPulse",
    seeker_style = "digital",
    card_style = "compact",
    panel_opacity = 1.0,
    corner_radius_scale = 0.8,
    spacing_scale = 0.95,
  },
  glass = {
    tint_strength = 0.1,
    tint_hue = 0.55,
    use_accent_tint = true,
    translucency = 0.9,
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
