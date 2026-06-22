import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Common
import qs.Widgets
import "QuizEngine.js" as QuizEngine

PanelWindow {
    id: overlay

    property var question: null
    property string nudge: "Quiz dispo"
    property string emoji: "🦉"
    property int animIndex: 0       // 0..13 — voir les animations dans la pastille
    readonly property int animCount: 14
    signal dismissed()
    signal snoozeRequested(int ms)
    signal onboardingComplete(var ids, var customs)
    signal lessonDone()
    signal quizAnswered()
    signal askQuestion(string question)

    property var lesson: null
    property string contentType: "quiz" // "quiz" | "lesson"
    property string lessonAnswer: ""
    property bool lessonAnswering: false

    property string mode: "hidden" // "hidden"|"pending"|"open"|"feedback"|"onboarding"
    property int selected: -1

    onAnimIndexChanged: pill.resetPillTransforms()
    onModeChanged: {
        if (overlay.mode === "pending")
            pill.resetPillTransforms();
        if (overlay.mode === "open" || overlay.mode === "feedback")
            content.forceActiveFocus();
    }

    function showPending() { overlay.selected = -1; overlay.mode = "pending"; overlay.visible = true; }
    function showOnboarding() { overlay.mode = "onboarding"; overlay.visible = true; }
    function reset() { overlay.mode = "hidden"; overlay.selected = -1; overlay.visible = false; overlay.dismissed(); }

    color: "transparent"
    visible: false

    WlrLayershell.namespace: "dms:quiz"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.exclusiveZone: -1
    // La pastille (pending) ne doit JAMAIS prendre le focus clavier : sinon, quand elle se mappe
    // pendant que tu tapes dans un champ, Hyprland lui donne le focus (layer OnDemand) et tu perds
    // ta saisie. Seules les cartes ouvertes (Q&A de leçon, onboarding) — ouvertes par un clic — en
    // ont besoin. None en pending/hidden, OnDemand une fois ouvert.
    WlrLayershell.keyboardFocus: (overlay.mode === "hidden" || overlay.mode === "pending") ? WlrKeyboardFocus.None : WlrKeyboardFocus.OnDemand

    anchors { bottom: true; right: true }
    WlrLayershell.margins { bottom: Theme.spacingL; right: Theme.spacingL }

    // Marge autour du contenu pour que l'ombre d'ElevationShadow ne soit pas clippée par la fenêtre.
    readonly property real shadowPad: 28

    implicitWidth: content.implicitWidth + overlay.shadowPad * 2
    implicitHeight: content.implicitHeight + overlay.shadowPad * 2

    Item {
        id: content
        focus: true
        Keys.onPressed: (event) => {
            var token;
            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                token = "ENTER";
            else if (event.key === Qt.Key_Escape)
                token = "ESC";
            else if (event.text && event.text.length === 1)
                token = event.text.toUpperCase();
            else
                return;
            var act = QuizEngine.keyAction(token, overlay.mode, overlay.contentType, lessonCard.inputActive);
            if (act === "")
                return;
            event.accepted = true;
            if (act.indexOf("select") === 0) {
                var i = Number(act.charAt(6));
                if (overlay.question && overlay.question.choices && i < overlay.question.choices.length)
                    overlay.selected = i;
            } else if (act === "submit") {
                if (overlay.selected >= 0) { overlay.mode = "feedback"; overlay.quizAnswered(); }
            } else if (act === "next") {
                overlay.lessonDone(); overlay.reset();
            } else if (act === "ask") {
                lessonCard.openAsk();
            } else if (act === "closeAsk") {
                lessonCard.closeAsk();
                content.forceActiveFocus(); // masquer le champ focalisé perd le focus clavier → le regagner, sinon la nav (N/Échap) devient morte
            } else if (act === "snooze") {
                overlay.snoozeRequested(300000); overlay.reset();
            } else if (act === "close") {
                overlay.reset();
            }
        }
        anchors.fill: parent
        anchors.margins: overlay.shadowPad
        implicitWidth: onboardingCard.visible ? onboardingCard.implicitWidth
                       : lessonCard.visible ? lessonCard.implicitWidth
                       : card.visible ? card.implicitWidth : pill.implicitWidth
        implicitHeight: onboardingCard.visible ? onboardingCard.implicitHeight
                        : lessonCard.visible ? lessonCard.implicitHeight
                        : card.visible ? card.implicitHeight : pill.implicitHeight
        opacity: overlay.mode === "hidden" ? 0 : 1
        scale: overlay.mode === "hidden" ? 0.9 : 1
        Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
        Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

        StyledRect { // pastille
            id: pill
            visible: overlay.mode === "pending"
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            implicitWidth: pillRow.implicitWidth + Theme.spacingM * 2
            implicitHeight: pillRow.implicitHeight + Theme.spacingS * 2
            radius: Theme.cornerRadius
            color: Theme.surfaceContainerHigh
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.14)

            ElevationShadow {
                anchors.fill: parent
                z: -1
                level: Theme.elevationLevel2
                targetRadius: pill.radius
                targetColor: pill.color
                borderColor: pill.border.color
                borderWidth: pill.border.width
                shadowEnabled: Theme.elevationEnabled && SettingsData.popoutElevationEnabled
            }

            // --- Animations d'attention variées (index aléatoire par message), façon Duolingo ---
            transform: [
                Translate { id: animTrans },
                Rotation { id: animRot; origin.x: pill.width / 2; origin.y: 0 },
                Scale { id: animScale; origin.x: pill.width / 2; origin.y: pill.height / 2 }
            ]

            function resetPillTransforms() {
                animTrans.x = 0;
                animTrans.y = 0;
                animRot.angle = 0;
                animScale.xScale = 1;
                animScale.yScale = 1;
            }

            // 0 — Bounce 🦘
            SequentialAnimation {
                running: overlay.mode === "pending" && overlay.animIndex === 0
                loops: Animation.Infinite
                NumberAnimation { target: animTrans; property: "y"; from: 0; to: -12; duration: 240; easing.type: Easing.OutQuad }
                NumberAnimation { target: animTrans; property: "y"; to: 0; duration: 520; easing.type: Easing.OutBounce }
                PauseAnimation { duration: 2200 }
            }

            // 1 — Shake 🫨
            SequentialAnimation {
                running: overlay.mode === "pending" && overlay.animIndex === 1
                loops: Animation.Infinite
                SequentialAnimation {
                    loops: 3
                    NumberAnimation { target: animRot; property: "angle"; to: 7; duration: 70 }
                    NumberAnimation { target: animRot; property: "angle"; to: -7; duration: 70 }
                }
                NumberAnimation { target: animRot; property: "angle"; to: 0; duration: 70 }
                PauseAnimation { duration: 2400 }
            }

            // 2 — Pulse 💓
            SequentialAnimation {
                running: overlay.mode === "pending" && overlay.animIndex === 2
                loops: Animation.Infinite
                SequentialAnimation {
                    loops: 2
                    ParallelAnimation {
                        NumberAnimation { target: animScale; property: "xScale"; to: 1.12; duration: 180; easing.type: Easing.OutQuad }
                        NumberAnimation { target: animScale; property: "yScale"; to: 1.12; duration: 180; easing.type: Easing.OutQuad }
                    }
                    ParallelAnimation {
                        NumberAnimation { target: animScale; property: "xScale"; to: 1.0; duration: 220; easing.type: Easing.InQuad }
                        NumberAnimation { target: animScale; property: "yScale"; to: 1.0; duration: 220; easing.type: Easing.InQuad }
                    }
                }
                PauseAnimation { duration: 2200 }
            }

            // 3 — Swing 🎐
            SequentialAnimation {
                running: overlay.mode === "pending" && overlay.animIndex === 3
                loops: Animation.Infinite
                NumberAnimation { target: animRot; property: "angle"; to: 10; duration: 200; easing.type: Easing.OutQuad }
                NumberAnimation { target: animRot; property: "angle"; to: -7; duration: 280; easing.type: Easing.InOutQuad }
                NumberAnimation { target: animRot; property: "angle"; to: 4; duration: 240; easing.type: Easing.InOutQuad }
                NumberAnimation { target: animRot; property: "angle"; to: 0; duration: 200; easing.type: Easing.OutQuad }
                PauseAnimation { duration: 2400 }
            }

            // 4 — Tada 🎉
            SequentialAnimation {
                running: overlay.mode === "pending" && overlay.animIndex === 4
                loops: Animation.Infinite
                ParallelAnimation {
                    NumberAnimation { target: animScale; property: "xScale"; to: 0.9; duration: 150 }
                    NumberAnimation { target: animScale; property: "yScale"; to: 0.9; duration: 150 }
                }
                SequentialAnimation {
                    loops: 3
                    ParallelAnimation {
                        NumberAnimation { target: animScale; property: "xScale"; to: 1.1; duration: 90 }
                        NumberAnimation { target: animScale; property: "yScale"; to: 1.1; duration: 90 }
                        NumberAnimation { target: animRot; property: "angle"; to: 4; duration: 90 }
                    }
                    NumberAnimation { target: animRot; property: "angle"; to: -4; duration: 90 }
                }
                ParallelAnimation {
                    NumberAnimation { target: animScale; property: "xScale"; to: 1.0; duration: 150 }
                    NumberAnimation { target: animScale; property: "yScale"; to: 1.0; duration: 150 }
                    NumberAnimation { target: animRot; property: "angle"; to: 0; duration: 150 }
                }
                PauseAnimation { duration: 2400 }
            }

            // 5 — Heartbeat 💗
            SequentialAnimation {
                running: overlay.mode === "pending" && overlay.animIndex === 5
                loops: Animation.Infinite
                ParallelAnimation {
                    NumberAnimation { target: animScale; property: "xScale"; to: 1.16; duration: 120; easing.type: Easing.OutQuad }
                    NumberAnimation { target: animScale; property: "yScale"; to: 1.16; duration: 120; easing.type: Easing.OutQuad }
                }
                ParallelAnimation {
                    NumberAnimation { target: animScale; property: "xScale"; to: 1.0; duration: 110; easing.type: Easing.InQuad }
                    NumberAnimation { target: animScale; property: "yScale"; to: 1.0; duration: 110; easing.type: Easing.InQuad }
                }
                ParallelAnimation {
                    NumberAnimation { target: animScale; property: "xScale"; to: 1.16; duration: 120; easing.type: Easing.OutQuad }
                    NumberAnimation { target: animScale; property: "yScale"; to: 1.16; duration: 120; easing.type: Easing.OutQuad }
                }
                ParallelAnimation {
                    NumberAnimation { target: animScale; property: "xScale"; to: 1.0; duration: 200; easing.type: Easing.InQuad }
                    NumberAnimation { target: animScale; property: "yScale"; to: 1.0; duration: 200; easing.type: Easing.InQuad }
                }
                PauseAnimation { duration: 1900 }
            }

            // 6 — Rubber (squash & stretch) 🟪
            SequentialAnimation {
                running: overlay.mode === "pending" && overlay.animIndex === 6
                loops: Animation.Infinite
                ParallelAnimation {
                    NumberAnimation { target: animScale; property: "xScale"; to: 1.25; duration: 180; easing.type: Easing.OutQuad }
                    NumberAnimation { target: animScale; property: "yScale"; to: 0.78; duration: 180; easing.type: Easing.OutQuad }
                }
                ParallelAnimation {
                    NumberAnimation { target: animScale; property: "xScale"; to: 0.85; duration: 180 }
                    NumberAnimation { target: animScale; property: "yScale"; to: 1.18; duration: 180 }
                }
                ParallelAnimation {
                    NumberAnimation { target: animScale; property: "xScale"; to: 1.0; duration: 260; easing.type: Easing.OutBounce }
                    NumberAnimation { target: animScale; property: "yScale"; to: 1.0; duration: 260; easing.type: Easing.OutBounce }
                }
                PauseAnimation { duration: 2200 }
            }

            // 7 — Float 🎈 (flottement doux)
            SequentialAnimation {
                running: overlay.mode === "pending" && overlay.animIndex === 7
                loops: Animation.Infinite
                NumberAnimation { target: animTrans; property: "y"; to: -7; duration: 900; easing.type: Easing.InOutSine }
                NumberAnimation { target: animTrans; property: "y"; to: 0; duration: 900; easing.type: Easing.InOutSine }
            }

            // 8 — Headshake ↔️
            SequentialAnimation {
                running: overlay.mode === "pending" && overlay.animIndex === 8
                loops: Animation.Infinite
                SequentialAnimation {
                    loops: 3
                    NumberAnimation { target: animTrans; property: "x"; to: -8; duration: 80 }
                    NumberAnimation { target: animTrans; property: "x"; to: 8; duration: 80 }
                }
                NumberAnimation { target: animTrans; property: "x"; to: 0; duration: 80 }
                PauseAnimation { duration: 2400 }
            }

            // 9 — Wobble 〰️ (x + rotation)
            SequentialAnimation {
                running: overlay.mode === "pending" && overlay.animIndex === 9
                loops: Animation.Infinite
                ParallelAnimation {
                    NumberAnimation { target: animTrans; property: "x"; to: -8; duration: 150 }
                    NumberAnimation { target: animRot; property: "angle"; to: -6; duration: 150 }
                }
                ParallelAnimation {
                    NumberAnimation { target: animTrans; property: "x"; to: 6; duration: 200 }
                    NumberAnimation { target: animRot; property: "angle"; to: 5; duration: 200 }
                }
                ParallelAnimation {
                    NumberAnimation { target: animTrans; property: "x"; to: 0; duration: 200; easing.type: Easing.OutQuad }
                    NumberAnimation { target: animRot; property: "angle"; to: 0; duration: 200; easing.type: Easing.OutQuad }
                }
                PauseAnimation { duration: 2300 }
            }

            // 10 — Pop ✨ (overshoot net)
            SequentialAnimation {
                running: overlay.mode === "pending" && overlay.animIndex === 10
                loops: Animation.Infinite
                ParallelAnimation {
                    NumberAnimation { target: animScale; property: "xScale"; to: 1.28; duration: 140; easing.type: Easing.OutBack }
                    NumberAnimation { target: animScale; property: "yScale"; to: 1.28; duration: 140; easing.type: Easing.OutBack }
                }
                ParallelAnimation {
                    NumberAnimation { target: animScale; property: "xScale"; to: 1.0; duration: 260; easing.type: Easing.OutBack }
                    NumberAnimation { target: animScale; property: "yScale"; to: 1.0; duration: 260; easing.type: Easing.OutBack }
                }
                PauseAnimation { duration: 2200 }
            }

            // 11 — Tilt (penche et revient)
            SequentialAnimation {
                running: overlay.mode === "pending" && overlay.animIndex === 11
                loops: Animation.Infinite
                NumberAnimation { target: animRot; property: "angle"; to: 12; duration: 260; easing.type: Easing.OutQuad }
                PauseAnimation { duration: 500 }
                NumberAnimation { target: animRot; property: "angle"; to: 0; duration: 260; easing.type: Easing.OutQuad }
                PauseAnimation { duration: 2200 }
            }

            // 12 — Jump-twist 🤸 (saut + petite vrille)
            SequentialAnimation {
                running: overlay.mode === "pending" && overlay.animIndex === 12
                loops: Animation.Infinite
                ParallelAnimation {
                    NumberAnimation { target: animTrans; property: "y"; to: -14; duration: 220; easing.type: Easing.OutQuad }
                    NumberAnimation { target: animRot; property: "angle"; to: 8; duration: 220; easing.type: Easing.OutQuad }
                }
                ParallelAnimation {
                    NumberAnimation { target: animTrans; property: "y"; to: 0; duration: 520; easing.type: Easing.OutBounce }
                    NumberAnimation { target: animRot; property: "angle"; to: 0; duration: 520; easing.type: Easing.OutBounce }
                }
                PauseAnimation { duration: 2200 }
            }

            // 13 — Metronome ⏱ (tic-tac régulier)
            SequentialAnimation {
                running: overlay.mode === "pending" && overlay.animIndex === 13
                loops: Animation.Infinite
                SequentialAnimation {
                    loops: 4
                    NumberAnimation { target: animRot; property: "angle"; to: 12; duration: 260; easing.type: Easing.InOutSine }
                    NumberAnimation { target: animRot; property: "angle"; to: -12; duration: 260; easing.type: Easing.InOutSine }
                }
                NumberAnimation { target: animRot; property: "angle"; to: 0; duration: 200; easing.type: Easing.OutQuad }
                PauseAnimation { duration: 2000 }
            }

            Row {
                id: pillRow
                anchors.centerIn: parent
                spacing: Theme.spacingXS
                StyledText { text: overlay.emoji; font.pixelSize: Theme.fontSizeLarge; anchors.verticalCenter: parent.verticalCenter }
                StyledText { text: overlay.nudge; font.pixelSize: Theme.fontSizeMedium; color: Theme.surfaceText; anchors.verticalCenter: parent.verticalCenter }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: overlay.mode = "open"
            }
        }

        QuizCard { // carte quiz
            id: card
            visible: (overlay.mode === "open" || overlay.mode === "feedback") && overlay.contentType === "quiz"
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            question: overlay.question
            mode: overlay.mode === "feedback" ? "feedback" : "open"
            selected: overlay.selected
            onSelect: (i) => overlay.selected = i
            onSubmit: { overlay.mode = "feedback"; overlay.quizAnswered(); }
            onClose: overlay.reset()
            onSnooze: (ms) => { overlay.snoozeRequested(ms); overlay.reset(); }
        }

        LessonCard { // carte leçon (mode apprentissage)
            id: lessonCard
            visible: overlay.mode === "open" && overlay.contentType === "lesson"
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            lesson: overlay.lesson
            answer: overlay.lessonAnswer
            answering: overlay.lessonAnswering
            onNext: {
                overlay.lessonDone();
                overlay.reset();
            }
            onClose: overlay.reset()
            onSnooze: (ms) => { overlay.snoozeRequested(ms); overlay.reset(); }
            onAsk: (q) => overlay.askQuestion(q)
        }

        QuizOnboardingCard { // setup au 1er lancement
            id: onboardingCard
            visible: overlay.mode === "onboarding"
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            onStart: (ids, customs) => {
                overlay.onboardingComplete(ids, customs);
                overlay.mode = "hidden";
                overlay.visible = false;
            }
        }
    }
}
