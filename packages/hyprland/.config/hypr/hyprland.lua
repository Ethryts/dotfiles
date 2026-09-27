-- Ubuntu profile, using the native Hyprland 0.55 Lua API.
hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")
hl.env("HYPRSHOT_DIR", os.getenv("HOME") .. "/Pictures/Screenshots")
hl.config({ misc = { disable_splash_rendering = true } })

require("config.monitors")
require("config.input")
require("config.windows")
require("config.visual")

hl.on("hyprland.start", function()
  for _, command in ipairs({
    "command -v quickshell >/dev/null && quickshell --no-duplicate --daemonize",
    "command -v hyprpaper >/dev/null && hyprpaper",
    "command -v hypridle >/dev/null && command -v hyprlock >/dev/null && hypridle",
    "command -v wl-paste >/dev/null && command -v cliphist >/dev/null && wl-paste --type text --watch cliphist store",
    "command -v wl-paste >/dev/null && command -v cliphist >/dev/null && wl-paste --type image --watch cliphist store",
  }) do
    hl.exec_cmd(command)
  end
end)
