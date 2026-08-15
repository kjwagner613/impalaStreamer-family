import crypto from "node:crypto";
import { execFileSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import process from "node:process";
import readline from "node:readline/promises";

const outputDirectory = path.resolve(process.cwd(), "owner-setup");
const rl = readline.createInterface({ input: process.stdin, output: process.stdout });

function normalizeUrl(value) {
  return String(value || "").trim().replace(/\/+$/, "");
}

function normalizeUsername(value) {
  return String(value || "").trim().toLowerCase();
}

function storageSegment(value) {
  return String(value || "impala")
    .trim()
    .replace(/[^a-z0-9._:-]/gi, "-")
    .replace(/^-+|-+$/g, "") || "impala";
}

function hashPassword(password) {
  const salt = crypto.randomBytes(16);
  const hash = crypto.scryptSync(password, salt, 64, { N: 16384, r: 8, p: 1 });
  return `scrypt$16384$8$1$${salt.toString("base64")}$${hash.toString("base64")}`;
}

async function hiddenQuestion(prompt) {
  if (process.platform === "win32") {
    process.stdout.write(prompt);
    const script = [
      "$secure = Read-Host -AsSecureString",
      "$pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)",
      "try { [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer) }",
      "finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer) }",
    ].join("\n");
    const value = execFileSync(
      "powershell.exe",
      ["-NoLogo", "-NoProfile", "-Command", script],
      { encoding: "utf8", stdio: ["inherit", "pipe", "inherit"] },
    ).replace(/\r?\n$/, "");
    process.stdout.write("\n");
    return value;
  }

  if (!process.stdin.isTTY || typeof process.stdin.setRawMode !== "function") {
    throw new Error("A terminal is required for secure password entry.");
  }

  process.stdout.write(prompt);
  process.stdin.setRawMode(true);
  process.stdin.resume();
  process.stdin.setEncoding("utf8");

  return await new Promise((resolve, reject) => {
    let value = "";
    const onData = (character) => {
      if (character === "\u0003") {
        cleanup();
        reject(new Error("Setup cancelled."));
        return;
      }
      if (character === "\r" || character === "\n") {
        cleanup();
        process.stdout.write("\n");
        resolve(value);
        return;
      }
      if (character === "\u007f" || character === "\b") {
        value = value.slice(0, -1);
        return;
      }
      if (character >= " ") value += character;
    };
    const cleanup = () => {
      process.stdin.off("data", onData);
      process.stdin.setRawMode(false);
      process.stdin.pause();
    };
    process.stdin.on("data", onData);
  });
}

function publicConfig({ signerUrl, liveUrl, storagePrefix }) {
  const date = new Date().toISOString().slice(0, 10).replaceAll("-", ".");
  const settingsBlock = `window.KW_PLAYER_CONFIG = window.KW_PLAYER_CONFIG || {
  apiBaseUrl: ${JSON.stringify(signerUrl)},
  liveStreamApiBaseUrl: ${JSON.stringify(liveUrl)},
  localLiveStreamApiBaseUrl: ${JSON.stringify(liveUrl)},
  syncPlayApiBaseUrl: "",
  coastApiBaseUrl: "",
  authStorageKey: ${JSON.stringify(`${storagePrefix}.authSession`)},
  playlistStoragePrefix: ${JSON.stringify(storagePrefix)},
  instanceStorageId: "",
  builtInPlaylistsEnabled: true,
  enabledBuiltInPlaylistIds: ["songs"],
  brandName: "Impala Streamer",
  appVersion: "1.2.0",
  appBuildDate: ${JSON.stringify(date)},
  mkvPlaybackEnabled: true,
  localHelperDownloadUrl: "https://www.discrete-dev.com/downloads.html#impalaHelper",
};
`;
  const sourceConfigPath = path.resolve(process.cwd(), "app-config.js");
  const sourceConfig = fs.readFileSync(sourceConfigPath, "utf8");
  const configPattern = /window\.KW_PLAYER_CONFIG\s*=\s*window\.KW_PLAYER_CONFIG\s*\|\|\s*\{[\s\S]*?\r?\n\};/;
  if (!configPattern.test(sourceConfig)) {
    throw new Error("The owner settings block was not found in app-config.js.");
  }
  return sourceConfig.replace(configPattern, settingsBlock.trimEnd());
}

try {
  console.log("\nImpala owner setup");
  console.log("Public website settings and private signer settings are generated separately.\n");

  const username = normalizeUsername(await rl.question("Owner user ID: "));
  if (!/^[a-z0-9._-]{2,64}$/.test(username)) {
    throw new Error("User ID must be 2-64 letters, numbers, dots, underscores, or hyphens.");
  }
  const displayName = (await rl.question("Display name: ")).trim() || username;
  const siteOrigin = normalizeUrl(await rl.question("GitHub Pages/site URL (https://...): "));
  if (siteOrigin && !siteOrigin.startsWith("https://")) {
    throw new Error("The public site URL must begin with https://");
  }
  const signerUrl = normalizeUrl(await rl.question("Optional signer URL (Enter for local-only): "));
  const liveUrl = normalizeUrl(await rl.question("Optional live-stream URL (Enter to skip): "));
  const password = await hiddenQuestion("Owner password (hidden): ");
  const confirmation = await hiddenQuestion("Confirm password (hidden): ");
  if (password.length < 12) throw new Error("Use a password of at least 12 characters.");
  if (password !== confirmation) throw new Error("Passwords did not match.");

  const storagePrefix = storageSegment(`impala-${username}`);
  const allowedUsers = [{
    username,
    displayName,
    passwordHash: hashPassword(password),
    allowedPrefixes: [],
    isAdmin: true,
  }];
  const privateValues = {
    ALLOWED_USERS_JSON: JSON.stringify(allowedUsers),
    CORS_ORIGINS: siteOrigin || "http://127.0.0.1:5500",
    SESSION_SECRET: crypto.randomBytes(48).toString("base64url"),
  };

  fs.mkdirSync(outputDirectory, { recursive: true });
  fs.writeFileSync(
    path.join(outputDirectory, "app-config.js"),
    publicConfig({ signerUrl, liveUrl, storagePrefix }),
    { mode: 0o644 },
  );
  fs.writeFileSync(
    path.join(outputDirectory, "PRIVATE-SIGNER-VALUES.json"),
    `${JSON.stringify(privateValues, null, 2)}\n`,
    { mode: 0o600 },
  );
  fs.writeFileSync(
    path.join(outputDirectory, "NEXT-STEPS.txt"),
    [
      "1. Review app-config.js, then copy it to the root of your Impala repository.",
      "2. Keep PRIVATE-SIGNER-VALUES.json private. Never commit or upload it to GitHub.",
      "3. If using cloud access, enter its three values as signer environment variables.",
      "4. Delete the owner-setup directory after configuring the signer.",
      "",
    ].join("\n"),
  );

  console.log(`\nSetup files created in: ${outputDirectory}`);
  console.log("The plaintext password was not stored.");
  console.log("PRIVATE-SIGNER-VALUES.json is secret and is excluded from Git.\n");
} catch (error) {
  console.error(`\nSetup failed: ${error.message}`);
  process.exitCode = 1;
} finally {
  rl.close();
}
