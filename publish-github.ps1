# Отправка проекта на GitHub ради сборки dylib
# Запуск:  .\publish-github.ps1

$ErrorActionPreference = 'Stop'
$repo = 'https://github.com/ВАШ_НИК/tiktok-region.git'

Write-Host ''
Write-Host '=== Отправка проекта на GitHub ===' -ForegroundColor Cyan
Write-Host ''
Write-Host 'Нужен ПУБЛИЧНЫЙ репозиторий: macOS-минуты в приватных'
Write-Host 'списываются с множителем 10x. Публичные — бесплатно.'
Write-Host ''

$url = Read-Host 'URL репозитория (или Enter для примера)'
if ([string]::IsNullOrWhiteSpace($url)) { $url = $repo }

if ($url -match 'ВАШ_НИК') {
    Write-Host ''
    Write-Host 'Пока не создан репозиторий. Порядок:' -ForegroundColor Yellow
    Write-Host '  1. Открой https://github.com/new'
    Write-Host '  2. Имя: tiktok-region'
    Write-Host '  3. Visibility: PUBLIC   <- обязательно публичный'
    Write-Host '  4. НЕ ставь галочки (README, .gitignore, лицензия)'
    Write-Host '  5. Create repository'
    Write-Host ''
    Write-Host 'Потом запусти этот скрипт снова.' -ForegroundColor Yellow
    exit 1
}

if ($url -notmatch '\.git$') { $url = "$url.git" }

git remote remove origin 2>$null | Out-Null
git remote add origin $url
Write-Host "remote -> $url" -ForegroundColor Green

git add -A
git commit -q -m "CI для сборки dylib" 2>$null | Out-Null

Write-Host ''
Write-Host 'Отправляю...' -ForegroundColor Cyan
git push -u origin main

Write-Host ''
Write-Host '=== Готово ===' -ForegroundColor Green
Write-Host ''
Write-Host 'Теперь:'
Write-Host '  1. Открой репозиторий на github.com'
Write-Host '  2. Вкладка Actions'
Write-Host '  3. Слева выбери "Сборка TikTokRegion.dylib (arm64)"'
Write-Host '  4. Справа сверху: Run workflow -> зелёная кнопка'
Write-Host ''
Write-Host 'Сборка ~10 минут. Внизу страницы будет раздел'
Write-Host 'Artifacts -> файл TikTokRegion-dylib-arm64.'
