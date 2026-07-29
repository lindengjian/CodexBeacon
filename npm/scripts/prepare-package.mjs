import { cpSync, existsSync, readFileSync, rmSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const packageDirectory = dirname(dirname(fileURLToPath(import.meta.url)));
const repositoryRoot = dirname(packageDirectory);
const bundledApp = join(repositoryRoot, ".build", "CodexBeacon.app");
const packageAppDirectory = join(packageDirectory, "app");
const packageJSON = JSON.parse(readFileSync(join(packageDirectory, "package.json"), "utf8"));

const build = spawnSync(join(repositoryRoot, "scripts", "build-app.sh"), [], {
  cwd: repositoryRoot,
  stdio: "inherit",
});
if (build.status !== 0) {
  process.exit(build.status ?? 1);
}

if (!existsSync(bundledApp)) {
  throw new Error(`Expected build output is missing: ${bundledApp}`);
}

const version = spawnSync(
  "/usr/libexec/PlistBuddy",
  ["-c", "Print :CFBundleShortVersionString", join(repositoryRoot, "Resources", "Info.plist")],
  { encoding: "utf8" }
);
if (version.status !== 0) {
  throw new Error("Unable to read Codex Beacon's bundle version.");
}
if (version.stdout.trim() !== packageJSON.version) {
  throw new Error(
    `npm package version ${packageJSON.version} must match app version ${version.stdout.trim()}.`
  );
}

rmSync(packageAppDirectory, { recursive: true, force: true });
cpSync(bundledApp, join(packageAppDirectory, "CodexBeacon.app"), {
  recursive: true,
  preserveTimestamps: true,
});
console.log(`Staged ${bundledApp} for npm packaging.`);
