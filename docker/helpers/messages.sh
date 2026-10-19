#!/bin/bash

source "${HELPERS_DIR:-/helpers}/colors.sh"

function Error() {
	local message="${1:-}"
	local exit_code="${2:-}"
	printf "${RED}ERROR: $message${NC}\n"

	# An optional second argument exits the script with that code.
	if [[ -n "$exit_code" ]]; then
		if [[ "$exit_code" == "1" ]]; then
			exit 1
		elif [[ "$exit_code" == "0" ]]; then
			exit 0
		fi
	fi
}

function Warn() {
	local message="${1:-}"
	printf "${YELLOW}WARNING: $message${NC}\n"
}

function Info() {
	local message="${1:-}"
	printf "${BLUE}$message${NC}\n"
}

function Success() {
	local message="${1:-}"
	printf "${GREEN}SUCCESS: $message${NC}\n"
}

function Debug() {
	local message="${1:-}"
	if [[ "${EGG_DEBUG:-0}" == "1" ]]; then
		echo "[DEBUG] $message"
	fi
}

##########
# Colors #
##########

function Green() {
	local message="${1:-}"
	printf "${GREEN}$message${NC}\n"
}