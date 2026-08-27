<#
.SYNOPSIS
  Renders config\herdr\config.toml into bin\herdr-config.toml and returns the
  rendered path.

.DESCRIPTION
  config\herdr\config.toml is the file you edit and the file that is committed.
  It carries a __BUNDLE__ token wherever an absolute path is unavoidable, which
  keeps it identical on every machine.

  This script substitutes the token with the real bundle root. It runs on every
  launch, so editing the template takes effect the next time you start the
  console. There is no build step to remember.

  The rendered file lands in bin\ and is gitignored.

.OUTPUTS
  The full path of the rendered config.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$BundleRoot
)

$ErrorActionPreference = 'Stop'

$template = Join-Path $BundleRoot 'config\herdr\config.toml'
if (-not (Test-Path $template)) {
    throw "herdr config template not found at $template"
}

$binDir = Join-Path $BundleRoot 'bin'
if (-not (Test-Path $binDir)) { New-Item -ItemType Directory -Force -Path $binDir | Out-Null }

$rendered = Join-Path $binDir 'herdr-config.toml'

# Forward slashes throughout: TOML strings treat a backslash as an escape, and
# every Windows API here accepts forward slashes.
$rootForToml = $BundleRoot.Replace('\', '/').TrimEnd('/')

# Not Get-Content -Raw: under Windows PowerShell 5.1 that reads with the system
# ANSI codepage, not UTF-8. A template byte pair like C2 B7 (the "·" in the
# tab-bar hint) comes back as the two Latin-1 characters "Â·", and the UTF-8
# write below then encodes THOSE, so the file lands as C3 82 C2 B7 and herdr
# renders mojibake. It is the same defect as the BOM one noted below, on the
# read side instead of the write side, and it only shows up once the template
# stops being pure ASCII.
#
# [System.IO.File]::ReadAllText defaults to UTF-8 and strips a BOM if one is
# there, which is the exact inverse of the write.
$text = [System.IO.File]::ReadAllText($template).Replace('__BUNDLE__', $rootForToml)

# Not Set-Content -Encoding UTF8: under Windows PowerShell 5.1 that writes a BOM.
$noBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($rendered, $text, $noBom)

return $rendered
