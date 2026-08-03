-- Monochrome Pulse — a single-hue LIGHTNS ramp (one hue, only L varies from
-- dark to light) rather than a hue-walk (aurora_wave) or a 2-color lerp
-- (sunset_bars). Pairs naturally with the monochrome_editorial theme
-- preset, which currently has no matching visualizer.

local function hsl_to_hex(h, s, l)
  local c = (1 - math.abs(2 * l - 1)) * s
  local x = c * (1 - math.abs((h / 60) % 2 - 1))
  local m = l - c / 2
  local r, g, b = 0, 0, 0
  if h < 60 then r, g, b = c, x, 0
  elseif h < 120 then r, g, b = x, c, 0
  elseif h < 180 then r, g, b = 0, c, x
  elseif h < 240 then r, g, b = 0, x, c
  elseif h < 300 then r, g, b = x, 0, c
  else r, g, b = c, 0, x end
  local function to255(v) return math.floor((v + m) * 255 + 0.5) end
  return string.format("#%02X%02X%02X", to255(r), to255(g), to255(b))
end

local hue = 0        -- 0 = neutral grayscale (s = 0 below)
local stops = 5
local colors = {}
for i = 1, stops do
  local l = 0.18 + (0.75 - 0.18) * (i - 1) / (stops - 1)
  colors[i] = hsl_to_hex(hue, 0.0, l)
end

visualizer = {
  colors = colors,
  sensitivity = 0.9,
  bar_corner_radius = 1,
  bar_spacing = 2,
  mirrored = false,
}
