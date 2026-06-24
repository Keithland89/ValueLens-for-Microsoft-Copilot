<#
.SYNOPSIS
  Thin wrapper around the latest PAX AIBV rollup release.

.DESCRIPTION
  Downloads the selected Microsoft PAX release script, runs the built-in AIBV
  rollup pipeline, and leaves the two rollup CSVs the SharePoint PBIT consumes
  in .\processed\. No separate local Python processor is used here.

.PARAMETER TenantId
  Target Entra tenant GUID.

.PARAMETER ClientId
  App registration client ID in the target tenant.

.PARAMETER ClientSecret
  App registration secret. If omitted, the script tries the environment and
  Windows Credential Manager.

.PARAMETER Days
  Lookback window in days. Used to derive the PAX start/end date range.

.PARAMETER WorkRoot
  Working directory. Holds the downloaded PAX release cache and processed CSVs.

.PARAMETER PaxReleaseTag
  GitHub release tag to use. Default: latest.

.PARAMETER IncludeAgent365Info
  Passes the PAX -IncludeAgent365Info switch so the optional Agent 365 output
  is produced.

.PARAMETER ForcePaxDownload
  Re-download the selected PAX release script even if it is already cached.

.EXAMPLE
  .\Run-PAX-AIBV.ps1 -TenantId <guid> -ClientId <guid>

.EXAMPLE
  .\Run-PAX-AIBV.ps1 -TenantId <guid> -ClientId <guid> -Days 30 -IncludeAgent365Info
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)] [string]$TenantId,
  [Parameter(Mandatory = $true)] [string]$ClientId,
  [string]$ClientSecret,
  [int]$Days = 7,
  [string]$WorkRoot = (Get-Location).Path,
  [string]$PaxReleaseTag = 'latest',
  [switch]$IncludeAgent365Info,
  [switch]$ForcePaxDownload
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

if ($PSVersionTable.PSVersion.Major -lt 7) {
  throw "PowerShell 7+ required. Run with 'pwsh', not 'powershell'."
}

function Resolve-Secret {
  param([string]$Provided, [string]$TenantId)
  if ($Provided) { return $Provided }
  if ($env:AIBV_CLIENT_SECRET) { return $env:AIBV_CLIENT_SECRET }
  $credTarget = "PAX-AIBV-$TenantId"
  try {
    Add-Type @"
using System; using System.Runtime.InteropServices;
public class _AIBVCred {
  [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)] public struct CR {
    public uint Flags; public uint Type; public IntPtr TargetName; public IntPtr Comment;
    public System.Runtime.InteropServices.ComTypes.FILETIME LastWritten;
    public uint CredentialBlobSize; public IntPtr CredentialBlob;
    public uint Persist; public uint AttributeCount; public IntPtr Attributes;
    public IntPtr TargetAlias; public IntPtr UserName; }
  [DllImport("Advapi32.dll", EntryPoint="CredReadW", CharSet=CharSet.Unicode, SetLastError=true)]
  public static extern bool CredRead(string target, uint type, uint flag, out IntPtr ptr);
  [DllImport("Advapi32.dll", EntryPoint="CredFree")] public static extern void CredFree(IntPtr cred);
  public static string Get(string target) {
    IntPtr p; if (!CredRead(target, 1u, 0u, out p)) return null;
    try { var c = (CR)Marshal.PtrToStructure(p, typeof(CR));
      return Marshal.PtrToStringUni(c.CredentialBlob, (int)(c.CredentialBlobSize/2)); }
    finally { CredFree(p); } } }
"@ -ErrorAction SilentlyContinue | Out-Null
    $fromCm = [_AIBVCred]::Get($credTarget)
    if ($fromCm) { return $fromCm }
  } catch { }
  $secure = Read-Host -Prompt "Client secret for app $ClientId" -AsSecureString
  return [System.Net.NetworkCredential]::new('', $secure).Password
}

function Get-GitHubRelease {
  param([string]$ReleaseTag)

  $headers = @{
    'User-Agent' = 'Microsoft-Scout'
    'Accept'     = 'application/vnd.github+json'
  }

  $uri = if ($ReleaseTag -eq 'latest') {
    'https://api.github.com/repos/microsoft/PAX/releases/latest'
  } else {
    "https://api.github.com/repos/microsoft/PAX/releases/tags/$ReleaseTag"
  }

  try {
    Invoke-RestMethod -Method Get -Uri $uri -Headers $headers -ErrorAction Stop
  } catch {
    throw "Failed to resolve PAX release '$ReleaseTag': $_"
  }
}

