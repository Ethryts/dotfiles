import QtQuick

QtObject {
    id: root

    property int resetTimeoutMs: 450
    property int stopTimeoutMs: 180
    property int baseIntervalMs: 120
    property int minIntervalMs: 35
    property int fastGapMs: 90
    property int mediumGapMs: 160
    property int slowGapMs: 260
    property real maxMomentum: 4
    property double lastWheelMs: 0
    property real momentum: 0
    property int direction: 0

    signal step(int direction)

    function handleWheel(deltaY) {
        const nextDirection = deltaY > 0 ? 1 : (deltaY < 0 ? -1 : 0);

        if (nextDirection === 0) {
            return;
        }

        const now = Date.now();
        const gapMs = root.lastWheelMs > 0 ? now - root.lastWheelMs : root.resetTimeoutMs + 1;
        const continuing = root.direction === nextDirection
            && root.lastWheelMs > 0
            && gapMs <= root.resetTimeoutMs;

        root.direction = nextDirection;
        root.lastWheelMs = now;

        if (!continuing) {
            root.momentum = 0;
        } else if (gapMs <= root.fastGapMs) {
            root.momentum += 1;
        } else if (gapMs <= root.mediumGapMs) {
            root.momentum += 0.5;
        } else if (gapMs <= root.slowGapMs) {
            root.momentum += 0.2;
        } else {
            root.momentum *= 0.5;
        }

        root.momentum = Math.min(root.maxMomentum, root.momentum);
        root.step(root.direction);
        repeatTimer.interval = root.currentIntervalMs();

        if (root.momentum > 0 && !repeatTimer.running) {
            repeatTimer.start();
        }
    }

    function currentIntervalMs() {
        const multiplier = 1 + root.momentum;
        return Math.max(root.minIntervalMs, Math.round(root.baseIntervalMs / multiplier));
    }

    readonly property QtObject repeatTimer: Timer {
        id: repeatTimer
        repeat: true
        interval: root.baseIntervalMs
        onTriggered: {
            const now = Date.now();

            if (root.direction === 0 || now - root.lastWheelMs > root.stopTimeoutMs) {
                root.direction = 0;
                root.momentum = 0;
                repeatTimer.stop();
                return;
            }

            root.step(root.direction);
            repeatTimer.interval = root.currentIntervalMs();
        }
    }
}
