# kerbal.ru — установщик русификатора для Windows (PowerShell)
# Скачивает переводы и копирует их в GameData уже собранной сборки RO/RSS/RP-1,
# затем включает русский язык. Существующие моды не трогает.
#
# Запуск (правый клик по файлу → «Выполнить с помощью PowerShell»),
# либо в PowerShell:  .\install-ru.ps1
# либо с явным путём:  .\install-ru.ps1 "D:\Steam\steamapps\common\Kerbal Space Program"

param([string]$KspPath)

$ErrorActionPreference = "Stop"
$zip = "https://github.com/plagness/kerbal.ru/archive/refs/heads/main.zip"

function Say($m){ Write-Host "» $m" -ForegroundColor Cyan }
function Die($m){ Write-Host "× $m" -ForegroundColor Red; exit 1 }

# 1. Найти установку KSP
if (-not $KspPath) {
  $cands = @(
    "${env:ProgramFiles(x86)}\Steam\steamapps\common\Kerbal Space Program",
    "$env:ProgramFiles\Steam\steamapps\common\Kerbal Space Program",
    "C:\Program Files (x86)\Steam\steamapps\common\Kerbal Space Program"
  )
  foreach ($c in $cands) { if (Test-Path (Join-Path $c "GameData")) { $KspPath = $c; break } }
}
if (-not $KspPath -or -not (Test-Path (Join-Path $KspPath "GameData"))) {
  Die "Не нашёл установку KSP. Укажи путь: .\install-ru.ps1 `"C:\путь\к\Kerbal Space Program`""
}
Say "Установка KSP: $KspPath"

# 2. Скачать и распаковать
$tmp = Join-Path $env:TEMP ("kerbalru_" + [guid]::NewGuid())
New-Item -ItemType Directory -Path $tmp | Out-Null
try {
  Say "Скачиваю переводы…"
  Invoke-WebRequest -Uri $zip -OutFile "$tmp\ru.zip"
  Say "Распаковываю…"
  Expand-Archive -Path "$tmp\ru.zip" -DestinationPath $tmp -Force
  $src = Get-ChildItem -Path $tmp -Recurse -Directory -Filter GameData | Select-Object -First 1
  if (-not $src) { Die "В архиве не найдена папка GameData" }

  # 3. Скопировать локализацию
  Say "Копирую файлы локализации в GameData…"
  Copy-Item -Path (Join-Path $src.FullName "*") -Destination (Join-Path $KspPath "GameData") -Recurse -Force

  # 4. Включить русский язык
  $cfg = Join-Path $KspPath "settings.cfg"
  if (Test-Path $cfg) {
    Copy-Item $cfg "$cfg.bak-kerbalru" -Force
    $txt = Get-Content $cfg -Raw
    if ($txt -match "(?m)^LANGUAGE = .*$") {
      $txt = $txt -replace "(?m)^LANGUAGE = .*$", "LANGUAGE = ru"
    } else {
      $txt += "`r`nLANGUAGE = ru`r`n"
    }
    Set-Content -Path $cfg -Value $txt -NoNewline
    Say "Язык переключён на русский (бэкап settings.cfg рядом)."
  } else {
    Say "settings.cfg пока нет (создастся после первого запуска)."
    Say "После первого запуска выбери язык в настройках игры → Русский."
  }
  Write-Host "✓ Готово! Русификатор установлен. Запускай игру." -ForegroundColor Green
}
finally { Remove-Item -Path $tmp -Recurse -Force -ErrorAction SilentlyContinue }
