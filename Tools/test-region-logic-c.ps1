# Компилирует и запускает настоящий C-тест логики RegionLogic.h.
#
# ЗАЧЕМ: прежний test-region-logic.mjs был зеркалом логики на JS. Зеркало
# может расходиться с исходником — и расходилось. Здесь исполняется сам
# RegionLogic.h.
#
# ТРЕБОВАНИЯ: любой C99-компилятор.
#   zig cc  — рекомендуется (ziglang.org, ~78 MB, содержит clang)
#   clang / gcc — тоже подходят
#
# Установка zig (Windows, один раз)
#   winget install -e --id zig.zig
#
# Использование:
#   powershell -ExecutionPolicy Bypass -File Tools\test-region-logic-c.ps1
#   ZIG="C:\path\to\zig.exe" powershell -File Tools\test-region-logic-c.ps1

$ErrorActionPreference = 'Stop'

$ROOT = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
$SRC  = Join-Path $ROOT 'Tools\test-region-logic.c'
$OUT  = Join-Path $env:TEMP 'rl_test.exe'

# Ищем компилятор: явный ZIG, потом в PATH, потом в стандартном месте.
function Find-Zig {
    if ($env:ZIG -and (Test-Path $env:ZIG)) { return $env:ZIG }
    $c = Get-Command zig -ErrorAction SilentlyContinue
    if ($c) { return $c.Source }
    foreach ($d in @("$env:LOCALAPPDATA\Programs\zig", 'C:\Program Files\zig')) {
        if (Test-Path $d) {
            $e = Get-ChildItem -Path $d -Filter 'zig.exe' -Recurse -ErrorAction SilentlyContinue |
                 Select-Object -First 1
            if ($e) { return $e.FullName }
        }
    }
    return $null
}

$zig = Find-Zig
if (-not $zig) {
    Write-Host ""
    Write-Host "  C99-компилятор не найден." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  Поставь zig (один раз, ~78 MB):"
    Write-Host "    winget install -e --id zig.zig"
    Write-Host ""
    Write-Host "  Это единственное, что нужно для компиляции RegionLogic.h."
    Write-Host "  Сам ObjC-модуль на Windows собрать нельзя — причина"
    Write-Host "  зафиксирована в VERIFICATION.md (ARC + Foundation headers)."
    Write-Host ""
    exit 2
}

Write-Host ""
Write-Host "  компилятор: $zig"
Write-Host "  $( & $zig version 2>&1 | Select-Object -First 1 )"

$ccOut = & $zig cc -std=c99 -Wall -Wextra -O2 $SRC -o $OUT 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "  КОМПИЛЯЦИЯ НЕ УДАЛАСЬ:" -ForegroundColor Red
    $ccOut | ForEach-Object { Write-Host "    $_" }
    exit 1
}
Write-Host "  скомпилировано чисто: -Wall -Wextra, 0 ошибок, 0 предупреждений"
Write-Host ""

& $OUT
exit $LASTEXITCODE