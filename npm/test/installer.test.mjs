import assert from "node:assert/strict";
import { mkdtempSync, mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";

import {
  doctor,
  installApp,
  uninstallApp,
  validatePlatform,
} from "../lib/installer.mjs";

function makeBundledApp(root) {
  const app = join(root, "CodexBeacon.app");
  const executable = join(app, "Contents", "MacOS", "CodexBeacon");
  mkdirSync(join(app, "Contents", "MacOS"), { recursive: true });
  writeFileSync(executable, "beacon executable");
  return { app, executable };
}

test("install copies the bundled app to the user's Applications directory and verifies it", () => {
  const root = mkdtempSync(join(tmpdir(), "codex-beacon-npm-test-"));
  try {
    const { app: bundledApp } = makeBundledApp(join(root, "package"));
    const applicationsDirectory = join(root, "Applications");
    const verified = [];

    const installedApp = installApp({
      bundledApp,
      applicationsDirectory,
      platform: "darwin",
      arch: "arm64",
      verifyApp: (path) => verified.push(path),
    });

    assert.equal(installedApp, join(applicationsDirectory, "CodexBeacon.app"));
    assert.equal(
      readFileSync(join(installedApp, "Contents", "MacOS", "CodexBeacon"), "utf8"),
      "beacon executable"
    );
    assert.deepEqual(verified, [bundledApp]);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test("install preserves an existing app when the new bundle fails verification", () => {
  const root = mkdtempSync(join(tmpdir(), "codex-beacon-npm-test-"));
  try {
    const { app: bundledApp } = makeBundledApp(join(root, "package"));
    const applicationsDirectory = join(root, "Applications");
    const { executable: existingExecutable } = makeBundledApp(applicationsDirectory);
    writeFileSync(existingExecutable, "existing beacon executable");

    assert.throws(
      () => installApp({
        bundledApp,
        applicationsDirectory,
        platform: "darwin",
        arch: "arm64",
        verifyApp: () => {
          throw new Error("signature verification failed");
        },
      }),
      /signature verification failed/
    );

    assert.equal(readFileSync(existingExecutable, "utf8"), "existing beacon executable");
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test("install rejects platforms the bundled app cannot support", () => {
  assert.throws(
    () => validatePlatform({ platform: "linux", arch: "x64" }),
    /only supports macOS on Apple Silicon/
  );
});

test("doctor without options reports a missing default installation instead of crashing", () => {
  assert.throws(
    () => doctor(),
    /Codex Beacon is not installed; run `codex-beacon install`/
  );
});

test("uninstall runs Beacon cleanup before removing only its installed bundle", () => {
  const root = mkdtempSync(join(tmpdir(), "codex-beacon-npm-test-"));
  try {
    const applicationsDirectory = join(root, "Applications");
    const { app: installedApp, executable } = makeBundledApp(applicationsDirectory);
    const cleanupCalls = [];

    uninstallApp({
      installedApp,
      prepareForUninstall: (path, commandArguments) =>
        cleanupCalls.push({ path, commandArguments }),
    });

    assert.deepEqual(cleanupCalls, [{ path: executable, commandArguments: ["--prepare-for-uninstall"] }]);
    assert.throws(() => readFileSync(executable), /ENOENT/);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});
