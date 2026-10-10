# Вставка TikTokRegion.dylib в TikTok.ipa
#
# Запуск:
#   .\insert-dylib.ps1 -Ipa "TikTok.ipa" -Dylib "TikTokRegion.dylib"
#
# Что делает:
#   1. Проверяет, что IPA действительно расшифрован
#   2. Вставляет dylib через insert_dylib
#   3. Говорит, что делать дальше (Sideloadly / AltStore)
#
# Нужен расшифрованный IPA. Из App Store файл приходит зашифрованным:
# байты кода там зашифрованы, и после вставки библиотеки приложение
# не запустится. Проверка на шаге 1 это ловит заранее.

param(
    [Parameter(Mandatory = $true)][string]$Ipa,
    [string]$Dylib = "$PSScriptRoot\..\artifacts\TikTokRegion.dylib",
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

function Say($msg, $color = 'Gray') { Write-Host $msg -ForegroundColor $color }

# --- проверки -------------------------------------------------------------

if (-not (Test-Path -LiteralPath $Ipa)) {
    Say "IPA not found: $Ipa" 'Red'
    exit 1
}
if (-not (Test-Path -LiteralPath $Dylib)) {
    Say "dylib not found: $Dylib" 'Red'
    Say "Take it from the Artifacts section of the last CI run." 'Yellow'
    exit 1
}

$insert = Get-Command insert_dylib -ErrorAction SilentlyContinue
if (-not $insert) {
    Say "insert_dylib is not installed." 'Red'
    Say ""
    Say "Install it (macOS/Linux):" 'Yellow'
    Say "  git clone https://github.com/Tyilo/insert_dylib"
    Say "  cd insert_dylib && cargo build --release"
    Say ""
    Say "On Windows there is no cargo build for it. Use WSL2, or run the" 'Yellow'
    Say "whole step on a machine with macOS or Linux." 'Yellow'
    exit 1
}

# --- проверка на шифрование ----------------------------------------------

Say "Checking whether the IPA is decrypted..." 'Cyan'

$tmp = Join-Path $env:TEMP ("ttcheck_" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp -Force | Out-Null
try {
    Copy-Item -LiteralPath $Ipa -Destination $tmp -Force
    $inner = Get-ChildItem $tmp -Filter *.ipa | Select-Object -First 1

    # cryptid != 0 means the Mach-O code is still encrypted.
    $cryptid = $null
    $bin = Get-ChildItem $tmp -Recurse -File -ErrorAction SilentlyContinue |
           Where-Object { $_.Name -eq 'TikTok' -and $_.Length -gt 1MB } |
           Select-Object -First 1

    if ($bin) {
        $bytes = [System.IO.File]::ReadAllBytes($bin.FullName)
        # LC_ENCRYPTION_INFO (0x21) — ищем номер команды
        for ($i = 0; $i -lt $bytes.Length - 12; $i++) {
            if ($bytes[$i] -eq 0x21 -and $bytes[$i+1] -eq 0x00 -and
                $bytes[$i+2] -eq 0x00 -and $bytes[$i+3] -eq 0x00) {
                $cryptid = [BitConverter]::ToUInt32($bytes, $i + 8)
                break
            }
        }
    }

    if ($null -eq $cryptid) {
        Say "  LC_ENCRYPTION_INFO not found - the binary looks decrypted." 'Green'
    }
    elseif ($cryptid -ne 0) {
        Say "  cryptid = $cryptid -> the IPA is ENCRYPTED." 'Red'
        Say ""
        Say "insert_dylib will produce a file that will not launch." 'Yellow'
        Say "You need a decrypted copy first." 'Yellow'
        exit 2
    }
    else {
        Say "  cryptid = 0 -> decrypted." 'Green'
    }
}
finally {
    Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}

# --- вставка --------------------------------------------------------------

Say ""
Say "Inserting the dylib..." 'Cyan'

& $insert.Source -i $Ipa -d $Dylib -m insert_dylib --target-version 16.0 --inplace
if ($LASTEXITCODE -ne 0) {
    Say "insert_dylib failed with exit code $LASTEXITCODE" 'Red'
    exit 1
}

Say ""
Say "Done. The dylib is now inside the IPA." 'Green'
Say ""
Say "Next: re-sign and install." 'Cyan'
Say "  1. Sideloadly (sideloadly.io) - free, runs on Windows"
Say "  2. Drag the IPA in, choose your Apple ID, press Start"
Say "  3. On the iPhone: Settings -> Privacy & Security ->"
Say "     Developer Mode -> on -> restart"
Say ""
Say "The free profile lasts 7 days. After that, sign again." 'Yellow'
