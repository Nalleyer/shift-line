-- Shared palette, virtual resolution (384x288), and layout coordinates.
local Theme = {}

Theme.W = 384
Theme.H = 288
Theme.SCALE = 3

Theme.C = {
  ink    = { 0.043, 0.055, 0.078 }, -- #0B0E14  background
  shade  = { 0.071, 0.102, 0.137 }, -- #121A23  panel fill
  panel  = { 0.094, 0.137, 0.176 }, -- #18232D  raised fill
  line   = { 0.173, 0.251, 0.325 }, -- #2C4053  borders
  dim    = { 0.353, 0.443, 0.525 }, -- #5A7186  secondary text
  paper  = { 0.788, 0.839, 0.886 }, -- #C9D6E2  primary text
  white  = { 0.949, 0.969, 0.988 }, -- #F2F7FC
  red    = { 1.000, 0.302, 0.278 }, -- #FF4D47  enemies / damage / core
  red_dk = { 0.560, 0.133, 0.149 }, -- #8E2226
  amber  = { 1.000, 0.769, 0.325 }, -- #FFC453  warnings / selection
  green  = { 0.357, 0.878, 0.557 }, -- #5BE08E  healing
  purple = { 0.741, 0.490, 1.000 },
  blue   = { 0.349, 0.659, 1.000 }, -- #59A8FF  shields / info
}

Theme.COLS = 6
Theme.COL_X0 = 28
Theme.COL_STEP = 56
Theme.PANEL_W = 48
Theme.PANEL_H = 70

Theme.TOP_H = 22
Theme.ENEMY_Y = 28
Theme.FRONT_Y = 106
Theme.PLAYER_Y = 114

Theme.BTN_Y = 200
Theme.BTN_H = 28
Theme.HINT_Y = 235
Theme.FOOT_Y = 254

function Theme.col_x(i)
  return Theme.COL_X0 + (i - 1) * Theme.COL_STEP
end

function Theme.col_cx(i)
  return Theme.col_x(i) + Theme.PANEL_W / 2
end

function Theme.gap_cx(i)
  return Theme.col_x(i) - 4
end

return Theme
