import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Common
import qs.Services
import qs.Widgets

// Agents drill view (the vibe-island port): one card per coding-agent session —
// live tool feed, elapsed time, Allow/Deny for permission requests, one-click
// question answers, and jump-back to the terminal that asked.
Column {
    id: agCol
    property var island: null
    anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
    spacing: Theme.spacingS
    opacity: island.panelView === "agents" ? 1 : 0
    visible: opacity > 0
    transform: Translate { x: island.panelView === "agents" ? 0 : 24; Behavior on x { NumberAnimation { duration: Theme.shortDuration; easing.type: Easing.OutQuad } } }
    Behavior on opacity { NumberAnimation { duration: Theme.shortDuration } }

    function stateLabel(s) {
        if (s.state === "waiting")
            return s.pending && s.pending.kind === "question" ? I18n.tr("has a question") : I18n.tr("needs approval")
        if (s.state === "done")
            return I18n.tr("done · click to jump")
        return (AgentService.verbFor("agent-" + s.id) || I18n.tr("working")) + "… · " + AgentService.elapsed(s)
    }
    function resetTime(block) {
        return block && block.resets_at ? Qt.formatTime(new Date(block.resets_at * 1000), "HH:mm") : ""
    }

    DrillHeader { island: agCol.island; title: I18n.tr("Agents") }

    // ---- usage quota + attention mode ----
    RowLayout {
        width: parent.width
        spacing: Theme.spacingS
        StyledText {
            Layout.fillWidth: true
            visible: AgentService.usage !== null
            text: {
                const u = AgentService.usage
                if (!u) return ""
                let parts = []
                if (u.five) parts.push("5h " + Math.round(u.five.used_percentage) + "%" + (agCol.resetTime(u.five) ? " ⟳" + agCol.resetTime(u.five) : ""))
                if (u.seven) parts.push("7d " + Math.round(u.seven.used_percentage) + "%")
                return "Claude · " + parts.join(" · ")
            }
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
            elide: Text.ElideRight
        }
        Item { Layout.fillWidth: AgentService.usage === null; visible: AgentService.usage === null; height: 1 }
        Repeater {
            model: [
                { key: "focus",  ic: "center_focus_strong", tip: I18n.tr("Follow focus — open the island when an agent needs you") },
                { key: "notify", ic: "notifications",       tip: I18n.tr("Notify me — splash when an agent needs you") },
                { key: "silent", ic: "notifications_off",   tip: I18n.tr("Stay silent — only tint the pill") }
            ]
            delegate: Rectangle {
                required property var modelData
                readonly property bool on: SessionData.agentApprovalMode === modelData.key
                width: 30; height: 24; radius: 12
                color: on ? Theme.primaryHover : modeArea.containsMouse ? Theme.surfaceLight : "transparent"
                DankIcon { anchors.centerIn: parent; name: parent.modelData.ic; size: 14; color: parent.on ? Theme.primary : Theme.surfaceVariantText }
                MouseArea {
                    id: modeArea
                    anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                    onClicked: SessionData.setAgentApprovalMode(parent.modelData.key)
                    ToolTip.visible: containsMouse
                    ToolTip.delay: 400
                    ToolTip.text: parent.modelData.tip
                }
            }
        }
    }

    // ---- fleet summary + bulk actions (multi-session management) ----
    RowLayout {
        width: parent.width
        spacing: Theme.spacingS
        visible: AgentService.sessions.length > 1
        StyledText {
            Layout.fillWidth: true
            text: {
                let bits = []
                if (AgentService.waitingCount) bits.push(AgentService.waitingCount + " " + I18n.tr("waiting"))
                if (AgentService.workingCount) bits.push(AgentService.workingCount + " " + I18n.tr("working"))
                if (AgentService.doneCount) bits.push(AgentService.doneCount + " " + I18n.tr("done"))
                return bits.join(" · ")
            }
            font.pixelSize: Theme.fontSizeSmall
            color: AgentService.waitingCount > 0 ? Theme.warning : Theme.surfaceVariantText
            elide: Text.ElideRight
            maximumLineCount: 1
        }
        DankButton {
            visible: AgentService.pendingPermCount > 1
            text: I18n.tr("Allow all")
            buttonHeight: 24; radius: buttonHeight / 2
            backgroundColor: Theme.primary
            textColor: Theme.primaryText
            onClicked: AgentService.allowAll()
        }
        DankButton {
            visible: AgentService.doneCount > 0
            text: I18n.tr("Clear done")
            buttonHeight: 24; radius: buttonHeight / 2
            backgroundColor: Theme.surfaceLight
            textColor: Theme.surfaceText
            onClicked: AgentService.clearDone()
        }
    }

    // ---- empty state: point at the one-time hook install ----
    Column {
        width: parent.width
        visible: AgentService.sessions.length === 0
        spacing: Theme.spacingM
        topPadding: Theme.spacingM
        StyledText {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: I18n.tr("No agent sessions")
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
        }
        DankButton {
            anchors.horizontalCenter: parent.horizontalCenter
            text: I18n.tr("Install Claude Code hooks")
            iconName: "link"
            iconSize: 14
            buttonHeight: 30
            radius: buttonHeight / 2
            onClicked: Quickshell.execDetached([AgentService.scriptsDir + "/dms-agent-install"])
        }
        StyledText {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: I18n.tr("One-time, idempotent — new claude sessions then appear here.")
            font.pixelSize: Theme.fontSizeSmall - 2
            color: Theme.surfaceVariantText
        }
    }

    // ---- session cards ----
    Repeater {
        model: AgentService.sorted
        delegate: Rectangle {
            id: card
            required property var modelData
            readonly property bool waiting: modelData.state === "waiting"
            width: parent.width
            height: cardCol.implicitHeight + Theme.spacingS * 2
            radius: Theme.cornerRadius
            color: Theme.surfaceContainerHighest
            border.width: waiting ? 1 : 0
            border.color: Theme.warning

            MouseArea { // whole card jumps back to the owning terminal
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: AgentService.jump(card.modelData.id)
            }

            Column {
                id: cardCol
                anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                anchors.margins: Theme.spacingS
                spacing: Theme.spacingXS

                RowLayout {
                    width: parent.width
                    spacing: Theme.spacingS
                    DankIcon {
                        name: card.modelData.state === "done" ? "check_circle" : card.waiting ? "front_hand" : AgentService.iconFor(card.modelData.agent)
                        size: 18
                        color: card.modelData.state === "done" ? Theme.success : card.waiting ? Theme.warning : Theme.primary
                        Layout.alignment: Qt.AlignVCenter
                    }
                    Column {
                        Layout.fillWidth: true
                        spacing: 1
                        StyledText {
                            width: parent.width
                            text: card.modelData.title
                            font.pixelSize: Theme.fontSizeSmall
                            font.weight: Font.Bold
                            color: Theme.surfaceText
                            elide: Text.ElideRight
                            maximumLineCount: 1
                        }
                        StyledText {
                            width: parent.width
                            text: {
                                let bits = [agCol.stateLabel(card.modelData)]
                                if (card.modelData.agent && card.modelData.agent !== "claude") bits.push(card.modelData.agent)
                                const dir = (card.modelData.cwd || "").split("/").pop()
                                if (dir) bits.push(dir)
                                if (card.modelData.model) bits.push(card.modelData.model)
                                if (card.modelData.ctx >= 0) bits.push(I18n.tr("ctx") + " " + Math.round(card.modelData.ctx) + "%")
                                return bits.join(" · ")
                            }
                            font.pixelSize: Theme.fontSizeSmall - 2
                            color: card.waiting ? Theme.warning : Theme.surfaceVariantText
                            elide: Text.ElideRight
                            maximumLineCount: 1
                        }
                    }
                    DankActionButton {
                        visible: card.modelData.state === "working" && card.modelData.apid > 0
                        iconName: "stop_circle"
                        buttonSize: 24; iconSize: 14
                        radius: buttonSize / 2
                        iconColor: Theme.error
                        onClicked: AgentService.interrupt(card.modelData.id)
                        tooltipText: I18n.tr("Interrupt the running turn (Esc)")
                    }
                    DankActionButton {
                        iconName: "jump_to_element"
                        buttonSize: 24; iconSize: 14
                        radius: buttonSize / 2
                        iconColor: Theme.surfaceVariantText
                        onClicked: AgentService.jump(card.modelData.id)
                    }
                    DankActionButton {
                        iconName: "close"
                        buttonSize: 24; iconSize: 14
                        radius: buttonSize / 2
                        iconColor: Theme.surfaceVariantText
                        onClicked: AgentService.remove(card.modelData.id)
                    }
                }

                // ---- live tool feed ----
                Repeater {
                    model: card.waiting ? [] : card.modelData.feed.slice(0, 4)
                    delegate: StyledText {
                        required property var modelData
                        required property int index
                        width: parent.width
                        text: modelData.tool + (modelData.detail ? " · " + modelData.detail : "")
                              + (modelData.plus || modelData.minus ? "  +" + modelData.plus + " −" + modelData.minus : "")
                        font.pixelSize: Theme.fontSizeSmall - 2
                        font.family: Theme.monoFontFamily
                        color: Theme.surfaceVariantText
                        opacity: 1.0 - index * 0.18
                        elide: Text.ElideRight
                        maximumLineCount: 1
                    }
                }

                // ---- pending permission request ----
                Column {
                    width: parent.width
                    visible: card.modelData.pending && card.modelData.pending.kind === "permission"
                    spacing: Theme.spacingS
                    Rectangle {
                        width: parent.width
                        height: permText.implicitHeight + Theme.spacingS * 2
                        radius: Theme.cornerRadius / 2
                        color: Theme.surfaceLight
                        StyledText {
                            id: permText
                            anchors.fill: parent
                            anchors.margins: Theme.spacingS
                            text: card.modelData.pending ? card.modelData.pending.tool + "\n" + card.modelData.pending.detail : ""
                            font.pixelSize: Theme.fontSizeSmall - 2
                            font.family: Theme.monoFontFamily
                            color: Theme.surfaceText
                            wrapMode: Text.WrapAnywhere
                            maximumLineCount: 8
                            elide: Text.ElideRight
                        }
                    }
                    Row {
                        anchors.right: parent.right
                        spacing: Theme.spacingS
                        DankButton {
                            text: I18n.tr("Deny")
                            buttonHeight: 28; radius: buttonHeight / 2
                            backgroundColor: Qt.rgba(Theme.error.r, Theme.error.g, Theme.error.b, 0.15)
                            textColor: Theme.error
                            onClicked: AgentService.decide(card.modelData.id, "deny")
                        }
                        DankButton {
                            text: I18n.tr("Terminal")
                            buttonHeight: 28; radius: buttonHeight / 2
                            backgroundColor: Theme.surfaceLight
                            textColor: Theme.surfaceText
                            onClicked: {
                                AgentService.decide(card.modelData.id, "pass")
                                AgentService.jump(card.modelData.id)
                            }
                        }
                        DankButton {
                            text: I18n.tr("Allow")
                            buttonHeight: 28; radius: buttonHeight / 2
                            backgroundColor: Theme.primary
                            textColor: Theme.primaryText
                            onClicked: AgentService.decide(card.modelData.id, "allow")
                        }
                    }
                }

                // ---- pending question(s): one-click, multi-select, multi-question ----
                Column {
                    id: qWrap
                    width: parent.width
                    visible: card.modelData.pending && card.modelData.pending.kind === "question"
                    spacing: Theme.spacingS
                    readonly property var pend: card.modelData.pending
                    // a lone single-select question answers on first click; anything
                    // richer collects picks and submits explicitly
                    readonly property bool oneShot: pend && pend.kind === "question" && pend.questions.length === 1 && !pend.questions[0].multi

                    Repeater {
                        model: qWrap.pend && qWrap.pend.kind === "question" ? qWrap.pend.questions : []
                        delegate: Column {
                            id: qBlock
                            required property var modelData
                            required property int index
                            width: parent.width
                            spacing: Theme.spacingXS
                            StyledText {
                                width: parent.width
                                text: qBlock.modelData.q + (qBlock.modelData.multi ? " · " + I18n.tr("pick any") : "")
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceText
                                wrapMode: Text.WordWrap
                            }
                            Repeater {
                                model: qBlock.modelData.opts
                                delegate: DankButton {
                                    required property var modelData
                                    readonly property bool picked: ((qWrap.pend && qWrap.pend.sel && qWrap.pend.sel[qBlock.index]) || []).indexOf(modelData) >= 0
                                    width: parent.width
                                    text: (picked ? "✓ " : "") + modelData
                                    buttonHeight: 28; radius: buttonHeight / 2
                                    backgroundColor: picked ? Theme.primaryHover : hovered ? Theme.primaryHover : Theme.surfaceLight
                                    textColor: picked || hovered ? Theme.primary : Theme.surfaceText
                                    onClicked: qWrap.oneShot
                                        ? AgentService.answer(card.modelData.id, modelData)
                                        : AgentService.toggleOpt(card.modelData.id, qBlock.index, modelData)
                                }
                            }
                        }
                    }
                    Row {
                        anchors.right: parent.right
                        spacing: Theme.spacingS
                        DankButton {
                            text: I18n.tr("Answer in terminal")
                            buttonHeight: 26; radius: buttonHeight / 2
                            backgroundColor: "transparent"
                            textColor: Theme.surfaceVariantText
                            onClicked: {
                                AgentService.decide(card.modelData.id, "pass")
                                AgentService.jump(card.modelData.id)
                            }
                        }
                        DankButton {
                            visible: !qWrap.oneShot
                            enabled: AgentService.canSubmit(card.modelData)
                            opacity: enabled ? 1 : 0.4
                            text: I18n.tr("Submit")
                            buttonHeight: 28; radius: buttonHeight / 2
                            backgroundColor: Theme.primary
                            textColor: Theme.primaryText
                            onClicked: AgentService.submitAnswers(card.modelData.id)
                        }
                    }
                }
            }
        }
    }
}
