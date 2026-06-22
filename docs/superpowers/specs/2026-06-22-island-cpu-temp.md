# CPU temperature in the system monitor pane (#8) — design + plan

**Date:** 2026-06-22 · **Status:** approved · **Branch:** `feat/dynamic-island`

## Scope (honest)
The request was "GPU/temp/ventilo" in the system monitor pane. After exploration:
- **CPU temperature** is trivially available (`DgopService.cpuTemperature`, already
  populated since the monitor view refs the `cpu` module) → **delivered in v1**.
- **GPU usage/temp** needs the `gpu` module ref + per-PCI-id discovery/ref dance
  (`addGpuPciId`/`removeGpuPciId`) and depends on discrete-GPU hardware → **deferred**
  (risky to land correctly now; clean follow-up using the DankBar `GpuTemperature`
  pattern).
- **Fan RPM** is not exposed by `DgopService` → **out of scope**.

## Approach
Add a CPU-temperature subtitle under the CPU gauge in `SystemMonitorPanel.qml`. No
service change (the data already flows while the monitor view is open).

## Implementation (single task)
- [ ] In `SystemMonitorPanel.qml`, after the RAM "used/total" subtitle `StyledText`,
  add a CPU-temp subtitle:

```qml
                    // CPU temperature subtitle under the CPU gauge
                    StyledText {
                        anchors.horizontalCenter: parent.horizontalCenter
                        visible: modelData.kind === "cpu" && DgopService.cpuTemperature > 0
                        text: DgopService.cpuTemperature + "°C"
                        color: DgopService.cpuTemperature >= 85 ? Theme.error : island.subText
                        font.pixelSize: Theme.fontSizeSmall - 2
                    }
```
- [ ] Verify: open the monitor view (`dms ipc call island open monitor`) → CPU gauge
  shows "NN°C" under it; journal clean. Screenshot.
- [ ] commit `feat(island): CPU temperature in the system monitor pane (#8)`

## Edge cases
- `cpuTemperature === 0` (unavailable) → subtitle hidden. ≥85°C → red.

## Out of scope (documented follow-up)
- GPU usage/temperature (needs gpu-module + PCI-id ref plumbing).
- Fan RPM (not exposed by DgopService).
