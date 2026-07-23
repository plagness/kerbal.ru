# kerbal.ru — установщик "всё в одном" для Windows PowerShell 5.1+.
# Два пути: полностью автоматическая установка сборки RP-1-ExpressInstall через CKAN
# + русификатор, либо только русификатор поверх уже поставленных модов.
#
# Мы не храним и не распространяем чужие моды или сам CKAN — только скачиваем
# официальные релизы KSP-CKAN/CKAN и вызываем их headless-режимом.
[CmdletBinding()]
param(
  [Parameter(Position=0)][string]$KspPath,
  [switch]$Full,
  [switch]$RuOnly,
  [switch]$Check,
  [switch]$Force,
  [ValidateSet("stable", "main")][string]$Channel = "stable",
  [string]$Version
)

$ErrorActionPreference = "Stop"
$ckanRepo = "KSP-CKAN/CKAN"
# RP-1-ExpressInstall в headless-режиме НЕ доустанавливает сам RP-1 (OR-зависимость
# "RP-1 OR RONoCareer" не резолвится без интерактивного выбора) — без явного RP-1
# карьеры не будет. Ставим все три пакета проверенной командой (см. docs/FOR-AGENTS.md).
$ckanPackages = @("RP-1-ExpressInstall", "RP-1-ExpressInstall-Graphics-Low", "RP-1")
$ckanLabel = "RP-1-ExpressInstall"
$ruInstallerUrl = "https://kerbal.ru/install-ru.ps1"

function Say([string]$Message) { Write-Host "» $Message" -ForegroundColor Cyan }
function Done([string]$Message) { Write-Host "✓ $Message" -ForegroundColor Green }
function Die([string]$Message) { Write-Host "× $Message" -ForegroundColor Red; exit 1 }

if ($Full -and $RuOnly) { Die "-Full и -RuOnly нельзя использовать вместе" }
$mode = if ($Full) { "full" } elseif ($RuOnly) { "ru-only" } else { "" }

# Найти KSP (та же логика, что в install-ru.ps1).
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
  Die 'Не нашёл KSP. Сначала поставь лицензионную Kerbal Space Program через Steam, потом укажи путь: .\install.ps1 "D:\Steam\steamapps\common\Kerbal Space Program" -Full'
}
Say "Установка KSP: $KspPath"

$modsPresent = (Test-Path (Join-Path $KspPath "GameData\RealismOverhaul")) -and (Test-Path (Join-Path $KspPath "GameData\RP-1"))

# Решить путь, если не задан явно флагом -Full/-RuOnly.
if (-not $mode) {
  if ($modsPresent) {
    $mode = "ru-only"
  } elseif ([Environment]::UserInteractive -and -not ([Console]::IsInputRedirected)) {
    Say "Сборка RO/RSS/RP-1 не найдена в $KspPath\GameData."
    Say "[1] Поставить всё автоматически через CKAN (RP-1-ExpressInstall) + русификатор — Enter"
    Say "[2] Моды поставлю сам(а) — поставить только русификатор"
    $choice = Read-Host "» Выбор [1/2]"
    $mode = if ($choice -eq "2") { "ru-only" } else { "full" }
  } else {
    Say "Сборка RO/RSS/RP-1 не найдена, а терминала для вопроса нет (неинтерактивный запуск)."
    Say "Укажи явно один из двух путей:"
    Say '  & ([scriptblock]::Create((irm https://kerbal.ru/install.ps1))) -Full     # поставить всё автоматически'
    Say '  & ([scriptblock]::Create((irm https://kerbal.ru/install.ps1))) -RuOnly   # только русификатор (моды уже свои)'
    exit 0
  }
}

if ($mode -eq "full") {
  if ($modsPresent) {
    if ($Check) { Say "Сборка RO/RSS/RP-1 уже установлена — шаг CKAN будет пропущен." }
    else { Done "Сборка RO/RSS/RP-1 уже установлена — пропускаю шаг CKAN." }
  } elseif ($Check) {
    Say "Сборка RO/RSS/RP-1 не установлена — при обычном запуске будет поставлена через CKAN ($ckanLabel)."
  } else {
    $workDir = Join-Path $env:TEMP ("kerbalru-ckan_" + [guid]::NewGuid())
    New-Item -ItemType Directory -Path $workDir | Out-Null
    try {
      Say "Ищу свежий релиз CKAN…"
      $release = Invoke-RestMethod -Uri "https://api.github.com/repos/$ckanRepo/releases/latest"
      $asset = $release.assets | Where-Object { $_.name -eq "ckan.exe" } | Select-Object -First 1
      if (-not $asset) { Die "Не удалось найти ckan.exe в последнем релизе $ckanRepo" }
      $ckanExe = Join-Path $workDir "ckan.exe"
      Say "Скачиваю CKAN…"
      Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $ckanExe

      Say "Обновляю индекс модов CKAN…"
      & $ckanExe update --headless --gamedir $KspPath
      if ($LASTEXITCODE -ne 0) { Die "CKAN update завершился с ошибкой (код $LASTEXITCODE)." }

      Say "Ставлю сборку $ckanLabel через CKAN (это надолго — несколько гигабайт)…"
      & $ckanExe install --headless --no-recommends --gamedir $KspPath @ckanPackages
      if ($LASTEXITCODE -ne 0) { Die "CKAN install завершился с ошибкой (код $LASTEXITCODE)." }
      Done "Сборка RO/RSS/RP-1 установлена через CKAN."
    }
    finally {
      Remove-Item -Path $workDir -Recurse -Force -ErrorAction SilentlyContinue
    }
  }
}

Say "Ставлю русификатор…"
$ruArgs = @{ KspPath = $KspPath }
if ($Check) { $ruArgs.Check = $true }
if ($Force) { $ruArgs.Force = $true }
if ($Version) { $ruArgs.Version = $Version }
if ($Channel -ne "stable") { $ruArgs.Channel = $Channel }
$ruScript = Invoke-RestMethod -Uri $ruInstallerUrl
& ([scriptblock]::Create($ruScript)) @ruArgs
