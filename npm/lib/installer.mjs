import {
  cpSync,
  existsSync,
  mkdirSync,
  renameSync,
  rmSync,
  statSync,
} from "node:fs";
import { homedir } from "node:os";
import { basename, dirname, join } from "node:path";
import { execFileSync } from "node:child_process";

export const applicationName = "CodexBeacon.app";
export const executableRelativePath = join("Contents", "MacOS", "CodexBeacon");

export function validatePlatform({ platform = process.platform, arch = process.arch } = {}) {
  if (platform !== "darwin" || arch !== "arm64") {
    throw new Error("Codex Beacon only supports macOS on Apple Silicon (darwin/arm64).");
  }
}

export function defaultApplicationsDirectory(homeDirectory = homedir()) {
  return join(homeDirectory, "Applications");
}

export function defaultInstalledApp(applicationsDirectory = defaultApplicationsDirectory()) {
  return join(applicationsDirectory, applicationName);
}

export function verifyApp(appPath) {
  execFileSync("/usr/bin/codesign", ["--verify", "--strict", "--verbose=2", appPath], {
    stdio: "inherit",
  });
}

export function openApp(appPath) {
  execFileSync("/usr/bin/open", [appPath], { stdio: "inherit" });
}

function assertAppBundle(appPath, description) {
  if (!existsSync(appPath) || !statSync(appPath).isDirectory()) {
    throw new Error(`${description} is missing: ${appPath}`);
  }
}

function replaceDirectory(source, destination) {
  const parentDirectory = dirname(destination);
  const stagingDirectory = join(parentDirectory, `.${basename(destination)}.install-${process.pid}`);
  const backupDirectory = join(parentDirectory, `.${basename(destination)}.backup-${process.pid}`);

  rmSync(stagingDirectory, { recursive: true, force: true });
  rmSync(backupDirectory, { recursive: true, force: true });
  cpSync(source, stagingDirectory, { recursive: true, preserveTimestamps: true });

  const hadExistingInstallation = existsSync(destination);
  if (hadExistingInstallation) {
    renameSync(destination, backupDirectory);
  }

  try {
    renameSync(stagingDirectory, destination);
  } catch (error) {
    if (hadExistingInstallation && !existsSync(destination)) {
      renameSync(backupDirectory, destination);
    }
    throw error;
  } finally {
    rmSync(stagingDirectory, { recursive: true, force: true });
  }

  rmSync(backupDirectory, { recursive: true, force: true });
}

export function installApp({
  bundledApp,
  applicationsDirectory = defaultApplicationsDirectory(),
  platform = process.platform,
  arch = process.arch,
  verifyApp: verify = verifyApp,
}) {
  validatePlatform({ platform, arch });
  assertAppBundle(bundledApp, "The bundled Codex Beacon app");
  verify(bundledApp);
  mkdirSync(applicationsDirectory, { recursive: true });

  const installedApp = defaultInstalledApp(applicationsDirectory);
  replaceDirectory(bundledApp, installedApp);
  return installedApp;
}

export function uninstallApp({
  installedApp = defaultInstalledApp(),
  prepareForUninstall = (executable, commandArguments) =>
    execFileSync(executable, commandArguments, { stdio: "inherit" }),
}) {
  if (!existsSync(installedApp)) {
    return false;
  }

  const executable = join(installedApp, executableRelativePath);
  if (!existsSync(executable)) {
    throw new Error(`The installed Codex Beacon app is incomplete: ${installedApp}`);
  }

  prepareForUninstall(executable, ["--prepare-for-uninstall"]);
  rmSync(installedApp, { recursive: true, force: false });
  return true;
}

export function doctor({
  installedApp = defaultInstalledApp(),
  platform = process.platform,
  arch = process.arch,
  verifyApp: verify = verifyApp,
}) {
  validatePlatform({ platform, arch });
  assertAppBundle(installedApp, "Codex Beacon is not installed; run `codex-beacon install`");
  verify(installedApp);
  return installedApp;
}
