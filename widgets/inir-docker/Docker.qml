pragma ComponentBehavior: Bound

// The Material desktop face for iNiR Docker. The data collector and parsers live
// in docker.js (MIT, based on devgtv/omarchy-docker); this file only draws and
// steers it.
//
// The widget is intentionally a card, not a bar popup: iNiR places it on the
// desktop. Click a container to select it, then use the action row for
// start/stop/restart, recent logs or follow logs.

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.shared.background.widgets
import "docker.js" as Docker

AbstractBackgroundWidget {
    id: root

    configEntryName: "custom.inir-docker"
    defaultConfig: ({
        placementStrategy: "free",
        widgetScale: 100,
        widgetOpacity: 100,
        colorMode: "auto",
        dim: 0,
        showBackground: true,
        backgroundOpacity: 0.16,
        borderWidth: 1,
        borderOpacity: 0.2,
        cornerRadius: -1,
        useBlur: false,
        x: 320,
        y: 200,
        refreshSeconds: 3,
        maxContainers: 6,
        showStopped: true,
        filter: ""
    })
    needsColText: true
    resizableAxes: ({ uniform: "widgetScale" })
    resizeMinWidth: 320
    resizeMinHeight: 150
    widgetSurfaceEnabled: true

    // ── Settings ─────────────────────────────────────────────
    readonly property int refreshSeconds: Math.max(1, Math.min(60, Number(root._readConfigKey("refreshSeconds") ?? 3)))
    readonly property int maxContainers: Math.max(1, Math.min(20, Number(root._readConfigKey("maxContainers") ?? 6)))
    readonly property bool showStopped: Boolean(root._readConfigKey("showStopped") ?? true)
    readonly property string filterText: String(root._readConfigKey("filter") ?? "")

    // ── Docker state ─────────────────────────────────────────
    property var snapshot: null
    property string error: ""
    property bool loading: false
    property string selectedId: ""
    property string pendingAction: ""
    property string actionNotice: ""
    property string actionError: ""

    readonly property var containers: (root.snapshot && root.snapshot.containers) ? root.snapshot.containers : []
    readonly property var filtered: {
        const list = Docker.visibleContainers(root.containers, root.filterText, "all", "", false)
        return root.showStopped ? list : list.filter(container => container.status === "running")
    }
    readonly property var shown: root.filtered.slice(0, root.maxContainers)
    readonly property int hiddenCount: Math.max(0, root.filtered.length - root.shown.length)
    readonly property var selected: {
        const id = root.selectedId
        if (id.length === 0) return null
        return root.containers.find(container => container.fullId === id || container.name === id) ?? null
    }
    readonly property string targetLabel: (root.snapshot && root.snapshot.target)
        ? Docker.targetLabel(root.snapshot.target) : ""
    readonly property bool available: Boolean(root.snapshot && root.snapshot.dockerAvailable)
    readonly property bool hasData: root.snapshot !== null
    readonly property bool busy: snapshotProc.running || actionProc.running

    // ── Geometry ─────────────────────────────────────────────
    readonly property int pad: Math.round(14 * root.scaleFactor)
    readonly property int gap: Math.round(6 * root.scaleFactor)
    readonly property int rowHeight: Math.round(32 * root.scaleFactor)

    implicitWidth: Math.round(380 * root.scaleFactor)
    implicitHeight: Math.max(Math.round(150 * root.scaleFactor), content.implicitHeight + root.pad * 2)

    // ── Collector ────────────────────────────────────────────
    Process {
        id: snapshotProc
        command: Docker.snapshotCommand
        stdout: StdioCollector {
            id: snapshotOut
            waitForEnd: true
        }
        stderr: StdioCollector {
            id: snapshotErr
            waitForEnd: true
        }
        onExited: (code, status) => {
            root.loading = false
            if (code === 0) {
                try {
                    const next = Docker.parseSnapshot(snapshotOut.text)
                    if (next && next.dockerAvailable) {
                        root.snapshot = next
                        root.error = ""
                    } else {
                        root.error = "Docker is not reachable"
                    }
                } catch (e) {
                    root.error = "Could not read Docker: " + String(e)
                }
            } else {
                const line = String(snapshotErr.text ?? "").trim().split("\n")[0]
                root.error = line.length > 0 ? line : "Docker did not answer"
            }
        }
    }

    function refresh(): void {
        if (snapshotProc.running) return
        root.loading = true
        snapshotProc.running = true
    }

    Timer {
        interval: root.refreshSeconds * 1000
        repeat: true
        triggeredOnStart: true
        // Keep the card cheap: poll only while it can be seen, plus the first read.
        running: root.visible && (root.motionActive || root.snapshot === null)
        onTriggered: root.refresh()
    }

    // ── Actions ──────────────────────────────────────────────
    Process {
        id: actionProc
        stderr: StdioCollector {
            id: actionErr
            waitForEnd: true
        }
        onExited: (code, status) => {
            if (code === 0) {
                root.actionNotice = root.pendingAction + " complete"
                root.actionError = ""
            } else {
                const line = String(actionErr.text ?? "").trim().split("\n")[0]
                root.actionError = line.length > 0 ? line : "Docker exited with code " + code
            }
            root.pendingAction = ""
            root.refresh()
        }
    }

    function selectContainer(container): void {
        root.selectedId = container.fullId
        root.pendingAction = ""
        root.actionError = ""
        root.actionNotice = ""
    }

    function requestAction(action): void {
        if (!root.selected || !Docker.canContainerAction(action, root.selected)) return
        root.pendingAction = action
        root.actionNotice = ""
        root.actionError = ""
    }

    function confirmAction(): void {
        if (!root.selected || root.pendingAction.length === 0 || !root.snapshot) return
        const command = Docker.containerActionCommand(root.snapshot.target, root.pendingAction, root.selected)
        if (command.length === 0) {
            root.actionError = "Docker target unavailable"
            root.pendingAction = ""
            return
        }
        actionProc.command = command
        actionProc.running = true
    }

    function cancelAction(): void {
        root.pendingAction = ""
    }

    function openLogs(follow): void {
        if (!root.selected || !root.snapshot) return
        const command = Docker.logsCommand(root.snapshot.target, root.selected, follow === true)
        if (command.length > 0) Quickshell.execDetached(command)
    }

    function statusIcon(status): string {
        if (status === "running") return "play_circle"
        if (status === "exited") return "stop_circle"
        if (status === "paused") return "pause_circle"
        if (status === "restarting") return "restart_alt"
        return "circle"
    }

    function statusColor(status): color {
        if (status === "running") return Appearance.colors.colPrimary
        if (status === "exited") return Appearance.colors.colError
        return ColorUtils.applyAlpha(root.widgetInk, 0.55)
    }

    // The plate every built-in widget sits on.
    WidgetSurface {
        anchors.fill: parent
        widget: root
        shown: root.backgroundOpacity > 0 || root.borderWidth > 0 || root.effectiveBlur
        surfaceColor: root.widgetInk
        surfaceAccent: root.widgetAccent3
    }

    ColumnLayout {
        id: content
        anchors.fill: parent
        anchors.margins: root.pad
        spacing: root.gap

        // ── Header ───────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: Math.round(6 * root.scaleFactor)

            MaterialSymbol {
                text: "deployed_code"
                fill: 1
                iconSize: Math.round(18 * root.scaleFactor)
                color: root.available ? root.widgetAccentVisible : ColorUtils.applyAlpha(root.widgetInk, 0.55)
            }
            StyledText {
                text: "Docker"
                font.pixelSize: Math.round(Appearance.font.pixelSize.small * root.scaleFactor)
                font.weight: Font.DemiBold
                color: root.widgetInk
            }
            StyledText {
                visible: root.available && root.snapshot?.dockerVersion?.length > 0
                text: "v" + String(root.snapshot?.dockerVersion ?? "")
                font.pixelSize: Math.round(Appearance.font.pixelSize.smaller * root.scaleFactor)
                color: ColorUtils.applyAlpha(root.widgetInk, 0.55)
            }
            Item { Layout.fillWidth: true }
            RippleButton {
                implicitWidth: Math.round(26 * root.scaleFactor)
                implicitHeight: implicitWidth
                buttonRadius: implicitWidth / 2
                enabled: !root.busy
                colBackground: "transparent"
                colBackgroundHover: ColorUtils.applyAlpha(root.widgetInk, 0.12)
                colRipple: ColorUtils.applyAlpha(root.widgetInk, 0.2)
                onClicked: root.refresh()
                Accessible.name: "Refresh Docker containers"
                contentItem: MaterialSymbol {
                    text: "refresh"
                    iconSize: Math.round(16 * root.scaleFactor)
                    color: root.widgetInk
                }
            }
        }

        StyledText {
            Layout.fillWidth: true
            visible: root.targetLabel.length > 0
            text: root.targetLabel
            elide: Text.ElideRight
            font.pixelSize: Math.round(Appearance.font.pixelSize.smaller * root.scaleFactor)
            color: ColorUtils.applyAlpha(root.widgetInk, 0.55)
        }

        // ── Body ─────────────────────────────────────────────
        StyledText {
            Layout.fillWidth: true
            visible: root.error.length > 0
            text: root.error
            wrapMode: Text.WordWrap
            font.pixelSize: Math.round(Appearance.font.pixelSize.small * root.scaleFactor)
            color: Appearance.colors.colError
        }

        StyledText {
            Layout.fillWidth: true
            visible: root.error.length === 0 && root.loading && !root.hasData
            text: "Reading Docker…"
            font.pixelSize: Math.round(Appearance.font.pixelSize.small * root.scaleFactor)
            color: ColorUtils.applyAlpha(root.widgetInk, 0.62)
        }

        StyledText {
            Layout.fillWidth: true
            visible: root.error.length === 0 && root.hasData && root.shown.length === 0
            text: root.filterText.length > 0 ? "No containers match the filter" : "No containers"
            font.pixelSize: Math.round(Appearance.font.pixelSize.small * root.scaleFactor)
            color: ColorUtils.applyAlpha(root.widgetInk, 0.62)
        }

        Column {
            id: rows
            Layout.fillWidth: true
            spacing: Math.round(2 * root.scaleFactor)

            Repeater {
                model: root.shown
                delegate: Rectangle {
                    required property var modelData

                    width: rows.width
                    height: root.rowHeight
                    radius: Math.round(6 * root.scaleFactor)
                    color: root.selectedId === modelData.fullId
                        ? ColorUtils.applyAlpha(root.widgetInk, 0.12)
                        : "transparent"

                    MouseArea {
                        anchors.fill: parent
                        onClicked: root.selectContainer(modelData)
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Math.round(6 * root.scaleFactor)
                        anchors.rightMargin: Math.round(6 * root.scaleFactor)
                        spacing: Math.round(6 * root.scaleFactor)

                        MaterialSymbol {
                            text: root.statusIcon(modelData.status)
                            fill: 1
                            iconSize: Math.round(15 * root.scaleFactor)
                            color: root.statusColor(modelData.status)
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: modelData.name
                            elide: Text.ElideRight
                            font.pixelSize: Math.round(Appearance.font.pixelSize.small * root.scaleFactor)
                            color: root.widgetInk
                        }
                        StyledText {
                            text: modelData.status
                            font.pixelSize: Math.round(Appearance.font.pixelSize.smaller * root.scaleFactor)
                            color: ColorUtils.applyAlpha(root.widgetInk, 0.55)
                        }
                        StyledText {
                            text: modelData.cpuPercent.length > 0 ? modelData.cpuPercent : "—"
                            font.family: root.widgetNumbersFamily
                            font.pixelSize: Math.round(Appearance.font.pixelSize.smaller * root.scaleFactor)
                            color: ColorUtils.applyAlpha(root.widgetInk, 0.55)
                        }
                        StyledText {
                            text: modelData.memUsageBytes > 0 ? Docker.formatBytes(modelData.memUsageBytes) : "—"
                            font.family: root.widgetNumbersFamily
                            font.pixelSize: Math.round(Appearance.font.pixelSize.smaller * root.scaleFactor)
                            color: ColorUtils.applyAlpha(root.widgetInk, 0.55)
                        }
                    }
                }
            }
        }

        StyledText {
            Layout.fillWidth: true
            visible: root.hiddenCount > 0
            text: "+" + root.hiddenCount + " more"
            font.pixelSize: Math.round(Appearance.font.pixelSize.smaller * root.scaleFactor)
            color: ColorUtils.applyAlpha(root.widgetInk, 0.55)
        }

        // ── Selected container ───────────────────────────────
        StyledText {
            Layout.fillWidth: true
            visible: root.selected !== null
            text: root.selected ? root.selected.image : ""
            elide: Text.ElideRight
            font.pixelSize: Math.round(Appearance.font.pixelSize.smaller * root.scaleFactor)
            color: ColorUtils.applyAlpha(root.widgetInk, 0.55)
        }

        RowLayout {
            Layout.fillWidth: true
            visible: root.selected !== null && root.pendingAction.length === 0
            spacing: Math.round(4 * root.scaleFactor)

            RippleButton {
                visible: Docker.canContainerAction("start", root.selected)
                implicitWidth: Math.round(28 * root.scaleFactor)
                implicitHeight: implicitWidth
                buttonRadius: Math.round(7 * root.scaleFactor)
                enabled: !root.busy
                colBackground: "transparent"
                colBackgroundHover: ColorUtils.applyAlpha(root.widgetAccentVisible, 0.14)
                colRipple: ColorUtils.applyAlpha(root.widgetAccentVisible, 0.22)
                onClicked: root.requestAction("start")
                Accessible.name: "Start container"
                contentItem: MaterialSymbol {
                    text: "play_arrow"
                    iconSize: Math.round(16 * root.scaleFactor)
                    color: root.widgetAccentVisible
                }
            }
            RippleButton {
                visible: Docker.canContainerAction("stop", root.selected)
                implicitWidth: Math.round(28 * root.scaleFactor)
                implicitHeight: implicitWidth
                buttonRadius: Math.round(7 * root.scaleFactor)
                enabled: !root.busy
                colBackground: "transparent"
                colBackgroundHover: ColorUtils.applyAlpha(root.widgetInk, 0.12)
                colRipple: ColorUtils.applyAlpha(root.widgetInk, 0.2)
                onClicked: root.requestAction("stop")
                Accessible.name: "Stop container"
                contentItem: MaterialSymbol {
                    text: "stop"
                    iconSize: Math.round(16 * root.scaleFactor)
                    color: root.widgetInk
                }
            }
            RippleButton {
                visible: Docker.canContainerAction("restart", root.selected)
                implicitWidth: Math.round(28 * root.scaleFactor)
                implicitHeight: implicitWidth
                buttonRadius: Math.round(7 * root.scaleFactor)
                enabled: !root.busy
                colBackground: "transparent"
                colBackgroundHover: ColorUtils.applyAlpha(root.widgetInk, 0.12)
                colRipple: ColorUtils.applyAlpha(root.widgetInk, 0.2)
                onClicked: root.requestAction("restart")
                Accessible.name: "Restart container"
                contentItem: MaterialSymbol {
                    text: "restart_alt"
                    iconSize: Math.round(16 * root.scaleFactor)
                    color: root.widgetInk
                }
            }
            RippleButton {
                implicitWidth: Math.round(28 * root.scaleFactor)
                implicitHeight: implicitWidth
                buttonRadius: Math.round(7 * root.scaleFactor)
                enabled: !root.busy
                colBackground: "transparent"
                colBackgroundHover: ColorUtils.applyAlpha(root.widgetInk, 0.12)
                colRipple: ColorUtils.applyAlpha(root.widgetInk, 0.2)
                onClicked: root.openLogs(false)
                Accessible.name: "Open recent logs"
                contentItem: MaterialSymbol {
                    text: "article"
                    iconSize: Math.round(16 * root.scaleFactor)
                    color: root.widgetInk
                }
            }
            RippleButton {
                implicitWidth: Math.round(28 * root.scaleFactor)
                implicitHeight: implicitWidth
                buttonRadius: Math.round(7 * root.scaleFactor)
                enabled: !root.busy
                colBackground: "transparent"
                colBackgroundHover: ColorUtils.applyAlpha(root.widgetInk, 0.12)
                colRipple: ColorUtils.applyAlpha(root.widgetInk, 0.2)
                onClicked: root.openLogs(true)
                Accessible.name: "Follow logs"
                contentItem: MaterialSymbol {
                    text: "subject"
                    iconSize: Math.round(16 * root.scaleFactor)
                    color: root.widgetInk
                }
            }
            Item { Layout.fillWidth: true }
        }

        RowLayout {
            Layout.fillWidth: true
            visible: root.pendingAction.length > 0
            spacing: Math.round(6 * root.scaleFactor)
            StyledText {
                Layout.fillWidth: true
                text: root.pendingAction + " " + (root.selected?.name ?? "container") + "?"
                elide: Text.ElideRight
                font.pixelSize: Math.round(Appearance.font.pixelSize.smaller * root.scaleFactor)
                color: root.widgetInk
            }
            RippleButton {
                buttonText: "Cancel"
                implicitWidth: Math.round(70 * root.scaleFactor)
                implicitHeight: Math.round(26 * root.scaleFactor)
                buttonRadius: Math.round(7 * root.scaleFactor)
                colBackground: "transparent"
                colBackgroundHover: ColorUtils.applyAlpha(root.widgetInk, 0.12)
                colRipple: ColorUtils.applyAlpha(root.widgetInk, 0.2)
                onClicked: root.cancelAction()
            }
            RippleButton {
                buttonText: "Confirm"
                implicitWidth: Math.round(74 * root.scaleFactor)
                implicitHeight: Math.round(26 * root.scaleFactor)
                buttonRadius: Math.round(7 * root.scaleFactor)
                colBackground: ColorUtils.applyAlpha(root.widgetAccentVisible, 0.18)
                colBackgroundHover: ColorUtils.applyAlpha(root.widgetAccentVisible, 0.28)
                colRipple: ColorUtils.applyAlpha(root.widgetAccentVisible, 0.34)
                onClicked: root.confirmAction()
            }
        }

        StyledText {
            Layout.fillWidth: true
            visible: root.actionNotice.length > 0
            text: root.actionNotice
            elide: Text.ElideRight
            font.pixelSize: Math.round(Appearance.font.pixelSize.smaller * root.scaleFactor)
            color: root.widgetAccentVisible
        }
        StyledText {
            Layout.fillWidth: true
            visible: root.actionError.length > 0
            text: root.actionError
            wrapMode: Text.WordWrap
            font.pixelSize: Math.round(Appearance.font.pixelSize.smaller * root.scaleFactor)
            color: Appearance.colors.colError
        }
    }
}
