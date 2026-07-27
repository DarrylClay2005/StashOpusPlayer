-- Minimalist — clean, quiet, paper-light preset.
--
-- The only light-background identity paired with the "paper" family below
-- (Pastel Dream is the other light theme, tuned much softer/more colorful) —
-- near-white surfaces, near-black ink accent, generous rounding, no glass
-- tint, motion reduced. Meant to feel like a stripped-down reading app more
-- than a music player.

local function shade(hex, amount)
  local r = tonumber(hex:sub(2, 3), 16)
  local g = tonumber(hex:sub(4, 5), 16)
  local b = tonumber(hex:sub(6, 7), 16)
  local function adjust(c)
    if amount >= 0 then
      c = c + (255 - c) * amount
    else
      c = c + c * amount
    end
    c = math.floor(c + 0.5)
    if c < 0 then c = 0 end
    if c > 255 then c = 255 end
    return c
  end
  return string.format("#%02X%02X%02X", adjust(r), adjust(g), adjust(b))
end

-- "Paper cream" background — warmer than pure white so long reading/browsing
-- sessions are easier on the eyes, same reasoning e-readers use.
local background = "#F2F1EC"
local surface = shade(background, 0.35)      -- lightened further toward white
local elevated_surface = shade(background, -0.05)

-- Ink-black accent instead of a saturated color — the point of "minimalist"
-- is that almost nothing competes for attention.
local accent = "#2B2B2B"
local accent_secondary = "#8A8A8E"

-- Every "loud" behavior flag stays off for this preset — computed via a
-- small loop (rather than three separate hand-written `false` literals)
-- so the "quiet by design" intent is explicit in the script itself.
local loud_flags = { false, false, false } -- bpm badge, aggressive prefetch, haptics
local any_loud = false
for _, is_loud in ipairs(loud_flags) do
  if is_loud then any_loud = true end
end

theme = {
  meta = {
    id = "minimalist",
    name = "Minimalist",
    description = "Warm paper-white background, ink-black accent, generous rounding — a quiet, distraction-free look.",
  },
  colors = {
    accent = accent,
    accent_secondary = accent_secondary,
    text_primary = "#1C1C1E",
    text_secondary = "#6E6E73",
    background = background,
    surface = surface,
    elevated_surface = elevated_surface,
  },
  style = {
    font_style = "system",
    panel_material = "solid",
    launch_screen_style = "minimalist",
    tab_transition_style = "fadeOnly",
    artwork_style = "equalizerCutout",
    seeker_style = "classic",
    card_style = "minimal",
    panel_opacity = 0.85,
    corner_radius_scale = 1.4,
    spacing_scale = 1.2,
  },
  glass = {
    tint_strength = 0.05,
    tint_hue = 0.0,
    use_accent_tint = false,
    translucency = 0.6,
  },
  flags = {
    reduce_motion = true,
    show_bpm_badges = false,
    aggressive_prefetch = false,
    haptic_feedback = false,
  },
  hooks = {
    library_default_sort = "title",
    pin_favorites_first = false,
    library_default_columns = 1,
  },
}
