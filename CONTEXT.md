# DankMaterialShell — Dynamic Island

Vocabulary for the Dynamic Island feature: a floating capsule per monitor that morphs between resting and expanded states, hosting live system state.

## Language

**Satellite**:
The small circle that detaches to the right of the resting pill to show the highest-priority ongoing observer state (screenshare, mic, camera, Tailscale attention, battery low).
_Avoid_: pin, live observer pin, bubble (alone)

**Live Activity**:
A running task with optional progress surfaced in the pill (island-run command, Pomodoro, agenda). Determinate (0–100%) or indeterminate.
_Avoid_: task, job, observer

**Splash**:
A fire-and-forget glanceable Live Activity (e.g. "Bluetooth connected"): icon + label, no progress, auto-dismisses.
_Avoid_: toast, notification

**At-rest UI**:
Island elements visible permanently without user action (pill, satellite, chip). Design rule: no infinite-loop animations here — state is shown by static color/glyph; motion only on transitions. Transient panel spinners and functional marquees are exempt.
