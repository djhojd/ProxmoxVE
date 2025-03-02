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
SELECT_STATUS=()
MSG_MAX_LENGTH=0

# Add actual containers to arrays
while read -r TAG ITEM REST; do
  OFFSET=2
  DISPLAY="$TAG: $ITEM"
  ((${#DISPLAY} + OFFSET > MSG_MAX_LENGTH)) && MSG_MAX_LENGTH=${#DISPLAY}+OFFSET
  CONTAINER_IDS+=("$TAG")
  CONTAINER_NAMES+=("$DISPLAY")
  SELECT_STATUS+=("ON")
done < <(pct list | awk 'NR>1 {printf "%s %s\n", $1, $2}')

if [ ${#CONTAINER_IDS[@]} -eq 0 ]; then
  echo -e "${RD}[Error]${CL} No containers found."
  exit 1
fi

# Container selection loop
while true; do
  # Build the menu items with current selection status
  MENU_ITEMS=()
  MENU_ITEMS+=("SELECTALL" "--- SELECT ALL CONTAINERS ---" "OFF")
  MENU_ITEMS+=("DESELECTALL" "--- DESELECT ALL CONTAINERS ---" "OFF")
  MENU_ITEMS+=("CONTINUE" "--- CONTINUE WITH CURRENT SELECTION ---" "OFF")

  # Add containers with their current select status
  for i in "${!CONTAINER_IDS[@]}"; do
    MENU_ITEMS+=("${CONTAINER_IDS[i]}" "${CONTAINER_NAMES[i]}" "${SELECT_STATUS[i]}")
  done

  # Show the checklist
  CHOICE=$(whiptail --backtitle "Container Command Runner" \
    --title "Select Containers" \
    --checklist "\nSelect containers or use the actions at the top:" \
    20 $((MSG_MAX_LENGTH + 60)) 12 \
    "${MENU_ITEMS[@]}" 3>&1 1>&2 2>&3) || exit 1

  # Clean up container IDs (remove quotes)
  CHOICE=$(echo "$CHOICE" | tr -d '"')

  # Process special actions
  if [[ "$CHOICE" == *"SELECTALL"* ]]; then
    # Select all containers
    for i in "${!SELECT_STATUS[@]}"; do
      SELECT_STATUS[i]="ON"
    done
    continue
  elif [[ "$CHOICE" == *"DESELECTALL"* ]]; then
    # Deselect all containers
    for i in "${!SELECT_STATUS[@]}"; do
      SELECT_STATUS[i]="OFF"
    done
    continue
  elif [[ "$CHOICE" == *"CONTINUE"* ]]; then
    # Process selected containers based on current SELECT_STATUS
    SELECTED_CONTAINERS=""
    for i in "${!CONTAINER_IDS[@]}"; do
      if [[ "${SELECT_STATUS[i]}" == "ON" ]]; then
        SELECTED_CONTAINERS+="${CONTAINER_IDS[i]} "
      fi
    done
    SELECTED_CONTAINERS="${SELECTED_CONTAINERS% }" # Remove trailing space
    break
  else
    # Update selection status based on user's choices
    for i in "${!CONTAINER_IDS[@]}"; do
      if [[ "$CHOICE" == *"${CONTAINER_IDS[i]}"* ]]; then
        SELECT_STATUS[i]="ON"
      else
        SELECT_STATUS[i]="OFF"
      fi
    done
    continue # Show the menu again with updated selections
  fi
done

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
