# Impala Local-First Distribution

Impala is distributed in two deliberately separate pieces:

1. **Impala Streamer** is the static personal interface hosted from the owner's
   free GitHub Pages site.
2. **Impala Local Library Companion** is the native localhost application
   downloaded from itch.io. It reads only the folders the owner selects and
   never uploads local media.

Cloud library access is optional. A new owner can begin with GitHub Pages and
the Companion without creating a MEGA account, signer, or paid subscription.

## Owner setup wizard

Install Node.js 18 or newer, open a terminal in the Impala project, and run:

```powershell
node .\scripts\setup-owner.mjs
```

The wizard asks for the owner user ID, display name, public site URL, optional
service URLs, and password. Password entry is hidden. It writes:

- `owner-setup/app-config.js` — public browser configuration
- `owner-setup/PRIVATE-SIGNER-VALUES.json` — private, hashed authentication
  and session values
- `owner-setup/NEXT-STEPS.txt` — concise completion steps

The plaintext password is never stored. The whole `owner-setup` directory is
ignored by Git. Copy only `app-config.js` into the repository. Never commit the
private signer file.

## Free GitHub Pages hosting

1. Create a free GitHub account at `github.com`.
2. Create a private working copy or a new repository for the owner's Impala.
3. Run the owner setup wizard and copy its public `app-config.js` into the
   repository root.
4. Commit and push the files.
5. In the GitHub repository, open **Settings → Pages**.
6. Under **Build and deployment**, deploy from the `main` branch and `/ (root)`.
7. Open the HTTPS Pages address GitHub reports.

GitHub Pages is public static hosting. Do not place passwords, MEGA keys,
session secrets, signer configuration, or private media in the repository.

## Local library

Download the matching Companion build from the Impala itch.io page:

- Windows x64 or ARM64
- macOS Intel or Apple Silicon
- Linux x64 or ARM64

Launch the Companion, open Impala **Settings → Local Library Companion**, and
select dedicated media folders such as `C:\Media\Audio` and
`C:\Media\Videos`. The Companion listens only on `127.0.0.1`.

## Optional MEGA cloud library

Cloud access is an additional owner-controlled layer, not a requirement for
local playback.

1. Create a MEGA account and enable its S4-compatible storage.
2. Create separate audio and video buckets if both are wanted.
3. Deploy the included `services/heroku-signer` service to the owner's chosen
   Node-compatible host.
4. Put the MEGA S4 access key, secret, endpoint, region, and bucket names only
   in that host's private environment variables.
5. Add `ALLOWED_USERS_JSON`, `SESSION_SECRET`, and `CORS_ORIGINS` from
   `PRIVATE-SIGNER-VALUES.json`.
6. Set `S4_BUCKET_RULES_JSON` so each user can access only their assigned
   buckets.
7. Put only the public signer URL into `app-config.js`.

The frontend must never contain MEGA credentials.

## Build Companion channels for itch.io

```powershell
.\scripts\build-companion-releases.ps1 -Version 1.2.0
```

Output is written to `dist/itch-companion/v1.2.0`. Each platform/architecture
folder is an independent itch.io channel and contains its own `.itch.toml`.
Butler currently exposes only `386` and `amd64` through its validation
architecture flag, so ARM64 channels are validated by target platform while
the release manifest and SHA-256 checks identify their ARM64 binaries.

Create the itch.io project page once, install and authenticate `butler`, then
validate and preview all channels without uploading:

```powershell
.\scripts\publish-companion-itch.ps1 -ItchTarget "account/impala-companion" -Version 1.2.0
```

Publish hidden builds for owner testing:

```powershell
.\scripts\publish-companion-itch.ps1 -ItchTarget "account/impala-companion" -Version 1.2.0 -Publish -Hidden
```

After installation tests pass in the itch app, make the downloads visible from
the itch.io project dashboard. Future updates use the same channel names so the
itch app can apply incremental updates.
