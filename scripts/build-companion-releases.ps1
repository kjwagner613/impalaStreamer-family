param(
  [string]$OutputDirectory = "dist/itch-companion",
  [string]$Version = "1.2.0"
)

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot
$sourceDirectory = Join-Path $projectRoot "services/local-library-helper"
$releaseRoot = Join-Path $projectRoot $OutputDirectory
$releaseDirectory = Join-Path $releaseRoot "v$Version"
$goCacheDirectory = Join-Path $releaseRoot ".go-build-cache"

if (Test-Path $releaseDirectory) {
  throw "Release directory already exists: $releaseDirectory. Use a new version or move the existing release first."
}

New-Item -ItemType Directory -Path $releaseDirectory -Force | Out-Null
New-Item -ItemType Directory -Path $goCacheDirectory -Force | Out-Null

$commit = "unknown"
try {
  $resolvedCommit = git -C $projectRoot rev-parse --short HEAD 2>$null
  if (-not [string]::IsNullOrWhiteSpace($resolvedCommit)) {
    $commit = $resolvedCommit.Trim()
  }
}
catch {
  Write-Warning "Git commit metadata is unavailable; packages will use commit=unknown."
}

$targets = @(
  @{ Os = "windows"; Platform = "windows"; Arch = "amd64"; Label = "x64"; Channel = "windows-x64" },
  @{ Os = "windows"; Platform = "windows"; Arch = "arm64"; Label = "arm64"; Channel = "windows-arm64" },
  @{ Os = "darwin"; Platform = "osx"; Arch = "amd64"; Label = "intel"; Channel = "macos-intel" },
  @{ Os = "darwin"; Platform = "osx"; Arch = "arm64"; Label = "apple-silicon"; Channel = "macos-apple-silicon" },
  @{ Os = "linux"; Platform = "linux"; Arch = "amd64"; Label = "x64"; Channel = "linux-x64" },
  @{ Os = "linux"; Platform = "linux"; Arch = "arm64"; Label = "arm64"; Channel = "linux-arm64" }
)

$artifacts = @()
$previousGoCache = $env:GOCACHE
$env:GOCACHE = $goCacheDirectory

Push-Location $sourceDirectory
try {
  go test ./...
  if ($LASTEXITCODE -ne 0) {
    throw "Companion tests failed with exit code $LASTEXITCODE."
  }

  foreach ($target in $targets) {
    $channelDirectory = Join-Path $releaseDirectory $target.Channel
    New-Item -ItemType Directory -Path $channelDirectory -Force | Out-Null

    $env:CGO_ENABLED = "0"
    $env:GOOS = $target.Os
    $env:GOARCH = $target.Arch
    $ldflags = "-s -w -X main.buildVersion=$Version -X main.buildCommit=$commit"

    if ($target.Os -eq "windows") {
      $binaryPath = Join-Path $channelDirectory "Impala-Companion.exe"
      $launchPath = "Impala-Companion.exe"
    }
    elseif ($target.Os -eq "darwin") {
      $appRoot = Join-Path $channelDirectory "Impala Companion.app"
      $macOsDirectory = Join-Path $appRoot "Contents/MacOS"
      New-Item -ItemType Directory -Path $macOsDirectory -Force | Out-Null
      $binaryPath = Join-Path $macOsDirectory "Impala-Companion"
      $launchPath = "Impala Companion.app"

      $infoPlist = @"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleDisplayName</key><string>Impala Companion</string>
  <key>CFBundleExecutable</key><string>Impala-Companion</string>
  <key>CFBundleIdentifier</key><string>com.discrete-dev.impala.companion</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>Impala Companion</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$Version</string>
  <key>CFBundleVersion</key><string>$Version</string>
  <key>LSMinimumSystemVersion</key><string>11.0</string>
</dict>
</plist>
"@
      Set-Content -LiteralPath (Join-Path $appRoot "Contents/Info.plist") -Value $infoPlist -Encoding UTF8
    }
    else {
      $binaryPath = Join-Path $channelDirectory "Impala-Companion"
      $launchPath = "Impala-Companion"
    }

    Write-Host "Building $($target.Channel)"
    go build -trimpath -ldflags $ldflags -o $binaryPath .
    if ($LASTEXITCODE -ne 0) {
      throw "Companion build failed for $($target.Channel) with exit code $LASTEXITCODE."
    }

    $consoleLine = if ($target.Os -eq "windows") { "`nconsole = true" } else { "" }
    $manifest = @"
[[actions]]
name = "play"
path = "$launchPath"
platform = "$($target.Platform)"$consoleLine
"@
    Set-Content -LiteralPath (Join-Path $channelDirectory ".itch.toml") -Value $manifest -Encoding UTF8

    $installText = @"
Impala Local Library Companion $Version
========================================

Platform: $($target.Platform) / $($target.Label)
Build commit: $commit

The Companion listens only on 127.0.0.1 and does not upload local media.
It trusts Impala Family at https://impala-fam.discrete-dev.com and local previews.

Install and launch this build through the itch.io app. The app uses .itch.toml
to start the correct executable. Keep the Companion running while Impala uses a
local library. Impala connects to http://127.0.0.1:8089.

Then open Impala > Settings > Local Library Companion, check the connection,
choose a dedicated media folder, and select Connect / Rescan.

FFmpeg and ffprobe are optional for ordinary browser-compatible files. They are
required for MKV preparation, incompatible audio conversion, and permanent
Voice Sync corrected copies. Install them through the operating system's
trusted package manager and ensure both commands are on PATH before launching
the Companion.

Pilot builds are not yet code-signed or notarized. Operating-system security
prompts may appear outside the itch.io app.
"@
    Set-Content -LiteralPath (Join-Path $channelDirectory "INSTALL.txt") -Value $installText -Encoding UTF8

    $binaryHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $binaryPath).Hash.ToLowerInvariant()
    $artifacts += [pscustomobject]@{
      channel = $target.Channel
      directory = $target.Channel
      platform = $target.Platform
      architecture = $target.Label
      goos = $target.Os
      goarch = $target.Arch
      executable = $binaryPath.Substring($releaseDirectory.Length + 1).Replace("\", "/")
      sha256 = $binaryHash
    }
  }
}
finally {
  Pop-Location
  Remove-Item Env:GOOS -ErrorAction SilentlyContinue
  Remove-Item Env:GOARCH -ErrorAction SilentlyContinue
  Remove-Item Env:CGO_ENABLED -ErrorAction SilentlyContinue
  if ([string]::IsNullOrWhiteSpace($previousGoCache)) {
    Remove-Item Env:GOCACHE -ErrorAction SilentlyContinue
  }
  else {
    $env:GOCACHE = $previousGoCache
  }
}

$checksumLines = $artifacts | ForEach-Object { "$($_.sha256)  $($_.executable)" }
Set-Content -LiteralPath (Join-Path $releaseDirectory "SHA256SUMS.txt") -Value $checksumLines -Encoding ASCII

$releaseManifest = [ordered]@{
  product = "Impala Local Library Companion"
  version = $Version
  commit = $commit
  builtAtUtc = [DateTime]::UtcNow.ToString("o")
  distribution = "itch.io"
  artifacts = $artifacts
}
$releaseManifest | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $releaseDirectory "release-manifest.json") -Encoding UTF8

Write-Host "Companion channel directories written to $releaseDirectory"
$artifacts | Format-Table channel, platform, architecture, sha256
