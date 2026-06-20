import QtQuick
import Quickshell
import qs.Common
import qs.Modules.Plugins

PluginComponent {
    id: root
    property var popoutService: null
    Component.onCompleted: console.info("QuizDaemon: started (stub)")
    Component.onDestruction: console.info("QuizDaemon: stopped")
}
