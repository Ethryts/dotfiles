hl.config({
    general = { gaps_in = 5, gaps_out = 20, border_size = 2, resize_on_border = false, allow_tearing = false, layout = "dwindle",
        col = { active_border = { colors = { "rgba(98c379ff)", "rgba(56b6c2ff)" }, angle = 90 }, inactive_border = "rgba(595959aa)" } },
    decoration = { rounding = 10, rounding_power = 2, active_opacity = 0.98, inactive_opacity = 0.95,
        shadow = { enabled = true, range = 6, render_power = 2, color = "rgba(1a1a1aee)" },
        blur = { enabled = true, size = 3, passes = 1, new_optimizations = true, vibrancy = 1 } },
    animations = { enabled = true },
    dwindle = { preserve_split = true }, master = { new_status = "master" },
    misc = { force_default_wallpaper = -1, disable_hyprland_logo = false },
})
for name, points in pairs({ easeOutQuint = {{0.23, 1}, {0.32, 1}}, easeInOutCubic = {{0.65, 0.05}, {0.36, 1}},
    linear = {{0, 0}, {1, 1}}, almostLinear = {{0.5, 0.5}, {0.75, 1}}, quick = {{0.15, 0}, {0.1, 1}} }) do
    hl.curve(name, { type = "bezier", points = points })
end
for _, a in ipairs({
    {"global", 10, "default"}, {"border", 5.39, "easeOutQuint"}, {"windows", 4.79, "easeOutQuint"},
    {"windowsIn", 4.1, "easeOutQuint", "popin 87%"}, {"windowsOut", 1.49, "linear", "popin 87%"},
    {"fadeIn", 1.73, "almostLinear"}, {"fadeOut", 1.46, "almostLinear"}, {"fade", 3.03, "quick"},
    {"layers", 3.81, "easeOutQuint"}, {"layersIn", 4, "easeOutQuint", "fade"}, {"layersOut", 1.5, "linear", "fade"},
    {"fadeLayersIn", 1.79, "almostLinear"}, {"fadeLayersOut", 1.39, "almostLinear"},
    {"workspaces", 1.94, "almostLinear", "fade"}, {"workspacesIn", 1.21, "almostLinear", "fade"},
    {"workspacesOut", 1.94, "almostLinear", "fade"}, {"zoomFactor", 7, "quick"},
}) do hl.animation({ leaf = a[1], enabled = true, speed = a[2], bezier = a[3], style = a[4] }) end
hl.workspace_rule({ workspace = "w[tv1]", gaps_out = 0, gaps_in = 0 })
hl.workspace_rule({ workspace = "f[1]", gaps_out = 0, gaps_in = 0 })
