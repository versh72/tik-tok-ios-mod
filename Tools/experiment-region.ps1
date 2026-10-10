# Аудит: разделяем уровни проверки и ставим эксперимент.
#
# ВОПРОС, который здесь проверяется:
#   Меняет ли TikTok то, что он отдаёт, в зависимости от исходящего IP?
#
# ПОЧЕМУ ЭТО ВАЖНО:
#   Прежний вывод проекта был «сеть в порядке, значит важна только подмена
#   параметра региона». Он опирался на DNS, TCP, TLS и HTTP-коды — то есть
#   доказывал только достижимость хоста. Это уровень 1 из шести.
#
#   Этот скрипт делает следующий шаг: ОДИН И ТОТ ЖЕ запрос через два разных
#   выхода, прямую разницу ответа, плюс проверку утечек IPv6 и DNS.
#
# ОГРАНИЧЕНИЕ, КОТОРОЕ НЕЛЬЗЯ ЗАМАЛЧИВАТЬ:
#   Лента (/aweme/v1/feed/) требует подписей X-Gorgon/X-Argus, которые зависят
#   от состояния устройства и приложения. Подделать их вне устройства нельзя.
#   Значит решающее сравнение ленты возможно ТОЛЬКО НА ТЕЛЕФОНЕ. Здесь —
#   только то, что доступно без подписи.

$IFACE = '192.168.0.86'
$UA    = 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1'

$GRN = "`e[32m"; $RED = "`e[31m"; $DIM = "`e[2m"; $RST = "`e[0m"
function Section($t) { Write-Host "`n$DIM== $t ==$RST" }
function Ok($t)   { Write-Host "  ${GRN}ok${RST}   $t" }
function Bad($t)  { Write-Host "  ${RED}FAIL${RST} $t" }
function Note($t) { Write-Host "       $t" }

$tmp = $env:TEMP

################################################################
Section '1. Какой исходящий IP используется на самом деле'
################################################################

$egress = @{}
foreach ($mode in @('DIRECT','PROXY')) {
  $extra = @()
  if ($mode -eq 'DIRECT') { $extra = @('--interface', $IFACE) }
  $out = Join-Path $tmp "egress_$mode.txt"
  & curl.exe -sS -m 20 @extra 'https://www.cloudflare.com/cdn-cgi/trace' -o $out 2>$null
  $ip   = (Select-String -Path $out -Pattern '^ip='   -ErrorAction SilentlyContinue | Select-Object -First 1)
  $loc  = (Select-String -Path $out -Pattern '^loc='  -ErrorAction SilentlyContinue | Select-Object -First 1)
  $colo = (Select-String -Path $out -Pattern '^colo=' -ErrorAction SilentlyContinue | Select-Object -First 1)
  if ($ip) {
    $egress[$mode] = ($ip.Line -split '=')[1]
    Write-Host ("  {0,-7} ip={1,-16} {2,-10} {3}" -f $mode, $egress[$mode], $loc.Line, $colo.Line)
  } else {
    Write-Host "  $mode (trace unavailable)"
  }
}

if ($egress.Count -eq 2) {
  if ($egress['DIRECT'] -ne $egress['PROXY']) { Ok "два разных исходящих IP — сравнение имеет смысл" }
  else { Bad "IP одинаковые — прокси не влияет, сравнение бессмысленно" }
}

################################################################
Section '2. Утечка IPv6 — самый часто пропускаемый шаг'
################################################################

# Если туннель несёт только IPv4, а провайдер выдаёт IPv6, приложение
# всё равно видит настоящий адрес. На телефоне это ломает анонимность
# маршрута так же надёжно, как его отсутствие.
$v6 = & curl.exe -sS -m 12 'https://api6.ipify.org' 2>$null
if ($v6 -and "$v6".Trim()) {
  Bad "IPv6-egress существует: $v6"
  Note "Туннель только на IPv4 НЕ скрывает этот адрес. Проверьте на телефоне."
} else {
  Ok "IPv6-egress с этой машины отсутствует"
}

