# Codex Beacon npm installer

This package installs the native Codex Beacon app into `~/Applications` on an
Apple Silicon Mac running macOS 15 or later.

```sh
npx @lindengjian/codex-beacon install
```

Or install the small command-line launcher globally:

```sh
npm install -g @lindengjian/codex-beacon
codex-beacon install
```

Commands:

```sh
codex-beacon open
codex-beacon doctor
codex-beacon uninstall
```

`uninstall` removes only `~/Applications/CodexBeacon.app`. Before removal it
asks Beacon to unregister its login item and roll back the shared App Server
compatibility adapter that Beacon itself created.

The app remains ad-hoc signed and is not notarized. npm does not bypass macOS
security checks; follow the macOS prompt only when you trust the release.
