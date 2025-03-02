#!/usr/bin/env bash

# Set error handling
set -euo pipefail

# Color definitions
BL="\033[36m"
RD="\033[01;31m"
GN="\033[1;92m"
YW="\033[33m"
CL="\033[m"

function header_info {
  clear
  cat <<"EOF"
   ____            _        _                  
  / ___|___  _ __ | |_ __ _(_)_ __   ___ _ __ 
 | |   / _ \| '_ \| __/ _` | | '_ \ / _ \ '__|
 | |__| (_) | | | | || (_| | | | | |  __/ |   
  \____\___/|_| |_|\__\__,_|_|_| |_|\___|_|   
   ____                                        
  / ___|___  _ __ ___  _ __ ___   __ _ _ __   
 | |   / _ \| '_ ` _ \| '_ ` _ \ / _` | '_ \  
 | |__| (_) | | | | | | | | | | | (_| | | | | 
  \____\___/|_| |_| |_|_| |_| |_|\__,_|_| |_| 
  ____                                         
 |  _ \ _   _ _ __  _ __   ___ _ __           
 | |_) | | | | '_ \| '_ \ / _ \ '__|          
 |  _ <| |_| | | | | | | |  __/ |             
 |_| \_\\__,_|_| |_|_| |_|\___|_|             
EOF
}

header_info
echo "Loading..."

# Get container list
echo -e "${BL}[Info]${GN} Getting container list...${CL}"

# Prepare for whiptail container selection
CONTAINER_IDS=()
CONTAINER_NAMES=()
MSG_MAX_LENGTH=0

# Add actual containers to arrays
while read -r TAG ITEM REST; do
  OFFSET=2
  DISPLAY="$TAG: $ITEM"
  ((${#DISPLAY} + OFFSET > MSG_MAX_LENGTH)) && MSG_MAX_LENGTH=${#DISPLAY}+OFFSET
  CONTAINER_IDS+=("$TAG")
  CONTAINER_NAMES+=("$DISPLAY")
done < <(pct list | awk 'NR>1 {printf "%s %s\n", $1, $2}')

if [ ${#CONTAINER_IDS[@]} -eq 0 ]; then
  echo -e "${RD}[Error]${CL} No containers found."
  exit 1
fi

# Ask if user wants to select all containers
if whiptail --backtitle "Container Command Runner" \
  --title "Container Selection" \
  --yesno "\nDo you want to select all containers?" 10 60; then

  # User chose Yes - set all containers to ON initially
  MENU_ITEMS=()
  for i in "${!CONTAINER_IDS[@]}"; do
    MENU_ITEMS+=("${CONTAINER_IDS[i]}" "${CONTAINER_NAMES[i]}" "ON")
  done

  whiptail --backtitle "Container Command Runner" \
    --title "Selected Containers" \
    --checklist "\nThe following containers will be used (press OK to continue):" \
    20 $((MSG_MAX_LENGTH + 60)) 12 \
    "${MENU_ITEMS[@]}" --separate-output 3>&1 1>&2 2>&3

  # Create the list of selected containers
  SELECTED_CONTAINERS=""
  for container in "${CONTAINER_IDS[@]}"; do
    SELECTED_CONTAINERS+="$container "
  done
  SELECTED_CONTAINERS="${SELECTED_CONTAINERS% }" # Remove trailing space

else
  # User chose No - set all containers to OFF initially
  MENU_ITEMS=()
  for i in "${!CONTAINER_IDS[@]}"; do
    MENU_ITEMS+=("${CONTAINER_IDS[i]}" "${CONTAINER_NAMES[i]}" "OFF")
  done

  # Container selection loop
  while true; do
    # Show the checklist
    CHOICE=$(whiptail --backtitle "Container Command Runner" \
      --title "Select Containers" \
      --checklist "\nSelect containers or use the actions at the top:" \
      20 $((MSG_MAX_LENGTH + 60)) 12 \
      "${MENU_ITEMS[@]}" 3>&1 1>&2 2>&3) || exit 1

    # Clean up container IDs (remove quotes)
    CHOICE=$(echo "$CHOICE" | tr -d '"')

    # Set SELECTED_CONTAINERS based on user choice
    SELECTED_CONTAINERS="$CHOICE"

    # Break out of the loop now that we have selections
    break
  done
fi

if [ -z "$SELECTED_CONTAINERS" ]; then
  echo -e "${RD}[Warning]${CL} No containers selected. Exiting."
  exit 0
fi

# Get the command to run
COMMAND=$(whiptail --backtitle "Container Command Runner" \
  --title "Command Input" \
  --inputbox "\nEnter the command to run in selected containers:" \
  10 70 "apt update && apt upgrade -y" 3>&1 1>&2 2>&3) || exit 1

if [ -z "$COMMAND" ]; then
  echo -e "${RD}[Warning]${CL} No command entered. Exiting."
  exit 0
fi

# Confirm execution
whiptail --backtitle "Container Command Runner" \
  --title "Confirm Execution" \
  --yesno "\nReady to execute:\n\n${COMMAND}\n\non the selected containers?" \
  12 70 || exit 0

# Execute command on each container
echo -e "${BL}[Info]${GN} Executing command on selected containers...${CL}\n"

for container in $SELECTED_CONTAINERS; do
  status=$(pct status $container)

  if [ "$status" == "status: stopped" ]; then
    echo -e "${YW}[Warning]${CL} Container ${BL}$container${CL} is stopped. Skipping."
    continue
  fi

  echo -e "${BL}[Info]${GN} Running command on container ${BL}$container${CL}:${CL}"

  # Execute the command and capture output
  if OUTPUT=$(pct exec "$container" -- bash -c "$COMMAND" 2>&1); then
    echo -e "${GN}[Success]${CL} Command executed on ${BL}$container${CL}${GN} successfully${CL}"
    echo -e "${YW}--- Output ---${CL}"
    echo "$OUTPUT"
    echo -e "${YW}-------------${CL}\n"
  else
    echo -e "${RD}[Error]${CL} Failed to execute command on ${BL}$container${CL}"
    echo -e "${YW}--- Error Output ---${CL}"
    echo "$OUTPUT"
    echo -e "${YW}------------------${CL}\n"
  fi
done

echo -e "\n${GN}All operations completed.${CL}"