function Get-PaxReleaseScript {
  param(
    [string]$ReleaseTag,
    [string]$CacheRoot,
    [switch]$ForceDownload
  )

  $release = Get-GitHubRelease -ReleaseTag $ReleaseTag
  $asset = $release.assets |
    Where-Object { $_.name -match '^PAX_Purview_Audit_Log_Processor_v.*\.ps1$' } |
    Select-Object -First 1

  if (-not $asset) {
    throw "No PAX script asset found in release $($release.tag_name)."
  }

  $releaseRoot = Join-Path $CacheRoot 'releases'
  $tagRoot = Join-Path $releaseRoot $release.tag_name
  $scriptPath = Join-Path $tagRoot $asset.name
  $metaPath = Join-Path $tagRoot 'release.json'

  New-Item -ItemType Directory -Force -Path $tagRoot | Out-Null

  if ($ForceDownload -or -not (Test-Path -LiteralPath $scriptPath)) {
    Write-Host "==> Downloading PAX $($release.tag_name) -> $scriptPath" -ForegroundColor Cyan
    Invoke-WebRequest -Method Get -Uri $asset.browser_download_url -OutFile $scriptPath -Headers @{ 'User-Agent' = 'Microsoft-Scout' }
  } else {
    Write-Host "==> Using cached PAX $($release.tag_name) at $scriptPath" -ForegroundColor Cyan
  }

  $meta = [pscustomobject]@{
    requested_tag = $ReleaseTag
    resolved_tag  = $release.tag_name
    asset_name    = $asset.name
    asset_url     = $asset.browser_download_url
    cached_utc    = (Get-Date).ToUniversalTime().ToString('o')
  }
  $meta | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $metaPath -Encoding utf8

  [pscustomobject]@{
    Path = $scriptPath
    Tag = $release.tag_name
    Asset = $asset.name
  }
}

$WorkRoot = (Resolve-Path -LiteralPath $WorkRoot).Path
$PaxCacheRoot = Join-Path $WorkRoot 'pax'
$OutDir = Join-Path $WorkRoot 'processed'
New-Item -ItemType Directory -Force -Path $PaxCacheRoot, $OutDir | Out-Null

$secret = Resolve-Secret -Provided $ClientSecret -TenantId $TenantId
$StartDate = (Get-Date).AddDays(-$Days).ToString('yyyy-MM-dd')
$EndDate = (Get-Date).ToString('yyyy-MM-dd')

$pax = Get-PaxReleaseScript -ReleaseTag $PaxReleaseTag -CacheRoot $PaxCacheRoot -ForceDownload:$ForcePaxDownload

Write-Host ""
Write-Host "==== PAX run ====" -ForegroundColor Cyan
Write-Host ("Tenant   : {0}" -f $TenantId)
Write-Host ("App      : {0}" -f $ClientId)
Write-Host ("Window   : {0} -> {1} ({2} days)" -f $StartDate, $EndDate, $Days)
Write-Host ("Release  : {0} ({1})" -f $pax.Tag, $pax.Asset)
Write-Host ("Out dir  : {0}" -f $OutDir)
Write-Host ""

$paxStart = Get-Date
$paxArgs = @(
  '-TenantId', $TenantId,
  '-ClientId', $ClientId,
  '-ClientSecret', $secret,
  '-Auth', 'AppRegistration',
  '-Dashboard', 'AIBV',
  '-Rollup',
  '-StartDate', $StartDate,
  '-EndDate', $EndDate,
  '-OutputPath', $OutDir,
  '-OutputPathUserInfo', $OutDir
)

if ($IncludeAgent365Info) {
  $paxArgs += '-IncludeAgent365Info'
}

& $pax.Path @paxArgs
if (-not $?) {
  throw "PAX failed."
}

$paxElapsed = (Get-Date) - $paxStart
Write-Host ("==> PAX finished in {0:N1} min" -f $paxElapsed.TotalMinutes) -ForegroundColor Green

$interactions = Get-ChildItem $OutDir -Filter '*_Interactions_*.csv' |
  Sort-Object LastWriteTime -Descending | Select-Object -First 1
$users = Get-ChildItem $OutDir -Filter '*_Users_*.csv' |
  Sort-Object LastWriteTime -Descending | Select-Object -First 1

if (-not $interactions) { throw "No rollup interactions CSV found in $OutDir." }
if (-not $users) { throw "No rollup users CSV found in $OutDir." }

Write-Host ""
Write-Host "==== Rollup outputs ====" -ForegroundColor Cyan
Write-Host ("  Interactions : {0} ({1:N0} bytes)" -f $interactions.FullName, $interactions.Length)
Write-Host ("  Users        : {0} ({1:N0} bytes)" -f $users.FullName, $users.Length)

$manifest = [pscustomobject]@{
  generated_utc      = (Get-Date).ToUniversalTime().ToString('o')
  tenant_id          = $TenantId
  window_days        = $Days
  window_start       = $StartDate
  window_end         = $EndDate
  pax_release_tag    = $pax.Tag
  pax_release_asset  = $pax.Asset
  pax_elapsed_min    = [math]::Round($paxElapsed.TotalMinutes, 2)
  include_agent365   = [bool]$IncludeAgent365Info
  interactions_csv   = $interactions.FullName
  users_csv          = $users.FullName
}

$manifestPath = Join-Path $OutDir 'rollup-manifest.json'
$manifest | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $manifestPath -Encoding utf8

Write-Host ""
Write-Host ("Manifest written: {0}" -f $manifestPath) -ForegroundColor Green
Write-Host ""
Write-Host "Next: .\Upload-Rollups-SharePoint.ps1 -Manifest `"$manifestPath`" -SiteId <...> -DriveId <...> -FolderPath /AIBV" -ForegroundColor Yellow