################################################################
Section '3. Какой DNS-резолвер используется'
################################################################

$ns = (nslookup www.tiktokv.com 2>$null | Select-String -Pattern '^Address:' | Select-Object -Last 1)
Note ("резолвер: " + $(if ($ns) { ($ns.Line -split ':')[-1].Trim() } else { 'не определён' }))
Note "если резолвер географически не совпадает с IP — для TikTok это флаг риска"

################################################################
Section '4. Один и тот же запрос, два выхода — различается ли ответ?'
################################################################

function Probe-Pair($label, $url) {
  $dFile = Join-Path $tmp ("p_direct_" + ($label -replace '\W','_') + ".txt")
  $pFile = Join-Path $tmp ("p_proxy_"  + ($label -replace '\W','_') + ".txt")

  $dCode = (& curl.exe -sS -m 20 --interface $IFACE -o $dFile -w '%{http_code}' -A $UA $url 2>$null)
  $pCode = (& curl.exe -sS -m 20                    -o $pFile -w '%{http_code}' -A $UA $url 2>$null)

  $dCode = "$dCode".Trim(); $pCode = "$pCode".Trim()
  $verdict = if ($dCode -eq $pCode) { 'одинаково' } else { 'РАЗЛИЧАЕТСЯ' }
  Write-Host ("  {0,-30} direct={1,-5} proxy={2,-5} {3}" -f $label, $dCode, $pCode, $verdict)

  foreach ($pair in @(@('direct',$dFile), @('proxy ',$pFile))) {
    if (Test-Path $pair[1]) {
      $body = (Get-Content $pair[1] -Raw -ErrorAction SilentlyContinue)
      if ($body) {
        $shown = ($body -replace '\s+',' ').Trim()
        if ($shown.Length -gt 300) { $shown = $shown.Substring(0,300) + '…' }
        Write-Host ("       {0} : {1}" -f $pair[0], $shown)
      } else {
        Write-Host ("       {0} : (пусто)" -f $pair[0])
      }
    }
  }
}

Probe-Pair 'passport/web/region' 'https://www.tiktok.com/passport/web/region/'
Probe-Pair 'api/i18n/region'    'https://www.tiktok.com/api/i18n/region/'

################################################################
Section '5. Заголовки ответа, выдающие регион на стороне сервера'
################################################################

foreach ($mode in @('DIRECT','PROXY')) {
  $extra = @()
  if ($mode -eq 'DIRECT') { $extra = @('--interface', $IFACE) }
  Write-Host "  --- $mode ---"
  $h = & curl.exe -sS -m 20 @extra -D - -o NUL -A $UA 'https://www.tiktok.com/' 2>$null
  $keep = $h | Select-String -Pattern '^(location|x-|cf-|server|set-cookie)' -CaseSensitive:$false |
          Where-Object { $_.Line -notmatch '(?i)nonce|ray id' } | Select-Object -First 10
  if ($keep) { $keep | ForEach-Object { Write-Host ("       " + $_.Line.Trim()) } }
  else { Write-Host '       (нет значимых заголовков)' }
}

################################################################
Section '6. Чего этот скрипт НЕ может проверить'
################################################################

Note 'Лента /aweme/v1/feed/ требует X-Gorgon и X-Argus.'
Note 'Подписи зависят от устройства и состояния приложения,'
Note 'подделать их вне устройства невозможно.'
Note ''
Note 'Значит решающее сравнение ленты возможно ТОЛЬКО НА ТЕЛЕФОНЕ:'
Note '  1. включить туннель  → открыть ленту  → запомнить видео'
Note '  2. выключить туннель → открыть ленту  → сравнить'
Note '  3. проверить утечки на ipleak.net при включённом туннеле'
Write-Host ''