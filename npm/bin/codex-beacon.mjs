#!/usr/bin/env node

import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

import {
  defaultInstalledApp,
  doctor,
  installApp,
  openApp,
  uninstallApp,
} from "../lib/installer.mjs";

const packageDirectory = dirname(dirname(fileURLToPath(import.meta.url)));
const bundledApp = join(packageDirectory, "app", "CodexBeacon.app");

function printUsage() {
  console.log(`Codex Beacon npm installer

Usage:
  codex-beacon install [--no-launch]  Install to ~/Applications and open it
  codex-beacon open                   Open the installed app
  codex-beacon doctor                 Check platform, installation, and signature
  codex-beacon uninstall              Clean up Beacon-owned services and remove the app
`);
}

function run() {
  const [command = "help", ...arguments_] = process.argv.slice(2);

  switch (command) {
    case "install": {
      const installedApp = installApp({ bundledApp });
      console.log(`Installed Codex Beacon at ${installedApp}`);
      if (!arguments_.includes("--no-launch")) {
        openApp(installedApp);
      }
      return;
    }
    case "open": {
      const installedApp = defaultInstalledApp();
      doctor({ installedApp });
      openApp(installedApp);
      return;
    }
    case "doctor": {
      const installedApp = doctor();
      console.log(`Codex Beacon is installed and its signature is valid: ${installedApp}`);
      console.log("Open Beacon and use its integration diagnostic to verify Codex Desktop compatibility.");
      return;
    }
    case "uninstall": {
      if (uninstallApp({})) {
        console.log("Removed Codex Beacon from ~/Applications.");
      } else {
        console.log("Codex Beacon is not installed in ~/Applications.");
      }
      return;
    }
    case "help":
    case "--help":
    case "-h":
      printUsage();
      return;
    default:
      throw new Error(`Unknown command: ${command}`);
  }
}

try {
  run();
} catch (error) {
  console.error(`codex-beacon: ${error.message}`);
  process.exitCode = 1;
}
