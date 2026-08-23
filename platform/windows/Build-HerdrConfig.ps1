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

$text = (Get-Content $template -Raw).Replace('__BUNDLE__', $rootForToml)

# Not Set-Content -Encoding UTF8: under Windows PowerShell 5.1 that writes a BOM.
$noBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($rendered, $text, $noBom)

return $rendered
