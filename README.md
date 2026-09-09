# Easy Capture

Turn any moment on your screen into a screenshot or recording. Capture regions, apps, or monitors from your Omarchy bar, with optional desktop sound, microphone selection, and app capture across screens.

![Easy Capture showing the Record tab, capture targets, audio controls, and microphone input selection](preview.png)

Captures stay on your computer. Audio is off until you enable it.

## New in 0.3.0

- A custom outline camera icon and compact Screenshot / Record tabs.
- Region, App, and Monitor targets with an explicit **Capture!** button.
- Independent desktop sound and microphone controls, with red muted icons when off.
- A microphone input picker when multiple inputs are available.
- App selection across monitors, including visible special-workspace and pinned windows.
- Steady hover colors, keyboard navigation, and a recording timer with click-to-stop.

## Install

```sh
omarchy plugin add https://github.com/chyld/omarchy-easy-capture.git --enable
```

The plugin uses Omarchy/Quickshell, Hyprland, `bash`, `jq`, `slurp`, `hyprpicker`,
`grim`, `wl-copy`, `gpu-screen-recorder`, and `pactl`, along with Omarchy's capture
and notification helpers.

## Update

```sh
omarchy plugin update chyld.easy-capture
omarchy restart shell
```

Restart the shell after updating so the dialog loads the latest QML components.

## Remove

Stop any recording before removing the plugin:

```sh
omarchy plugin remove chyld.easy-capture
```

Removal deletes the plugin files at
`~/.config/omarchy/plugins/chyld.easy-capture/`. Saved screenshots and recordings
remain in their output directories. The plugin creates no credentials or
separate persistent settings store.

## What it shows

- A camera icon that opens the capture dialog.
- **Screenshot** and **Record** tabs, each with Region, App, and Monitor targets.
- A monitor list when you need to choose between displays.
- Desktop sound and microphone toggles under Record; muted icons are red.
- Named microphone inputs plus **System default** when multiple inputs are available.
- A pulsing red dot and elapsed timer while recording; click the camera to stop.

Select the target, adjust audio if recording, and click **Capture!** Changing a
tab or target alone does not start a capture. Region and App open the selection
tool after the dialog closes; Monitor starts immediately after that delay.

Tab/Shift+Tab move through controls. Arrows or h/j/k/l navigate within and between
sections. Enter or Space activates the highlighted control; Escape closes the dialog.

## When it refreshes

Monitor and microphone lists refresh when the dialog opens. Microphones also
refresh when you select Record or enable Microphone, and every three seconds
while the Record dialog is open with Microphone enabled.

Speaker-monitor sources are excluded from the microphone picker. With one input,
its name is shown without a picker. If a selected input disconnects, the selection
returns to System default with a notice.

Tab, target, and audio choices stay in memory while the widget is loaded and
reset on shell restart. Recording state belongs to each widget instance.

## Capturing and recording

App selection includes visible windows on every enabled monitor, regardless of
which monitor you started from. Hidden workspaces and hidden or unmapped windows
are excluded. Region selection supports a freeform rectangle. A single monitor
is selected automatically for the Monitor target.

Desktop sound uses the system's default output. Microphone recording uses the
system default input or your chosen device. Enabling both mixes them into a single
AAC track so playback includes both sources.

The recorder uses 60 FPS and Omarchy's default video encoding options. Monitor
recordings larger than 3840×2160 are capped. There is no webcam, desktop-output
device selector, or video-quality setting.

The stop command sends SIGINT so the recorder can finalize the file. It currently
matches `gpu-screen-recorder` processes by name, so it can also stop a recording
started elsewhere.

## Data, network, and execution

Screenshots are saved under `~/Pictures` or `$OMARCHY_SCREENSHOT_DIR`, and copied
to the clipboard. Recordings are saved under `~/Videos` or
`$OMARCHY_SCREENRECORD_DIR`. XDG picture/video directory settings are also
respected. Completion notifications identify the saved file; recording
notifications offer playback through `mpv`.

The plugin has no upload or analytics client. It reads monitor and window metadata
through `hyprctl` and audio-source metadata through `pactl`. Capture commands
inherit the shell environment and read `~/.config/user-dirs.dirs` when present.

Region selection uses `omarchy-capture-region`. App selection uses
`capture-region.sh`, a local copy of the installed Omarchy helper adapted to
include windows across monitors. The packaged helper is unchanged. Selection
uses `hyprpicker` and `slurp`; screenshots use `grim` and `wl-copy`; recordings
use `gpu-screen-recorder`. Target and audio values are passed as shell positional
arguments. Capture waits 200 ms for the popup to fade out before selection begins.

Quickshell manages its own runtime logs and QML cache, which can survive plugin
removal. Saved captures and the screenshot clipboard contents also outlive the
plugin's in-memory state.

## Development

```sh
node --test tests/audio_devices.test.js
python3 tests/audio_test.py
python3 tests/picker_test.py
omarchy plugin validate .
# Requires a running Wayland session and Omarchy/Quickshell.
# Uses a fake capture host; does not record the screen or audio.
python3 tests/interface_test.py
```

The tests cover audio-source filtering, recorder arguments, cross-monitor picker
candidates, cancellation, and QML controls and keyboard navigation. Plugin files
normally hot-reload; restart the shell when a dialog shows stale components.

## License

[MIT](LICENSE). The adapted Omarchy picker retains its [upstream MIT notice](LICENSE.omarchy).
