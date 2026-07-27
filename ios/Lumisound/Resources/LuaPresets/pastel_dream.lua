-- Pastel Dream — soft lavender, gentle-motion preset.
--
-- The second (and much softer/more colorful) of the two light-background
-- identities in this preset set — Minimalist is stark black-on-cream ink,
-- this is soft lavender-on-white with a pink accent pairing and heavier
-- frosted glass, aimed at feeling calm rather than plain.

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

local background = "#F5EEFB"
local surface = "#FFFFFF"
local elevated_surface = shade(background, -0.03)

local accent = "#B497D6"
local accent_secondary = "#F7B7C5"

-- Softness score just gates how strongly favorites get pinned to the top —
-- a real (if small) example of a preset's own logic feeding into a hook
-- value rather than a hand-picked literal.
local softness = 0.8
local pin_favorites_first = softness > 0.5

theme = {
  meta = {
    id = "pastel_dream",
    name = "Pastel Dream",
    description = "Soft lavender over white, pink accent, heavy frosted glass — gentle motion throughout.",
  },
  colors = {
    accent = accent,
    accent_secondary = accent_secondary,
    text_primary = "#4A4458",
    text_secondary = "#8A8299",
    background = background,
    surface = surface,
    elevated_surface = elevated_surface,
  },
  style = {
    font_style = "rounded",
    panel_material = "frostedGlass",
    launch_screen_style = "aurora",
    tab_transition_style = "scalePop",
    artwork_style = "kaleidoscopeBloom",
    seeker_style = "pill",
    card_style = "comfortable",
    panel_opacity = 0.8,
    corner_radius_scale = 1.6,
    spacing_scale = 1.1,
  },
  glass = {
    tint_strength = 0.25,
    tint_hue = 0.78,
    use_accent_tint = true,
    translucency = 0.7,
  },
  flags = {
    reduce_motion = false,
    show_bpm_badges = false,
    aggressive_prefetch = false,
    haptic_feedback = true,
  },
  hooks = {
    library_default_sort = "title",
    pin_favorites_first = pin_favorites_first,
    library_default_columns = 2,
  },
}
