local monitors = {
  main = "desc:LG Electronics LG ULTRAGEAR 203MXRF4D934",
  secondary = "desc:LG Electronics LG ULTRAGEAR 401MXSK4D438",
}
hl.monitor({ output = monitors.secondary, mode = "preferred", position = "0x0", scale = "auto", transform = 1 })
hl.monitor({ output = monitors.main, mode = "preferred", position = "1440x675", scale = "auto" })
-- Covers the new laptop panel without assuming its connector or pixel density.
hl.monitor({ output = "", mode = "preferred", position = "2720x2115", scale = "auto" })
-- After checking hyprctl monitors, an explicit laptop position can go here.
return monitors
