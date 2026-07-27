-- Sunset Bars — warm orange-to-pink gradient with punchier, more sensitive
-- bars (louder-reading response) and a mirrored layout, computed from a
-- simple linear interpolation between two endpoint colors rather than
-- hand-picked mid-stops.

local function lerp(a, b, t) return a + (b - a) * t end

local function mix_hex(hex_a, hex_b, t)
  local function channel(hex, i) return tonumber(hex:sub(i, i + 1), 16) end
  local r = math.floor(lerp(channel(hex_a, 2), channel(hex_b, 2), t) + 0.5)
  local g = math.floor(lerp(channel(hex_a, 4), channel(hex_b, 4), t) + 0.5)
  local b = math.floor(lerp(channel(hex_a, 6), channel(hex_b, 6), t) + 0.5)
  return string.format("#%02X%02X%02X", r, g, b)
end

local from_color = "#FF6A00"  -- deep orange
local to_color = "#FF2AA6"    -- hot pink

local colors = {}
local stops = 4
for i = 1, stops do
  colors[i] = mix_hex(from_color, to_color, (i - 1) / (stops - 1))
end

visualizer = {
  colors = colors,
  sensitivity = 1.35,
  bar_corner_radius = 4,
  bar_spacing = 5,
  mirrored = true,
}
