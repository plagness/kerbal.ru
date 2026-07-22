# kerbal.ru — установщик и обновлятор для Windows PowerShell 5.1+.
[CmdletBinding()]
param(
  [Parameter(Position=0)][string]$KspPath,
  [switch]$Check,
  [switch]$Force,
  [ValidateSet("stable", "main")][string]$Channel = "stable",
  [string]$Version
)

$ErrorActionPreference = "Stop"
$repo = "plagness/kerbal.ru"

function Say([string]$Message) { Write-Host "» $Message" -ForegroundColor Cyan }
function Done([string]$Message) { Write-Host "✓ $Message" -ForegroundColor Green }
function Die([string]$Message) { Write-Host "× $Message" -ForegroundColor Red; exit 1 }
function Write-Utf8NoBom([string]$Path, [string]$Text) {
  $encoding = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($Path, $Text, $encoding)
}

if ($Version -and $Channel -eq "main") { Die "-Version и -Channel main нельзя использовать вместе" }

# Найти KSP.
if (-not $KspPath) {
  $candidates = @(
    "${env:ProgramFiles(x86)}\Steam\steamapps\common\Kerbal Space Program",
    "$env:ProgramFiles\Steam\steamapps\common\Kerbal Space Program",
    "C:\Program Files (x86)\Steam\steamapps\common\Kerbal Space Program"
  )
  foreach ($candidate in $candidates) {
    if (Test-Path (Join-Path $candidate "GameData")) { $KspPath = $candidate; break }
  }
}
if (-not $KspPath -or -not (Test-Path (Join-Path $KspPath "GameData"))) {
  Die 'Не нашёл KSP. Укажи путь: .\install-ru.ps1 "D:\Steam\steamapps\common\Kerbal Space Program"'
}
Say "Установка KSP: $KspPath"

$versionFile = Join-Path $KspPath ".kerbalru-version"
$currentVersion = if (Test-Path $versionFile) { (Get-Content $versionFile -First 1).Trim() } else { "не установлена" }

# Выбрать источник и версию.
if ($Version) {
  $remoteVersion = $Version.TrimStart("v")
  if ($remoteVersion -notmatch '^\d{2}\.[1-9]\d*$') { Die "Версия должна выглядеть как v26.1" }
  $archiveUrl = "https://github.com/$repo/archive/refs/tags/v$remoteVersion.zip"
} elseif ($Channel -eq "main") {
  $commit = Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/commits/main"
  $remoteVersion = "main-" + $commit.sha.Substring(0, 7)
  $archiveUrl = "https://github.com/$repo/archive/refs/heads/main.zip"
} else {
  try { $release = Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/releases/latest" }
  catch { $release = $null }
  if ($release -and $release.tag_name) {
    $tag = [string]$release.tag_name
    $remoteVersion = $tag.TrimStart("v")
    $archiveUrl = "https://github.com/$repo/archive/refs/tags/$tag.zip"
  } else {
    Say "Стабильных релизов пока нет — использую текущую main."
    $commit = Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/commits/main"
    $remoteVersion = "main-" + $commit.sha.Substring(0, 7)
    $archiveUrl = "https://github.com/$repo/archive/refs/heads/main.zip"
  }
}

Say "Установлено: $currentVersion"
Say "Доступно: $remoteVersion ($Channel)"
if ($Check) {
  if ($currentVersion -eq $remoteVersion) { Done "Установлена актуальная версия." }
  else { Say "Доступно обновление. Запусти установщик без -Check." }
  exit 0
}
if ($currentVersion -eq $remoteVersion -and -not $Force) {
  Done "Уже установлена актуальная версия. Для переустановки добавь -Force."
  exit 0
}

$workDir = Join-Path $env:TEMP ("kerbalru_" + [guid]::NewGuid())
New-Item -ItemType Directory -Path $workDir | Out-Null
try {
  $zipPath = Join-Path $workDir "kerbalru.zip"
  $archiveDir = Join-Path $workDir "archive"
  Say "Скачиваю ${remoteVersion}…"
  Invoke-WebRequest -Uri $archiveUrl -OutFile $zipPath
  Say "Распаковываю…"
  Expand-Archive -Path $zipPath -DestinationPath $archiveDir -Force
  $sourceData = Get-ChildItem -Path $archiveDir -Recurse -Directory -Filter GameData | Select-Object -First 1
  if (-not $sourceData) { Die "В архиве не найдена папка GameData" }

  $newManifest = @(
    Get-ChildItem -Path $sourceData.FullName -Recurse -File | ForEach-Object {
      $relative = $_.FullName.Substring($sourceData.FullName.Length).TrimStart('\', '/').Replace('\', '/')
      "GameData/$relative"
    } | Sort-Object
  )
  if ($newManifest.Count -eq 0) { Die "Архив не содержит файлов локализации" }

  $manifestPath = Join-Path $KspPath ".kerbalru-files"
  $oldManifest = if (Test-Path $manifestPath) { @(Get-Content $manifestPath | Where-Object { $_ }) } else { @() }
  $allManaged = @($oldManifest + $newManifest | Sort-Object -Unique)

  $safeVersion = $currentVersion.Replace('/', '-')
  $backupDir = Join-Path $KspPath ("kerbal.ru-backups\{0}-{1}" -f $safeVersion, (Get-Date -Format "yyyyMMdd-HHmmss"))
  $backupCreated = $false
  foreach ($relative in $allManaged) {
    if (-not $relative.StartsWith("GameData/") -or $relative.Contains("..")) { continue }
    $target = Join-Path $KspPath $relative.Replace('/', [IO.Path]::DirectorySeparatorChar)
    if (Test-Path $target -PathType Leaf) {
      $backupTarget = Join-Path $backupDir $relative.Replace('/', [IO.Path]::DirectorySeparatorChar)
      New-Item -ItemType Directory -Path (Split-Path $backupTarget) -Force | Out-Null
      Copy-Item $target $backupTarget -Force
      $backupCreated = $true
    }
  }

  foreach ($relative in $oldManifest) {
    if (-not $relative.StartsWith("GameData/") -or $relative.Contains("..")) { continue }
    if ($newManifest -notcontains $relative) {
      $stalePath = Join-Path $KspPath $relative.Replace('/', [IO.Path]::DirectorySeparatorChar)
      Remove-Item $stalePath -Force -ErrorAction SilentlyContinue
    }
  }

  Say "Копирую файлы локализации…"
  Copy-Item -Path (Join-Path $sourceData.FullName "*") -Destination (Join-Path $KspPath "GameData") -Recurse -Force
  Write-Utf8NoBom $manifestPath (($newManifest -join "`n") + "`n")
  Write-Utf8NoBom $versionFile ($remoteVersion + "`n")

  $settings = Join-Path $KspPath "settings.cfg"
  if (Test-Path $settings) {
    $settingsBackup = "$settings.bak-kerbalru"
    if (-not (Test-Path $settingsBackup)) { Copy-Item $settings $settingsBackup }
    $text = [IO.File]::ReadAllText($settings)
    if ($text -match "(?m)^LANGUAGE = .*$") { $text = $text -replace "(?m)^LANGUAGE = .*$", "LANGUAGE = ru" }
    else { $text += "`r`nLANGUAGE = ru`r`n" }
    Write-Utf8NoBom $settings $text
  } else {
    Say "settings.cfg появится после первого запуска; затем выбери Русский в настройках."
  }

  if ($backupCreated) { Say "Резервная копия: $backupDir" }
  Done "kerbal.ru $remoteVersion установлен. Запускай игру."
}
finally {
  Remove-Item -Path $workDir -Recurse -Force -ErrorAction SilentlyContinue
}
