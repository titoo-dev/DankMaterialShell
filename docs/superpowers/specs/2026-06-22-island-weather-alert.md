# Weather alert pop (#9) — design + plan

**Date:** 2026-06-22 · **Status:** approved · **Branch:** `feat/dynamic-island`

## Scope
Open-Meteo (the WeatherService source) has no severe-weather *alert feed*, so v1 pops a
live-activity splash when the WMO `wCode` enters a **severe set** (heavy rain/snow,
violent showers, thunderstorm). Uses the existing `pushActivity` splash + the existing
`getWeatherIcon`/`getWeatherCondition`. No new service; relies on weather already being
populated by existing consumers (the bar weather widget refs WeatherService).

## Approach (in `DynamicIsland.qml`)
- Setting `SettingsData.islandWeatherAlerts` (default true).
- `property int _lastWeatherAlertCode: 0` (de-dupe guard).
- `Connections { target: WeatherService; onWeatherChanged }`:
  - if `SettingsData.islandWeatherAlerts && root.ready && WeatherService.weather.available`:
    - `c = WeatherService.weather.wCode`; severe = `[65,75,82,86,95,96,99].indexOf(c) !== -1`.
    - if severe && `c !== _lastWeatherAlertCode` → `pushActivity(WeatherService.getWeatherIcon(c), I18n.tr("Weather alert") + " · " + WeatherService.getWeatherCondition(c), { priority: 2, duration: 5000 })`; `_lastWeatherAlertCode = c`.
    - else if not severe → `_lastWeatherAlertCode = 0` (so a later severe event re-alerts).

## Implementation
- [ ] SettingsData after `islandRecordingTimer`: `property bool islandWeatherAlerts: true`
- [ ] SettingsSpec after `islandRecordingTimer`: `islandWeatherAlerts: { def: true },`
- [ ] DynamicIsland: add `_lastWeatherAlertCode` + the Connections (near the other live-activity Connections).
- [ ] Verify: no QML errors; (real severe weather needed for live e2e — logic verified by construction). Optionally force by temporarily lowering the severe check.
- [ ] commit `feat(island): severe-weather alert pop (#9)`

## Edge cases
- Weather unavailable / no consumer ref → silent. De-dupe prevents repeat pops for the
  same ongoing code; resets when conditions clear. Priority-2 so it's noticeable.

## Out of scope
- A real meteorological alert/warning feed (provider-dependent).
- Configurable severe-code set.
