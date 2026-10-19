#!/bin/bash

source "${HELPERS_DIR:-/helpers}/messages.sh"

# Define colors
BOLD="\e[1m"
GREEN="\e[32m"
RESET="\e[0m"

# Clear screen for a fresh display
clear

# Pine Hosting Banner
echo -e "${GREEN}╭─────────────────────────────────────────────────────╮"
echo -e "${GREEN}│${BOLD}                     PINE HOSTING                    ${RESET}${GREEN}│"
echo -e "${GREEN}├─────────────────────────────────────────────────────┤"
echo -e "${GREEN}│${BOLD} WE ARE GETTING YOUR SERVER READY. PLEASE BE PATIENT ${RESET}${GREEN}│"
echo -e "${GREEN}├─────────────────────────────────────────────────────┤"
echo -e "${GREEN}│${BOLD}  Join our Discord: https://discord.pinehosting.com  ${RESET}${GREEN}│"
echo -e "${GREEN}├─────────────────────────────────────────────────────┤"
echo -e "${GREEN}│${BOLD}          Visit us: https://pinehosting.com          ${RESET}${GREEN}│"
echo -e "${GREEN}╰─────────────────────────────────────────────────────╯${RESET}"