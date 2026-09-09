# Contributing

Read the [architecture](ARCHITECTURE.md) and [security review](SECURITY.md) before
changing capture behavior. Review changes using the linked Omarchy plugin security
skill, including its source/sink, process, file, disclosure and repository checks.

Keep capture state in `CaptureService.qml`, fixed desktop operations in
`capture_backend.py`, and process/file ownership in `capture_runtime.py`. UI components
must not add shell commands, PID handling, dynamic image URLs or public capture IPC.
New helper events need a bounded schema in `CaptureModel.js` and regression coverage.

Run the Python and JavaScript suites, the manifest validator, and the QML integration
runner listed in the README. Capture tests normally use fakes; live screen or audio
recording should be an explicitly requested test with a narrow scope.

Before publishing, run the marketplace's `runSecurityBaseline` against the final
40-character commit SHA and verify that README, manifest, preview and behavior match.
Keep the manifest description and opening README paragraph identical. Never claim
marketplace verification based only on a local scanner run.

Do not distribute auto-loaded agent instructions or a copy of SKILL.md in the plugin
installation. This contributor document links the review guidance without making it
an automatically executed instruction surface. Keep test output, caches and bytecode
out of the repository.
