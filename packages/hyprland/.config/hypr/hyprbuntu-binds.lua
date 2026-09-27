-- Notifications (swaync)
hl.bind("SUPER + COMMA", hl.dsp.exec_cmd("swaync-client --close-latest"), { description = "Dismiss last notification" })
hl.bind("SUPER + SHIFT + COMMA", hl.dsp.exec_cmd("swaync-client --close-all"), { description = "Dismiss all notifications" })
hl.bind("SUPER + CTRL + COMMA", hl.dsp.exec_cmd("swaync-client --toggle-panel"), { description = "Open notifications panel" })
hl.bind("SUPER + ALT + COMMA", hl.dsp.exec_cmd("swaync-client --toggle-dnd && swaync-client --get-dnd | grep -q 'true' && notify-send 'Silenced notifications' || notify-send 'Enabled notifications'"), { description = "Toggle silencing notifications" })

-- Screenshots
local hyprshot = os.getenv("HOME") .. "/.local/bin/hyprshot"
hl.bind("PRINT", hl.dsp.exec_cmd(hyprshot .. " -m region"), { description = "Region screenshot" })
hl.bind("ALT + PRINT", hl.dsp.exec_cmd(hyprshot .. " -m window"), { description = "Window screenshot" })
hl.bind("SHIFT + PRINT", hl.dsp.exec_cmd(hyprshot .. " -m output"), { description = "Monitor screenshot" })

-- Multimedia keys for media, volume and screen brightness (with SwayOSD)
-- These have been disabled since the default ~/.config/hypr/hyprland.lua already binds these
-- To activate swayosd, remove the duplicate XF86* binds from hyprland.lua and uncomment the following
--hl.bind("XF86AudioNext", hl.dsp.exec_cmd("swayosd-client --playerctl next"), { locked = true, description = "Next track" })
--hl.bind("XF86AudioPause", hl.dsp.exec_cmd("swayosd-client --playerctl play-pause"), { locked = true, description = "Pause" })
--hl.bind("XF86AudioPlay", hl.dsp.exec_cmd("swayosd-client --playerctl play-pause"), { locked = true, description = "Play" })
--hl.bind("XF86AudioPrev", hl.dsp.exec_cmd("swayosd-client --playerctl previous"), { locked = true, description = "Previous track" })

--hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("swayosd-client --output-volume raise"), { locked = true, repeating = true, description = "Volume up" })
--hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("swayosd-client --output-volume lower"), { locked = true, repeating = true, description = "Volume down" })
--hl.bind("XF86AudioMute", hl.dsp.exec_cmd("swayosd-client --output-volume mute-toggle"), { locked = true, repeating = true, description = "Mute" })
--hl.bind("XF86AudioMicMute", hl.dsp.exec_cmd("swayosd-client --input-volume mute-toggle"), { locked = true, repeating = true, description = "Mute microphone" })

--hl.bind("XF86MonBrightnessUp", hl.dsp.exec_cmd("swayosd-client --brightness raise"), { locked = true, repeating = true, description = "Brightness up" })
--hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("swayosd-client --brightness lower"), { locked = true, repeating = true, description = "Brightness down" })

