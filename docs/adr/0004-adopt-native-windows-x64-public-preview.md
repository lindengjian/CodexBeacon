# Adopt a native Windows x64 public preview

After the native macOS-first release, Codex Beacon will add a Windows 11 x64 public preview with core feature parity. The Windows client will be a separate C# / .NET 10 LTS + WPF implementation that follows the shared status, quota, completion-confirmation, privacy, and fail-closed contracts; it will not attempt to port AppKit UI code or require a shared cross-platform UI.

## Considered Options

- Cross-compile or share the existing Swift/AppKit application: rejected because the floating, non-activating window, notification, login-startup, shortcut, and local-runtime integration behaviors are platform-specific.
- Use a cross-platform UI framework: rejected for this preview because it would add an abstraction layer before Windows overlay behavior and Codex Desktop integration have been proven on real devices.
- Native WPF client: accepted because it provides a Windows-native desktop surface while preserving an independently testable behavioral contract.

## Consequences

The Windows preview must fail closed to **监测不可用** when its local Codex Desktop integration is missing, stale, incompatible, or otherwise unverified. It remains a passive observer; any repair operation requires explicit user action. GitHub Releases will distribute an Inno Setup x64 `Setup.exe` as a per-user installation, without automatic update checks or silent network access. Until code signing is introduced, user-facing documentation must explain the expected Windows SmartScreen prompt.
