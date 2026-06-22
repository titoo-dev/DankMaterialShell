# Bluetooth battery glanceable (#7) — design + plan

**Date:** 2026-06-22 · **Status:** approved · **Branch:** `feat/dynamic-island`

## Problem / scope
Show connected Bluetooth device battery in the island. The **Bluetooth drill panel
already shows it** (`BluetoothPanel.qml` device rows include
`Math.round(battery*100) + "%"`). The only missing piece is a **glanceable idle-row
indicator**, so #7 = add a small BT-battery chip to the idle pane.

## Approach
In `IdlePane.qml`'s `rightCluster`, add a chip (icon + lowest connected-device
battery %) shown when `BluetoothService.allDevicesWithBattery` is non-empty. Reuses
the existing `BluetoothService.allDevicesWithBattery` (devices with
`batteryAvailable && battery > 0`). No service change.

## Implementation (single task)
- [ ] In `IdlePane.qml`, after the Tailscale `Item`, add:

```qml
        Row {  // Bluetooth device battery (lowest connected device)
            spacing: 3
            anchors.verticalCenter: parent.verticalCenter
            readonly property var lowest: {
                const ds = BluetoothService.allDevicesWithBattery
                let best = null
                for (var i = 0; i < ds.length; i++)
                    if (!best || ds[i].battery < best.battery) best = ds[i]
                return best
            }
            visible: lowest !== null
            DankIcon {
                name: "bluetooth"
                size: Theme.iconSize - 7
                color: parent.lowest && parent.lowest.battery <= 0.2 ? Theme.error : island.subText
                anchors.verticalCenter: parent.verticalCenter
            }
            StyledText {
                text: parent.lowest ? Math.round(parent.lowest.battery * 100) + "%" : ""
                color: island.textColor; font.pixelSize: Theme.fontSizeSmall
                anchors.verticalCenter: parent.verticalCenter
            }
        }
```
- [ ] Verify: hover the island (idle) with a battery-reporting BT device connected →
  chip shows; journal clean. (No such device here → silent; force-render to confirm
  layout.)
- [ ] commit `feat(island): Bluetooth battery glanceable in idle row (#7)`

## Edge cases
- No battery-reporting device → silent. Lowest of several shown. ≤20% → red icon.

## Out of scope
- Per-device battery in the idle row (panel already lists all).
