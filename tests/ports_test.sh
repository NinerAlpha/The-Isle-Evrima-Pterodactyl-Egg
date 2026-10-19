#!/bin/bash
# Unit tests for the port resolver (docker/helpers/ports.sh).
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
source "${HELPERS_DIR}/ports.sh"

# run <SERVER_PORT> <QUERY_PORT> <RCON_PORT> <QUEUE_PORT> -> "q r u"
run() {
    # shellcheck disable=SC2034  # read by Resolve_Ports
    SERVER_PORT="$1" QUERY_PORT="$2" RCON_PORT="$3" QUEUE_PORT="$4"
    Resolve_Ports || { echo "ERR"; return; }
    echo "${RESOLVED_QUERY_PORT} ${RESOLVED_RCON_PORT} ${RESOLVED_QUEUE_PORT}"
}

check "all from env"                "7778 7779 7780" "$(run 7777 7778 7779 7780)"
check "env values need not be contiguous" "9000 9100 9200" "$(run 7777 9000 9100 9200)"
check "all missing -> offsets"      "7778 7779 7780" "$(run 7777 '' '' '')"
check "zero means auto"             "7778 7779 7780" "$(run 7777 0 0 0)"
check "old egg default collision (44000 x2)" "7778 44000 7780" "$(run 7777 '' 44000 44000)"
check "collides with game port"     "7778 7779 7780" "$(run 7777 7777 7777 7777)"
check "invalid values"              "7778 7779 7780" "$(run 7777 abc 70000 -1)"
check "fallback skips taken offset" "7779 7778 7780" "$(run 7777 '' 7778 '')"
check "invalid SERVER_PORT"         "ERR" "$(run '' 1 2 3)"
check "near top of range"           "65532 65533 65534" "$(run 65531 '' '' '')"

SERVER_PORT=7777 QUERY_PORT='' RCON_PORT=9000 QUEUE_PORT='' Resolve_Ports
[[ "$PORT_SOURCES" == *"rcon=9000(env)"* && "$PORT_SOURCES" == *"query=7778(SERVER_PORT+1)"* ]] \
    && pass "PORT_SOURCES describes origins" || fail "PORT_SOURCES: $PORT_SOURCES"
finish
