param(
  [Parameter(Mandatory = $true)]
  [ValidatePattern('^[a-z0-9][a-z0-9-]*/[a-z0-9][a-z0-9-]*$')]
  [string]$ItchTarget,

  [string]$Version = "1.2.0",
  [string]$ReleaseDirectory = "",
  [switch]$Publish,
  [switch]$Hidden
)

$ErrorActionPreference = "Stop"

if (-not (Get-Command butler -ErrorAction SilentlyContinue)) {
  throw "itch.io butler was not found on PATH. Install and authenticate it before publishing."
}

if ([string]::IsNullOrWhiteSpace($ReleaseDirectory)) {
  $ReleaseDirectory = Join-Path $PSScriptRoot "..\dist\itch-companion\v$Version"
}
$ReleaseDirectory = [System.IO.Path]::GetFullPath($ReleaseDirectory)
if (-not (Test-Path -LiteralPath $ReleaseDirectory -PathType Container)) {
  throw "Release directory was not found: $ReleaseDirectory"
}

$channels = @(
  @{ Directory = "windows-x64"; Channel = "windows-x64"; Platform = "windows"; ValidationArch = "amd64" },
  @{ Directory = "windows-arm64"; Channel = "windows-arm64"; Platform = "windows"; ValidationArch = $null },
  @{ Directory = "macos-intel"; Channel = "macos-intel"; Platform = "osx"; ValidationArch = "amd64" },
  @{ Directory = "macos-apple-silicon"; Channel = "macos-apple-silicon"; Platform = "osx"; ValidationArch = $null },
  @{ Directory = "linux-x64"; Channel = "linux-x64"; Platform = "linux"; ValidationArch = "amd64" },
  @{ Directory = "linux-arm64"; Channel = "linux-arm64"; Platform = "linux"; ValidationArch = $null }
)

foreach ($item in $channels) {
  $channelDirectory = Join-Path $ReleaseDirectory $item.Directory
  if (-not (Test-Path -LiteralPath $channelDirectory -PathType Container)) {
    throw "Missing itch channel directory: $channelDirectory"
  }

  Write-Host "Validating $($item.Channel)..."
  $validationArguments = @("validate", "--platform", $item.Platform)
  if ($item.ValidationArch) {
    $validationArguments += @("--arch", $item.ValidationArch)
  } else {
    Write-Host "Butler does not expose ARM64 as a validation architecture; validating the package and manifest by platform."
  }
  $validationArguments += $channelDirectory
  & butler @validationArguments
  if ($LASTEXITCODE -ne 0) {
    throw "butler validation failed for $($item.Channel)."
  }

  $destination = "${ItchTarget}:$($item.Channel)"
  if (-not $Publish) {
    Write-Host "Previewing $destination..."
    & butler push-preview --changes-only $channelDirectory $destination
    if ($LASTEXITCODE -ne 0) {
      throw "butler preview failed for $($item.Channel)."
    }
    continue
  }

  $arguments = @("push", $channelDirectory, $destination, "--userversion", $Version)
  if ($Hidden) { $arguments += "--hidden" }
  Write-Host "Publishing $destination..."
  & butler @arguments
  if ($LASTEXITCODE -ne 0) {
    throw "butler publish failed for $($item.Channel)."
  }
}

if ($Publish) {
  Write-Host "All Companion channels published successfully."
} else {
  Write-Host "All Companion channels validated and previewed. No upload was performed."
  Write-Host "Run again with -Publish (and optionally -Hidden) when ready."
}
