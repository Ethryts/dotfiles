hl.config({ input = {
    kb_layout = "us", kb_options = "ctrl:nocaps", follow_mouse = 1,
    sensitivity = -0.1, accel_profile = "flat",
    touchpad = { natural_scroll = true },
} })

local function exec(key, command, options)
    hl.bind(key, hl.dsp.exec_cmd(command), options)
end
exec("SUPER + Q", "kitty")
exec("SUPER + E", "nautilus")
exec("SUPER + R", "quickshell ipc call launcher toggleFocused")
exec("SUPER + CONTROL + V", "cliphist list | rofi -dmenu -display-columns 2 | cliphist decode | wl-copy")
exec("SUPER + CONTROL + S", "mkdir -p \"$HOME/Pictures/Screenshots\" && hyprshot -m region")
hl.bind("SUPER + C", function()
    local window = hl.get_active_window()
    if not window then return end
    local name = window.workspace and window.workspace.name or ""
    if name == "special:media" or name == "special:chat" or name == "special:steam" then
        hl.dispatch(hl.dsp.workspace.toggle_special(name:sub(9)))
    else
        hl.dispatch(hl.dsp.window.close())
    end
end)
hl.bind("SUPER + V", hl.dsp.window.float({ action = "toggle" }))
hl.bind("SUPER + P", hl.dsp.window.pseudo())
hl.bind("SUPER + F", hl.dsp.window.fullscreen({ mode = "maximized" }))
hl.bind("SUPER + F12", hl.dsp.window.fullscreen({ mode = "fullscreen" }))
for key, direction in pairs({ H = "left", L = "right", K = "up", J = "down" }) do
    hl.bind("SUPER + " .. key, hl.dsp.focus({ direction = direction }))
    hl.bind("SUPER + CONTROL + " .. key, hl.dsp.window.move({ direction = direction }))
    hl.bind("SUPER + SHIFT + " .. key, hl.dsp.workspace.move({ monitor = direction }))
end
for i = 1, 10 do
    hl.bind("SUPER + " .. i % 10, hl.dsp.focus({ workspace = i }))
    hl.bind("SUPER + SHIFT + " .. i % 10, hl.dsp.window.move({ workspace = i, follow = true }))
end
for _, spec in ipairs({ { "S", "S", "magic" }, { "Y", "M", "media" }, { "U", "U", "chat" }, { "I", "I", "steam" } }) do
    local name = spec[3]
    hl.bind("SUPER + " .. spec[1], hl.dsp.workspace.toggle_special(name))
    hl.bind("SUPER + SHIFT + " .. spec[2], function()
        hl.dispatch(hl.dsp.window.float({ action = "set" }))
        hl.dispatch(hl.dsp.window.move({ workspace = "special:" .. name, follow = true }))
    end)
end
hl.bind("SUPER + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
hl.bind("SUPER + mouse_up", hl.dsp.focus({ workspace = "e-1" }))
hl.bind("SUPER + mouse:272", hl.dsp.window.drag(), { mouse = true })
hl.bind("SUPER + mouse:273", hl.dsp.window.resize(), { mouse = true })
for key, command in pairs({
    XF86AudioRaiseVolume = "bash ~/.config/quickshell/scripts/audio.sh up",
    XF86AudioLowerVolume = "bash ~/.config/quickshell/scripts/audio.sh down",
    XF86AudioMute = "bash ~/.config/quickshell/scripts/audio.sh mute",
    XF86AudioMicMute = "wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle",
    XF86MonBrightnessUp = "bash ~/.config/quickshell/scripts/brightness.sh up",
    XF86MonBrightnessDown = "bash ~/.config/quickshell/scripts/brightness.sh down",
}) do exec(key, command, { locked = true, repeating = true }) end
for key, command in pairs({ XF86AudioNext = "next", XF86AudioPause = "play-pause", XF86AudioPlay = "play-pause", XF86AudioPrev = "previous" }) do
    exec(key, "playerctl " .. command, { locked = true })
end
