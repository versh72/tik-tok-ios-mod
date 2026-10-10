#!/usr/bin/env bash
# Does TikTok serve different content depending on the exit IP?
#
# WHY: the earlier conclusion in this project was "the network is fine, so
# only the region parameter matters". That conclusion rested on DNS answers,
# TCP connects, TLS handshakes and HTTP status codes — which prove a host is
# reachable, and nothing about what the application receives.
#
# This runs the SAME request over two exits and diffs the result:
#   DIRECT — physical Ethernet, xray TUN bypassed  (Russian IP)
#   PROXY  — default path                          (foreign IP)
#
# It also checks the two leak channels that are routinely missed and that
# silently pin an app to the real region even when a tunnel is up.
#
# Usage: bash Tools/experiment-region.sh

set -uo pipefail

IFACE="192.168.0.86"      # physical Ethernet; bypasses the xray TUN
UA='Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1'

GRN=$'\033[32m'; RED=$'\033[31m'; DIM=$'\033[2m'; RST=$'\033[0m'
section() { printf "\n%s== %s ==%s\n" "$DIM" "$1" "$RST"; }
ok()   { printf "  %sok%s   %s\n" "$GRN" "$RST" "$1"; }
bad()  { printf "  %sFAIL%s %s\n" "$RED" "$RST" "$1"; }
info() { printf "       %s\n" "$1"; }

# fetch <label> <url> [extra curl args...]
fetch() {
  local label="$1" url="$2"; shift 2
  local out="/tmp/$(echo "$label" | tr ' /' '__').out"
  local code
  code=$(curl -sS -m 20 -o "$out" -w '%{http_code}' "$@" "$url" 2>/dev/null)
  printf '%s' "$code"
}

show_body() {
  local f="/tmp/$(echo "$1" | tr ' /' '__').out"
  [ -s "$f" ] || { info "(empty body)"; return; }
  # Normalise volatile fields so a diff is not drowned by noise.
  tr -d '\r' < "$f" \
    | sed -E 's/"(region|country_code|countryCode|locale|timezone)"[[:space:]]*:[[:space:]]*"[^"]*"/"\1":"X"/g' \
    | head -c 600
  echo
}

########################################################################
section "1. Exit IP actually in use"
########################################################################

for mode in DIRECT PROXY; do
  args=()
  [ "$mode" = "DIRECT" ] && args=(--interface "$IFACE")
  out="/tmp/ip_$mode.txt"
  curl -sS -m 20 "${args[@]}" "https://www.cloudflare.com/cdn-cgi/trace" -o "$out" 2>/dev/null
  ip=$(grep '^ip=' "$out" 2>/dev/null | cut -d= -f2)
  loc=$(grep '^loc=' "$out" 2>/dev/null | cut -d= -f2)
  colo=$(grep '^colo=' "$out" 2>/dev/null | cut -d= -f2)
  if [ -n "$ip" ]; then
    printf "  %-7s ip=%-16s loc=%-3s colo=%s\n" "$mode" "$ip" "$loc" "$colo"
  else
    printf "  %-7s (trace unavailable)\n" "$mode"
  fi
done

########################################################################
section "2. IPv6 leak — is there an IPv6 route at all?"
########################################################################

# If the tunnel carries only IPv4 while the ISP hands out IPv6, the app can
# still see the real address over v6. This is the single most-missed step.
v6=$(curl -sS -m 12 "https://api6.ipify.org" 2>/dev/null)
if [ -n "$v6" ]; then
  bad "IPv6 EGRESS EXISTS: $v6"
  info "An IPv4-only tunnel does not hide it. Check this on the phone."
else
  ok "no IPv6 egress from this host"
fi

########################################################################
section "3. DNS resolver in use"
########################################################################

ns=$(nslookup www.tiktokv.com 2>/dev/null | grep -i '^Address:' | tail -1 | awk '{print $2}')
info "resolver observed: ${ns:-unknown}"

########################################################################
section "4. Same request, two exits — does the ANSWER differ?"
########################################################################

# These are the endpoints that can answer without an account. A feed request
# needs a signature, so it cannot be replayed from here; that limitation is
# recorded in the report rather than papered over.

probe_pair() {
  local label="$1" url="$2"
  local d p
  d=$(fetch "${label}_DIRECT" "$url" --interface "$IFACE")
  p=$(fetch "${label}_PROXY" "$url")
  printf "  %-34s direct=%-4s proxy=%-4s" "$label" "$d" "$p"
  if [ "$d" = "$p" ]; then printf " same\n"; else printf " DIFFERENT\n"; fi
  if [ "$d" != "000" ] || [ "$p" != "000" ]; then
    printf "       direct body: "; show_body "${label}_DIRECT"
    printf "       proxy  body: "; show_body "${label}_PROXY"
  fi
}

probe_pair "passport/web/region"  "https://www.tiktok.com/passport/web/region/"
probe_pair "api/i18n/region"     "https://www.tiktok.com/api/i18n/region/"
probe_pair "passport/region/list" "https://www.tiktok.com/passport/region/list/"

########################################################################
section "5. Response headers that reveal server-side region"
########################################################################

for mode in DIRECT PROXY; do
  args=()
  [ "$mode" = "DIRECT" ] && args=(--interface "$IFACE")
  printf "  --- %s ---\n" "$mode"
  curl -sS -m 20 "${args[@]}" -D - -o /dev/null "https://www.tiktok.com/" 2>/dev/null \
    | grep -iE '^(location|x-|cf-|set-cookie:.*region|server)' \
    | grep -viE 'nonce|ray id' | head -12 | sed 's/^/       /'
done

########################################################################
section "6. A signed feed request is NOT reachable from here"
########################################################################

info "The feed endpoint (/aweme/v1/feed/) requires X-Gorgon/X-Argus."
info "Those depend on device and app state and cannot be forged off-device."
info "So the decisive feed comparison MUST be run on the phone."
info "Use Tools/web/netdiag.html on the device, or read the TikTok feed"
info "under each exit and compare."

printf "\n"