# Build the first release as a native macOS app

The first release will use SwiftUI and AppKit, with task-state aggregation and quota parsing separated from platform window behavior. A shared cross-platform UI is deferred because the product depends on precise macOS behavior—matching the Codex pet's always-on-top level, joining all Spaces, overlaying full-screen apps, and snapping cleanly to screen edges—while Windows and Linux support is still only a possible future requirement.
