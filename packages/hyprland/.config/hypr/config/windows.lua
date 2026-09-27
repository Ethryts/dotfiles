local monitors = require("config.monitors")
for i = 1, 4 do
    hl.workspace_rule({ workspace = tostring(i), monitor = i <= 2 and monitors.main or monitors.secondary,
        persistent = true, on_created_empty = i == 1 and "kitty" or "firefox" })
end
for name, command in pairs({ media = "spotify", chat = "signal-desktop", steam = "steam" }) do
    hl.workspace_rule({ workspace = "special:" .. name, on_created_empty = "command -v " .. command .. " >/dev/null && " .. command })
end
for _, spec in ipairs({
    { "Spotify", "^(Spotify|spotify)$", "media" },
    { "Signal", "^(Signal|signal|signal-desktop)$", "chat" },
    { "Discord", "^(discord|Discord|vesktop|Vesktop)$", "chat" },
    { "Steam", "^(steam)$", "steam" },
}) do
    hl.window_rule({ name = spec[1] .. " scratchpad", match = { class = spec[2] }, workspace = "special:" .. spec[3] .. " silent" })
end
for _, name in ipairs({ "magic", "media", "chat", "steam" }) do
    hl.window_rule({ name = "Floating " .. name, match = { workspace = "special:" .. name }, float = true })
end
hl.window_rule({ name = "Steam games", match = { class = "^(steam_app_.*)$" }, workspace = "5" })
hl.window_rule({ name = "No maximize", match = { class = ".*" }, suppress_event = "maximize" })
hl.window_rule({ name = "Browser popups", match = { title = "^(.*bitwarden.*)$" }, float = true })
hl.window_rule({ name = "XWayland drag fix", match = { xwayland = true, float = true, fullscreen = false, pin = false }, suppress_event = "move" })
hl.window_rule({ name = "Opaque browsers", match = { class = "^(firefox|Chromium|Brave-browser|Google-chrome|Vivaldi|Microsoft-edge)$" }, opaque = true })
hl.window_rule({ name = "Float utilities", match = { class = "^(blueman-manager|.*pavucontrol|nm-connection-editor)$" }, float = true,
    size = "600 300", move = "(cursor_x-window_w) (cursor_y)" })
