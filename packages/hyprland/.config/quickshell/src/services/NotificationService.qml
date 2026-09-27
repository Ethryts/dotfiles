import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Services.Notifications

QtObject {
    id: root

    property int historyLimit: 100
    property int defaultTimeoutMs: 5000
    property int lowUrgencyTimeoutMs: 4000
    property int normalUrgencyTimeoutMs: 5000
    property int criticalUrgencyTimeoutMs: 0
    property var notificationHistory: []
    property var screenByNotificationId: ({})
    property var createdAtByNotificationId: ({})
    property var updatedAtByNotificationId: ({})
    property var connectedNotificationsById: ({})

    readonly property var activeNotifications: server.trackedNotifications
        ? (server.trackedNotifications.values || [])
        : []

    function focusedScreen() {
        const screens = Quickshell.screens || [];
        const focusedMonitor = Hyprland.focusedMonitor;

        if (focusedMonitor) {
            for (let i = 0; i < screens.length; ++i) {
                const screen = screens[i];
                if (Hyprland.monitorFor(screen) === focusedMonitor) {
                    return screen;
                }
            }
        }

        return screens.length > 0 ? screens[0] : null;
    }

    function screenForNotification(notificationId) {
        return root.screenByNotificationId[notificationId] || null;
    }

    function stringValue(value) {
        return value === undefined || value === null ? "" : String(value);
    }

    function screenNameForNotification(notificationId) {
        const screen = root.screenForNotification(notificationId);
        return screen ? screen.name : "";
    }

    function desktopEntryForNotification(notification) {
        const desktopEntryId = root.stringValue(notification ? notification.desktopEntry : "");
        if (!desktopEntryId.length) {
            return null;
        }

        return Quickshell.DesktopEntries.byId(desktopEntryId);
    }

    function iconSourceForNotification(notification) {
        const explicitIcon = root.stringValue(notification ? notification.appIcon : "");
        if (explicitIcon.length) {
            return Quickshell.iconPath(explicitIcon, "");
        }

        const desktopEntry = root.desktopEntryForNotification(notification);
        const desktopIcon = desktopEntry ? root.stringValue(desktopEntry.icon) : "";
        if (desktopIcon.length) {
            return Quickshell.iconPath(desktopIcon, "");
        }

        return "";
    }

    function imageSourceForNotification(notification) {
        return root.stringValue(notification ? notification.image : "");
    }

    function actionDataForNotification(notification) {
        const output = [];
        const notificationActions = notification && notification.actions ? notification.actions : [];

        for (let i = 0; i < notificationActions.length; ++i) {
            const action = notificationActions[i];
            output.push({
                identifier: root.stringValue(action.identifier),
                text: root.stringValue(action.text)
            });
        }

        return output;
    }

    function defaultActionIdentifier(notification) {
        const actions = root.actionDataForNotification(notification);
        for (let i = 0; i < actions.length; ++i) {
            if (actions[i].identifier === "default") {
                return "default";
            }
        }

        return "";
    }

    function effectiveTimeoutForNotification(notification) {
        if (!notification) {
            return root.defaultTimeoutMs;
        }

        if (notification.expireTimeout === 0) {
            return 0;
        }

        if (notification.expireTimeout > 0) {
            return Math.round(notification.expireTimeout);
        }

        switch (notification.urgency) {
        case NotificationUrgency.Critical:
            return root.criticalUrgencyTimeoutMs;
        case NotificationUrgency.Low:
            return root.lowUrgencyTimeoutMs;
        default:
            return root.normalUrgencyTimeoutMs;
        }
    }

    function groupKeyForNotification(notification) {
        const desktopEntry = root.stringValue(notification ? notification.desktopEntry : "");
        const appName = root.stringValue(notification ? notification.appName : "");
        const summary = root.stringValue(notification ? notification.summary : "");
        const body = root.stringValue(notification ? notification.body : "");

        return [desktopEntry, appName, summary, body].join("\u001f");
    }

    function presentationForNotification(notification, reason) {
        const createdAt = root.createdAtByNotificationId[notification.id] || Date.now();
        const updatedAt = root.updatedAtByNotificationId[notification.id] || Date.now();
        const appName = root.stringValue(notification.appName);
        const summary = root.stringValue(notification.summary);
        const body = root.stringValue(notification.body);
        const defaultAction = root.defaultActionIdentifier(notification);

        return {
            id: notification.id,
            raw: notification,
            screen: root.screenForNotification(notification.id),
            screenName: root.screenNameForNotification(notification.id),
            groupKey: root.groupKeyForNotification(notification),
            appName: appName,
            appLabel: appName.length ? appName : "Notification",
            summary: summary,
            body: body,
            urgency: notification.urgency,
            timeoutMs: root.effectiveTimeoutForNotification(notification),
            persistent: root.effectiveTimeoutForNotification(notification) === 0,
            appIconName: root.stringValue(notification.appIcon),
            iconSource: root.iconSourceForNotification(notification),
            imageSource: root.imageSourceForNotification(notification),
            desktopEntry: root.stringValue(notification.desktopEntry),
            resident: notification.resident,
            transient: notification.transient,
            hints: notification.hints,
            actions: root.actionDataForNotification(notification),
            hasDefaultAction: defaultAction.length > 0,
            defaultActionIdentifier: defaultAction,
            createdAt: createdAt,
            updatedAt: updatedAt,
            closeReason: reason,
            closeReasonText: reason === undefined ? "" : NotificationCloseReason.toString(reason)
        };
    }

    function groupedNotificationViews(notifications) {
        const latestByGroup = ({});
        const ordered = [];

        for (let i = 0; i < notifications.length; ++i) {
            const notification = notifications[i];
            const view = root.presentationForNotification(notification);
            const existingIndex = latestByGroup[view.groupKey];

            if (existingIndex === undefined) {
                latestByGroup[view.groupKey] = ordered.length;
                ordered.push(view);
                continue;
            }

            const existing = ordered[existingIndex];
            if (view.updatedAt >= existing.updatedAt) {
                ordered[existingIndex] = view;
            }
        }

        ordered.sort(function(a, b) {
            return b.updatedAt - a.updatedAt;
        });

        return ordered;
    }

    function activeNotificationViews() {
        return root.groupedNotificationViews(root.activeNotifications || []);
    }

    function activeNotificationViewsForScreen(screen) {
        const notifications = root.activeNotifications || [];
        const filtered = [];

        for (let i = 0; i < notifications.length; ++i) {
            const notification = notifications[i];
            if (root.screenForNotification(notification.id) === screen) {
                filtered.push(notification);
            }
        }

        return root.groupedNotificationViews(filtered);
    }

    function historySnapshot(notification, reason) {
        const snapshot = root.presentationForNotification(notification, reason);
        snapshot.closedAt = Date.now();
        return snapshot;
    }

    function prependHistory(entry) {
        const nextHistory = [entry].concat(root.notificationHistory || []);
        if (nextHistory.length > root.historyLimit) {
            nextHistory.length = root.historyLimit;
        }

        root.notificationHistory = nextHistory;
    }

    function rememberNotificationMetadata(notification) {
        const now = Date.now();
        const notificationId = notification.id;
        const existingScreen = root.screenForNotification(notificationId);

        root.screenByNotificationId = Object.assign({}, root.screenByNotificationId, {
            [notificationId]: existingScreen || root.focusedScreen()
        });

        root.updatedAtByNotificationId = Object.assign({}, root.updatedAtByNotificationId, {
            [notificationId]: now
        });

        if (!(notificationId in root.createdAtByNotificationId)) {
            root.createdAtByNotificationId = Object.assign({}, root.createdAtByNotificationId, {
                [notificationId]: now
            });
        }
    }

    function forgetNotificationMetadata(notificationId) {
        const nextScreens = Object.assign({}, root.screenByNotificationId);
        const nextCreatedAt = Object.assign({}, root.createdAtByNotificationId);
        const nextUpdatedAt = Object.assign({}, root.updatedAtByNotificationId);

        delete nextScreens[notificationId];
        delete nextCreatedAt[notificationId];
        delete nextUpdatedAt[notificationId];

        root.screenByNotificationId = nextScreens;
        root.createdAtByNotificationId = nextCreatedAt;
        root.updatedAtByNotificationId = nextUpdatedAt;
    }

    function findNotification(notificationId) {
        const notifications = root.activeNotifications || [];

        for (let i = 0; i < notifications.length; ++i) {
            const notification = notifications[i];
            if (notification.id === notificationId) {
                return notification;
            }
        }

        return null;
    }

    function invokeAction(notificationId, actionIdentifier) {
        const notification = root.findNotification(notificationId);
        if (!notification) {
            return;
        }

        const actions = notification.actions || [];
        for (let i = 0; i < actions.length; ++i) {
            const action = actions[i];
            if (action.identifier === actionIdentifier) {
                action.invoke();
                return;
            }
        }
    }

    function invokeDefaultAction(notificationId) {
        const notification = root.findNotification(notificationId);
        if (!notification) {
            return;
        }

        const defaultAction = root.defaultActionIdentifier(notification);
        if (defaultAction.length) {
            root.invokeAction(notificationId, defaultAction);
        }
    }

    function dismissNotification(notificationId) {
        const notification = root.findNotification(notificationId);
        if (notification) {
            notification.dismiss();
        }
    }

    function expireNotification(notificationId) {
        const notification = root.findNotification(notificationId);
        if (notification) {
            notification.expire();
        }
    }

    function clearHistory() {
        root.notificationHistory = [];
    }

    function connectNotification(notification) {
        const notificationId = notification.id;
        const connectedNotifications = root.connectedNotificationsById;

        if (connectedNotifications[notificationId] === notification) {
            return;
        }

        connectedNotifications[notificationId] = notification;
        notification.closed.connect(function(reason) {
            root.prependHistory(root.historySnapshot(notification, reason));
            root.forgetNotificationMetadata(notification.id);
        });
    }

    readonly property QtObject server: NotificationServer {
        keepOnReload: false
        persistenceSupported: false
        bodySupported: true
        bodyMarkupSupported: true
        bodyHyperlinksSupported: false
        bodyImagesSupported: false
        actionsSupported: true
        actionIconsSupported: false
        imageSupported: true
        inlineReplySupported: false

        onNotification: function(notification) {
            notification.tracked = true;
            root.rememberNotificationMetadata(notification);
            root.connectNotification(notification);
        }
    }
}
