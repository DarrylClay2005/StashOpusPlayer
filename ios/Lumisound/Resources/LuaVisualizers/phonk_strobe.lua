-- Phonk Strobe — hard, discrete red/black alternation (no interpolation,
-- unlike aurora_wave's hue-walk or sunset_bars' color lerp), square
-- corners, tight spacing, and punchy sensitivity for a harsh
-- phonk/Memphis-rap look.

local red = "#B4001E"
local black = "#0A0A0A"

local stops = 6
local colors = {}
for i = 1, stops do
  colors[i] = (i % 2 == 1) and red or black
end

visualizer = {
  colors = colors,
  sensitivity = 1.5,
  bar_corner_radius = 0,
  bar_spacing = 1,
  mirrored = true,
}
