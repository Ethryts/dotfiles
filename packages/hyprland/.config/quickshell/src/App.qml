import Quickshell
import "./modules"
import "./services"

Scope {
    id: root

    CalendarMenuService { id: calendarMenu }
    LauncherMenuService { id: launcherMenu }
    NotificationService { id: notificationService }
    QuickControlsService { id: quickControlsService }
    NetworkService { id: networkService }
    AudioService { id: audioService }
    BrightnessService { id: brightnessService }
    PowerProfilesService { id: powerProfilesService }
    HyprwhisperService { id: hyprwhisperService }

    Bar {
        calendarController: calendarMenu
        launcherController: launcherMenu
        quickControlsController: quickControlsService
        networkService: networkService
        audioService: audioService
        brightnessService: brightnessService
        powerProfilesService: powerProfilesService
        hyprwhisperService: hyprwhisperService
    }

    CalendarMenu {
        calendarController: calendarMenu
    }

    LauncherMenu {
        launcherController: launcherMenu
    }

    NotificationOverlay {
        notificationService: notificationService
    }

    OverlayModule {}

    HyprwhisperOverlay {
        hyprwhisperService: hyprwhisperService
    }

    QuickControlsMenu {
        quickControlsController: quickControlsService
        networkService: networkService
        audioService: audioService
        brightnessService: brightnessService
        powerProfilesService: powerProfilesService
    }
}
