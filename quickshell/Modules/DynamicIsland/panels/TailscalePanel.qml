import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Common
import qs.Services
import qs.Widgets

// Tailscale detail view (drill-down, island-styled). Mirrors the Control Center
// Tailscale widget (status header + searchable, filterable peer list) and refs
// the service only while open. Reads/writes island state via `island`.
Column {
    id: tsCol
    property var island: null
    anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
    spacing: Theme.spacingS
    opacity: island.panelView === "tailscale" ? 1 : 0
    visible: opacity > 0
    transform: Translate { x: island.panelView === "tailscale" ? 0 : 24; Behavior on x { NumberAnimation { duration: Theme.shortDuration; easing.type: Easing.OutQuad } } }
    Behavior on opacity { NumberAnimation { duration: Theme.shortDuration } }

    property string searchQuery: ""
    property int filterIndex: 0  // 0=My Online, 1=All Online, 2=All

    // ref-count the service while the view is open (covers the direct IPC
    // `open tailscale` path too). TailscaleService is ref'd via the declarative
    // Ref component (it has no addRef()/removeRef() methods).
    readonly property bool tsActive: island && island.mode === "expanded" && island.panelView === "tailscale"
    Loader {
        active: tsCol.tsActive
        visible: false   // non-visual: keep it out of the Column layout
        sourceComponent: Component { Ref { service: TailscaleService } }
    }
    onTsActiveChanged: if (tsActive) {
        TailscaleService.getStatus()
        TailscaleService.refreshExitInfo()
        TailscaleService.pingMyOnline()
    }

    // header: back · device_hub · title · refresh
    RowLayout {
        width: parent.width
        spacing: Theme.spacingS
        DankActionButton {
            iconName: "chevron_left"
            buttonSize: 30
            iconSize: 20
            iconColor: tsCol.island.textColor
            onClicked: tsCol.island.panelView = "controls"
        }
        DankIcon {
            name: "device_hub"
            size: 18
            color: TailscaleService.connected ? Theme.primary : Theme.surfaceVariantText
            Layout.alignment: Qt.AlignVCenter
        }
        StyledText {
            text: I18n.tr("Tailscale")
            font.pixelSize: Theme.fontSizeMedium
            font.weight: Font.Bold
            color: tsCol.island.textColor
            Layout.fillWidth: true
        }
        DankActionButton {
            iconName: "sync"
            buttonSize: 28
            iconSize: 16
            iconColor: Theme.surfaceVariantText
            tooltipText: I18n.tr("Refresh")
            onClicked: { TailscaleService.refresh(null); TailscaleService.refreshExitInfo(); TailscaleService.pingMyOnline() }
        }
    }

    // ---- not-connected state card (login / activate / errors) ----
    Column {
        width: parent.width
        spacing: Theme.spacingS
        visible: !TailscaleService.connected
        topPadding: Theme.spacingM

        DankIcon {
            anchors.horizontalCenter: parent.horizontalCenter
            name: {
                if (TailscaleService.authUrl.length > 0)
                    return "open_in_browser"
                const k = TailscaleService.statusKind
                if (k === "needsLogin" || k === "needsAuth")
                    return "person_off"
                if (k === "stopped")
                    return "cloud_off"
                if (k === "starting")
                    return "sync"
                return "vpn_key_off"
            }
            size: 40
            color: Theme.surfaceVariantText
            RotationAnimation on rotation {
                running: TailscaleService.statusKind === "starting" || (TailscaleService.loginInProgress && TailscaleService.authUrl.length === 0)
                from: 0; to: 360; duration: 1000; loops: Animation.Infinite
            }
        }

        StyledText {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            font.pixelSize: Theme.fontSizeMedium
            font.weight: Font.Bold
            color: tsCol.island.textColor
            wrapMode: Text.WordWrap
            text: {
                if (TailscaleService.loginInProgress && TailscaleService.authUrl.length === 0)
                    return I18n.tr("Connecting… approve in the dialog")
                if (TailscaleService.authUrl.length > 0)
                    return I18n.tr("Authenticate in your browser")
                const k = TailscaleService.statusKind
                if (k === "needsLogin" || k === "needsAuth")
                    return I18n.tr("No active account")
                if (k === "stopped")
                    return I18n.tr("Tailscale is stopped")
                if (k === "starting")
                    return I18n.tr("Connecting…")
                return I18n.tr("Tailscale unavailable")
            }
        }

        StyledText {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            visible: TailscaleService.loginError.length > 0
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.error
            wrapMode: Text.WordWrap
            text: TailscaleService.loginError
        }

        // primary action: Sign in / Activate / Retry
        DankButton {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: TailscaleService.authUrl.length === 0
                && TailscaleService.statusKind !== "starting"
                && !(TailscaleService.loginInProgress && TailscaleService.authUrl.length === 0)
            iconName: "login"
            text: {
                if (TailscaleService.loginError.length > 0)
                    return I18n.tr("Retry")
                if (TailscaleService.statusKind === "stopped")
                    return I18n.tr("Activate")
                return I18n.tr("Sign in")
            }
            onClicked: TailscaleService.login()
        }

        // auth-url actions: open browser / copy link
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Theme.spacingS
            visible: TailscaleService.authUrl.length > 0
            DankButton {
                iconName: "open_in_new"
                text: I18n.tr("Open browser")
                onClicked: Quickshell.execDetached(["xdg-open", TailscaleService.authUrl])
            }
            DankButton {
                iconName: "content_copy"
                text: I18n.tr("Copy link")
                backgroundColor: Theme.surfaceContainerHigh
                onClicked: Quickshell.execDetached(["dms", "cl", "copy", TailscaleService.authUrl])
            }
        }
    }

    // status line: tailnet + exit-node
    StyledText {
        width: parent.width
        visible: TailscaleService.connected
        elide: Text.ElideRight
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        text: {
            if (!TailscaleService.available)
                return I18n.tr("Tailscale not available")
            if (!TailscaleService.connected)
                return I18n.tr("Disconnected")
            const parts = []
            if (TailscaleService.tailnetName)
                parts.push(TailscaleService.tailnetName)
            if (TailscaleService.usingExitNode)
                parts.push(I18n.tr("via %1").arg(TailscaleService.exitNodeName) + " \u{1F310}")
            return parts.join("  •  ")
        }
    }

    // ---- exit-node selector ----
    Column {
        width: parent.width
        spacing: Theme.spacingXS
        visible: TailscaleService.connected && (TailscaleService.exitNodePeers.length > 0 || TailscaleService.usingExitNode)

        RowLayout {
            width: parent.width
            spacing: Theme.spacingS
            DankIcon {
                name: "public"
                size: 16
                color: TailscaleService.usingExitNode ? Theme.primary : Theme.surfaceVariantText
                Layout.alignment: Qt.AlignVCenter
            }
            StyledText {
                Layout.fillWidth: true
                font.pixelSize: Theme.fontSizeSmall
                color: tsCol.island.textColor
                elide: Text.ElideRight
                text: TailscaleService.usingExitNode ? (I18n.tr("Exit node") + ": " + TailscaleService.exitNodeName) : I18n.tr("Exit node")
            }
            DankButton {
                visible: TailscaleService.usingExitNode
                text: I18n.tr("Disconnect")
                buttonHeight: 26
                backgroundColor: Theme.surfaceContainerHigh
                onClicked: TailscaleService.clearExitNode()
            }
        }
        StyledText {
            width: parent.width
            visible: TailscaleService.exitNodeError.length > 0
            font.pixelSize: 10
            color: Theme.error
            wrapMode: Text.WordWrap
            text: TailscaleService.exitNodeError
        }
        Flow {
            width: parent.width
            spacing: Theme.spacingXS
            Repeater {
                model: TailscaleService.exitNodePeers
                delegate: DankButton {
                    required property var modelData
                    readonly property bool active: TailscaleService.activeExitNode && TailscaleService.activeExitNode.tailscaleIp === modelData.tailscaleIp
                    text: (modelData.hostname || modelData.tailscaleIp) + (active ? " ✓" : "")
                    buttonHeight: 26
                    backgroundColor: active ? Theme.primary : Theme.surfaceContainerHigh
                    textColor: active ? Theme.onPrimary : Theme.surfaceText
                    onClicked: active ? TailscaleService.clearExitNode() : TailscaleService.setExitNode(modelData)
                }
            }
        }
    }

    // search
    DankTextField {
        width: parent.width
        placeholderText: I18n.tr("Search devices...")
        leftIconName: "search"
        showClearButton: true
        text: tsCol.searchQuery
        onTextEdited: tsCol.searchQuery = text
        visible: TailscaleService.connected
    }

    // filter chips
    DankFilterChips {
        width: parent.width
        currentIndex: tsCol.filterIndex
        showCounts: true
        chipHeight: 26
        visible: TailscaleService.connected
        model: [
            { "label": I18n.tr("My Online"), "count": TailscaleService.myOnlinePeers.length },
            { "label": I18n.tr("Online"),    "count": TailscaleService.onlinePeers.length },
            { "label": I18n.tr("All"),        "count": TailscaleService.allPeersList.length }
        ]
        onSelectionChanged: index => tsCol.filterIndex = index
    }

    // peer list
    DankFlickable {
        width: parent.width
        height: Math.min(contentHeight, 260)
        contentHeight: peerCol.implicitHeight
        clip: true
        visible: TailscaleService.connected

        Column {
            id: peerCol
            width: parent.width
            spacing: Theme.spacingXS

            property var filteredPeers: {
                let base
                switch (tsCol.filterIndex) {
                case 0:  base = TailscaleService.myOnlinePeers; break
                case 1:  base = TailscaleService.onlinePeers; break
                case 2:  base = TailscaleService.allPeersList; break
                default: base = []
                }
                if (tsCol.searchQuery.length > 0)
                    return TailscaleService.searchPeers(tsCol.searchQuery, base)
                return base
            }

            // empty state
            StyledText {
                width: parent.width
                visible: peerCol.filteredPeers.length === 0
                horizontalAlignment: Text.AlignHCenter
                topPadding: Theme.spacingM; bottomPadding: Theme.spacingM
                text: tsCol.searchQuery.length > 0 ? I18n.tr("No matching devices") : I18n.tr("No peers found")
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
            }

            Repeater {
                model: peerCol.filteredPeers
                delegate: Rectangle {
                    id: peerCard
                    required property var modelData
                    // Taildrop: only online devices I own (with an IP) can receive a drop
                    readonly property bool canReceiveDrop: modelData.online && TailscaleService.isMine(modelData) && (modelData.tailscaleIp || "").length > 0
                    width: peerCol.width
                    height: peerRow.implicitHeight + Theme.spacingS * 2
                    radius: Theme.cornerRadius
                    color: Theme.surfaceContainerHighest
                    RowLayout {
                        id: peerRow
                        anchors.fill: parent
                        anchors.margins: Theme.spacingS
                        spacing: Theme.spacingS
                        Rectangle {
                            width: 8; height: 8; radius: 4
                            color: modelData.online ? "#4caf50" : Theme.surfaceVariantText
                            Layout.alignment: Qt.AlignVCenter
                        }
                        Column {
                            Layout.fillWidth: true
                            spacing: 1
                            StyledText {
                                text: modelData.hostname || ""
                                font.pixelSize: Theme.fontSizeSmall
                                font.weight: Font.Bold
                                color: Theme.surfaceText
                                width: parent.width
                                elide: Text.ElideRight
                            }
                            StyledText {
                                text: modelData.tailscaleIp || ""
                                font.pixelSize: 10
                                color: Theme.surfaceTextMedium
                            }
                            StyledText {
                                readonly property var p: TailscaleService.pings[modelData.tailscaleIp]
                                visible: modelData.online && p !== undefined
                                text: {
                                    if (!p) return ""
                                    if (p.state === "pending") return "…"
                                    if (p.state === "fail") return "—"
                                    return p.ms + " ms · " + (p.route === "relay" ? I18n.tr("relay") : I18n.tr("direct"))
                                }
                                font.pixelSize: 10
                                color: Theme.surfaceVariantText
                            }
                        }
                        DankActionButton {
                            visible: TailscaleService.isMine(modelData) && (modelData.tailscaleIp || "").length > 0
                            iconName: modelData.hostname === SettingsData.taildropDefaultPeer ? "star" : "star_border"
                            buttonSize: 20
                            iconSize: 13
                            iconColor: modelData.hostname === SettingsData.taildropDefaultPeer ? Theme.primary : Theme.surfaceVariantText
                            tooltipText: I18n.tr("Default Taildrop device")
                            onClicked: SettingsData.set("taildropDefaultPeer", SettingsData.taildropDefaultPeer === modelData.hostname ? "" : modelData.hostname)
                        }
                        DankActionButton {
                            iconName: "content_copy"
                            buttonSize: 20
                            iconSize: 11
                            iconColor: Theme.surfaceVariantText
                            tooltipText: I18n.tr("Copy")
                            onClicked: Quickshell.execDetached(["dms", "cl", "copy", modelData.tailscaleIp])
                        }
                    }

                    // Taildrop: drop files here to send to this device
                    Rectangle {
                        anchors.fill: parent
                        radius: peerCard.radius
                        visible: tsDrop.containsDrag && peerCard.canReceiveDrop
                        color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.18)
                        border.width: 1
                        border.color: Theme.primary
                        StyledText {
                            anchors.centerIn: parent
                            text: I18n.tr("Drop to send")
                            font.pixelSize: Theme.fontSizeSmall
                            font.weight: Font.Bold
                            color: Theme.primary
                        }
                    }
                    DropArea {
                        id: tsDrop
                        anchors.fill: parent
                        onEntered: drag => {
                            if (!peerCard.canReceiveDrop || !drag.hasUrls)
                                drag.accepted = false
                        }
                        onDropped: drop => {
                            if (!peerCard.canReceiveDrop || !drop.hasUrls)
                                return
                            const paths = []
                            for (var i = 0; i < drop.urls.length; i++) {
                                const u = String(drop.urls[i])
                                if (u.startsWith("file://"))
                                    paths.push(decodeURIComponent(u.substring(7)))
                            }
                            if (paths.length > 0) {
                                TaildropService.send(paths, peerCard.modelData)
                                drop.accept(Qt.CopyAction)
                            }
                        }
                    }
                }
            }
        }
    }
}
