#!/bin/bash

##################
# PORT RESOLVER  #
##################
#
# The egg's allocation block is (port_names order): main, query, rcon, queue.
# (The query port is only bound by Legacy; Evrima-based branches answer on
# the game port.)
# Each extra port is taken from its environment variable (filled by the panel's
# allocation tooling) when it is a valid port that does not collide with the
# primary port or another extra port. Anything missing, "0", invalid or
# colliding falls back to SERVER_PORT + its offset in the block (+1 query,
# +2 rcon, +3 queue); if that offset is taken by an accepted env value the next
# free slot of the 5-port block is used instead.
#
# Sets RESOLVED_QUERY_PORT, RESOLVED_RCON_PORT, RESOLVED_QUEUE_PORT and
# PORT_SOURCES (human-readable summary). Returns 1 if SERVER_PORT is invalid.

_Is_Valid_Port() {
    [[ "${1:-}" =~ ^[0-9]+$ ]] && (( 10#$1 >= 1 && 10#$1 <= 65535 ))
}

# shellcheck disable=SC2034  # RESOLVED_* / PORT_SOURCES are read by callers.
Resolve_Ports() {
    local main="${SERVER_PORT:-}"
    if ! _Is_Valid_Port "$main"; then
        return 1
    fi
    main=$((10#$main))

    local names=(QUERY RCON QUEUE)
    local -A offset=([QUERY]=1 [RCON]=2 [QUEUE]=3)
    local -A value=()
    local -A source=()
    local -A used=(["$main"]=1)
    local n v

    # Pass 1: accept valid, distinct environment values.
    for n in "${names[@]}"; do
        local var="${n}_PORT"
        v="${!var:-}"
        v="${v//[[:space:]]/}"
        if _Is_Valid_Port "$v" && [[ -z "${used[$((10#$v))]:-}" ]]; then
            v=$((10#$v))
            value[$n]=$v
            source[$n]="env"
            used[$v]=1
        fi
    done

    # Pass 2: fill the rest from the allocation block.
    local k cand
    for n in "${names[@]}"; do
        [[ -n "${value[$n]:-}" ]] && continue
        cand=$((main + offset[$n]))
        if [[ -n "${used[$cand]:-}" ]] || (( cand > 65535 )); then
            cand=""
            for k in 1 2 3 4; do
                if [[ -z "${used[$((main + k))]:-}" ]] && (( main + k <= 65535 )); then
                    cand=$((main + k))
                    break
                fi
            done
        fi
        [[ -z "$cand" ]] && return 1
        value[$n]=$cand
        source[$n]="SERVER_PORT+$((cand - main))"
        used[$cand]=1
    done

    RESOLVED_QUERY_PORT="${value[QUERY]}"
    RESOLVED_RCON_PORT="${value[RCON]}"
    RESOLVED_QUEUE_PORT="${value[QUEUE]}"
    PORT_SOURCES="game=${main} query=${RESOLVED_QUERY_PORT}(${source[QUERY]}) rcon=${RESOLVED_RCON_PORT}(${source[RCON]}) queue=${RESOLVED_QUEUE_PORT}(${source[QUEUE]})"
    return 0
}
