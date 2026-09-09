# Security review

This release was reviewed using the [Omarchy plugin security skill](https://github.com/wbso-ai/omarchy-plugin-security-skill/blob/e8e590c460c31ccebbcc5e1ca123c5c568b26f46/SKILL.md).
Reviewed skill content SHA-256: `5833649beb087c75061d41e0495f4e88cfa3e5293290eca17354cf7addd7c347`.

The review treats device names, window geometry, configuration files, child output,
and same-user filesystem interference as untrusted inputs. Applying the skill and
passing the baseline scanner are not a marketplace approval or an independent audit.

## Changes from 0.3.0

- Moved state out of individual bar widgets into one internal singleton service.
- Replaced embedded shell scripts and the copied picker with validated Python operations.
- Removed whole-output QML collectors, unbounded line parsers, shared capture markers,
  PID handoffs, global process-name signaling and shell-sourced configuration.
- Replaced timestamp-only output paths with anonymous private inodes and exclusive publication.
- Added producer byte limits, schema/depth/count limits, command deadlines, process-group
  ownership, cancellation and last-widget cleanup.
- Pinned every QML text sink to PlainText and sanitized host notification fields.
- Removed notification playback commands and image paths.
- Kept all capture/audio opt-in at the Capture! button; activation performs no capture.

## Limits

| Boundary | Limit |
| --- | --- |
| Capture request | 8 KiB, five-second input deadline, fixed keys and values |
| Raw metadata command | 1 MiB, five seconds |
| JSON tree | Depth 16, 32,768 values, 16 KiB raw strings |
| Discovered models | 16 monitors; 128 raw audio sources / 32 inputs; 512 windows |
| UI labels | Sanitized to 128 characters |
| Helper events | 32 KiB per event; QML additionally caps 128 KiB per operation |
| Picker | 120 seconds; bounded validated rectangles |
| Screenshot | 15 seconds; 256 MiB; 64 megapixels |
| Recording | 15-second startup; eight hours; 16 GiB stop threshold |
| Finalization | Ten seconds; kernel ceiling at 16 GiB + 16 MiB |
| Clipboard provider | At most eight hours, attached to the screenshot helper |
| Discovery retry | Exponential backoff, four consecutive failures |

## Verification

Automated tests exercise overflowing output, malformed/deep JSON, hostile environment
variables, unavailable devices, unsafe paths, FIFO and symlink configuration, exclusive
file publication, process groups whose leaders exit first, and unrelated processes.
QML integration uses controlled helper events to verify shared state, snapshots, input
controls, single-flight capture and last-widget cleanup. A temporary silent recording
and screenshot also exercised real tools with descriptor-backed output and verified
that the resulting video finalized; no microphone or desktop audio was recorded.

The marketplace baseline is run against the final pushed commit, using scanner revision
`1d042e9af2a25b2e8edb27dcea4bf1bc5d9e121c`. Its findings are narrower than this review.

## Trust and compatibility

System tools and the installed, reviewed plugin code remain trusted. Linux display,
audio and D-Bus endpoints are inherited from the desktop session. No remote endpoint,
credentials, privileges or package-install action is part of the plugin.

Output directories and XDG configuration with symlink components or unsafe permissions
are refused. Anonymous-file support is required. These restrictions protect capture
contents but may require choosing a different output directory on unsupported mounts.
A compromised compositor, kernel, privileged process or modified installed plugin can
still bypass these application-level protections. An uninterruptible process may outlive
a deadline until the kernel returns control.
