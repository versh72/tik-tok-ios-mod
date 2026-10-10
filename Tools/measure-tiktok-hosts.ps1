$hosts = @(
  'www.cloudflare.com',
  'api-va.tiktokv.com',
  'api16-normal-c-useast1a.tiktokv.com',
  'sf16-va.tiktokcdn.com',
  'p16-sign-va.tiktokcdn.com',
  'log-va.tiktokv.com',
  'mon-va.tiktokv.com'
)

$IFACE = '192.168.0.86'   # physical Ethernet, bypasses the xray TUN

function Measure-Host_ {
  param([string]$Host_, [string]$Iface)
  # $args is reserved in PowerShell and breaks splatting — use a distinct name.
  $curlArgs = @(
    '-sS', '-o', 'NUL', '-m', '20',
    '--connect-timeout', '10',
    '-w', '%{http_code} %{time_namelookup} %{time_connect} %{time_appconnect} %{time_total}',
    ('https://' + $Host_ + '/')
  )
  if ($Iface) { $curlArgs += @('--interface', $Iface) }

  $raw = & curl.exe @curlArgs 2>&1
  $line = ($raw | Where-Object { $_ -match '^\d+ ' } | Select-Object -First 1)
  if (-not $line) {
    $err = ($raw | Select-Object -First 1) -replace '^curl:\s*\(\d+\)\s*', ''
    return [pscustomobject]@{ Code = 'FAIL'; Dns = '-'; Tcp = '-'; Tls = '-'; Total = '-'; Err = $err }
  }
  $p = $line -split '\s+'
  return [pscustomobject]@{
    Code  = $p[0]
    Dns   = [math]::Round([double]$p[1] * 1000)
    Tcp   = [math]::Round([double]$p[2] * 1000)
    Tls   = [math]::Round([double]$p[3] * 1000)
    Total = [math]::Round([double]$p[4] * 1000)
    Err   = ''
  }
}

$fmt = '{0,-36} {1,-6} {2,7} {3,7} {4,7} {5,8}'
$bar = '-' * 74

function Show-Table([string]$title, [string]$iface) {
  Write-Output ''
  Write-Output "=== $title ==="
  Write-Output ($fmt -f 'host', 'http', 'dns_ms', 'tcp_ms', 'tls_ms', 'total_ms')
  foreach ($h in $hosts) {
    $r = Measure-Host_ $h $iface
    if ($r.Code -eq 'FAIL') {
      Write-Output ($fmt -f $h, 'FAIL', '-', '-', '-', '-')
      Write-Output ("      -> " + $r.Err)
    } else {
      Write-Output ($fmt -f $h, $r.Code, $r.Dns, $r.Tcp, $r.Tls, $r.Total)
    }
  }
}

Show-Table 'DIRECT — physical Ethernet, xray TUN bypassed' $IFACE
Show-Table 'THROUGH PROXY — default path via xray' ''