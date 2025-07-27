#!/bin/bash
# Run as asterisk or root

set +H  # Disable Bash history expansion (! operator)

# Node configuration
CONFIG_FILE="/opt/digital_link/switch_modes.conf"
LOG_FILE="/opt/digital_link/dvswitch_links.log"
DVSWITCH_APP="/opt/MMDVM_Bridge/dvswitch.sh"

echo "$(date): Executing with $1" >> $LOG_FILE

# Extract NODE_ID and LINKED_NODE_ID from [NodeInfo] section
NODE_ID=$(awk '
    /^\[NodeInfo\]/ { in_section=1; next }
    /^\[.*\]/ { in_section=0 }
    in_section && $1 ~ /^NODE_ID=/ { split($0,a,"="); print a[2]; exit }
' "$CONFIG_FILE")

LINKED_NODE_ID=$(awk '
    /^\[NodeInfo\]/ { in_section=1; next }
    /^\[.*\]/ { in_section=0 }
    in_section && $1 ~ /^LINKED_NODE_ID=/ { split($0,a,"="); print a[2]; exit }
' "$CONFIG_FILE")

echo "$(date): Node ID ${NODE_ID}, Linked Node ID ${LINKED_NODE_ID}" >> $LOG_FILE

# Input DTMF string
DTMF=$1
DTMF=${DTMF:1} # remove the initial digit to Asterisk
DTMF=${DTMF//\*/\#} # replace * with # for parsing purposes

# Validate input
if [[ -z "$DTMF" ]]; then
    echo "Invalid DTMF command. Exiting."
    echo "$(date): Invalid DTMF command ${DTMF}" >> $LOG_FILE
    exit 1
fi

MODE_DIGIT=${DTMF:0:1}   # First digit (mode)
MASTER=${DTMF:1:1}       # Second digit (master)
TG=${DTMF:2}             # Remaining digits (talkgroup ID)

unlink_current_mode() {
    # Constants — scalar or array allowed
    DMR_UNLINK=(4000 disconnect)  
    DSTAR_UNLINK=U
    YSF_UNLINK=4000
    NXDN_UNLINK=9999
    P25_UNLINK=9999

    # Determine current mode
    local current_mode=$(${DVSWITCH_APP} mode)

    # Helper function to tune on either a string or array
    tune_on_values() {
        local varname=$1
        declare -n ref=$varname   # Nameref to allow dynamic referencing of variable

        if declare -p "$varname" 2>/dev/null | grep -q 'declare \-a'; then
            # It's an array, loop over values
            for val in "${ref[@]}"; do
                ${DVSWITCH_APP} tune "$val"
            done
        else
            # Not an array, treat as scalar
            ${DVSWITCH_APP} tune "${ref}"
        fi
    }

    # Handle unlinking for each mode
    case $current_mode in
        DMR)
            tune_on_values DMR_UNLINK
            ;;
        DSTAR)
            tune_on_values DSTAR_UNLINK
            ;;
        YSF|YSFN)
            tune_on_values YSF_UNLINK
            ;;
        NXDN)
            tune_on_values NXDN_UNLINK
            ;;
        P25)
            tune_on_values P25_UNLINK
            ;;
        *)
            echo "WARNING: Unable to unlink unsupported mode: $current_mode"
            echo "WARNING: Unable to unlink unsupported mode: $current_mode" >> "$LOG_FILE"
            return 1
            ;;
    esac

    echo "Unlinked on mode $current_mode"
    echo "$(date): Unlinked on mode $current_mode" >> "$LOG_FILE"
}

# Disconnect and Unlink only when MODE and MASTER are both 0
if [[ "$MODE_DIGIT" == "0" && "$MASTER" == "0" ]]; then
    echo "Disconnecting node $NODE_ID from AllStarLink..."
    echo "Disconnecting node $NODE_ID from AllStarLink..." >> $LOG_FILE

    # Unlink current mode
    unlink_current_mode   

    # Disconnect NODE_ID from LINKED_NODE_ID
    asterisk -rx "rpt cmd $NODE_ID ilink 1 ${LINKED_NODE_ID}"

    echo "Node $NODE_ID disconnected from AllStarLink."
    echo "$(date): Disconnected node $NODE_ID" >> $LOG_FILE
    
    exit 0
fi

# Unlink from current mode when MODE is 0
if [[ "$MODE_DIGIT" == "0" ]]; then
    echo "Unlinking only"
    
    # Unlink current mode
    unlink_current_mode

    echo "Node $NODE_ID unlinked."
    echo "$(date): Unlinked from current node" >> $LOG_FILE
    
    exit 0
fi

# Ensure NODE_ID is connected to LINKED_NODE_ID
CURRENT_CONNECTION=$(asterisk -rx "rpt lstats $NODE_ID" | grep "ESTABLISHED")
if [[ -n "$CURRENT_CONNECTION" && "$CURRENT_CONNECTION" != *"$LINKED_NODE_ID"* ]]; then
    echo "Disconnecting from other nodes..."
    echo "Disconnecting from other nodes..." >> $LOG_FILE
    asterisk -rx "rpt cmd $NODE_ID ilink 6 1"
fi
if [[ "$CURRENT_CONNECTION" != *"$LINKED_NODE_ID"* ]]; then
    echo "Connecting node $NODE_ID to $LINKED_NODE_ID..."
    echo "Connecting node $NODE_ID to $LINKED_NODE_ID..." >> $LOG_FILE
    asterisk -rx "rpt fun $NODE_ID *3$LINKED_NODE_ID"
    sleep 2
fi

# Find the configuration section matching the master value
SECTION=$(awk -v modemaster="${MODE_DIGIT}${MASTER}" '
    /^\[.*\]/ { section=$0; in_section=0 }   # Capture section name and reset in_section
    $0 ~ "modemaster="modemaster { in_section=1 }  # Match modemaster exactly
    in_section { print section; exit }      # Print section name and exit when in_section is set
' "$CONFIG_FILE")

if [[ -z "$SECTION" ]]; then
    echo "No matching configuration for MASTER=${MASTER}. Exiting."
    echo "No matching configuration for MASTER=${MASTER}. Exiting." >> $LOG_FILE
    exit 1
fi

# Extract details from the matching section
MODE=$(awk -v section="$SECTION" '
    $0 == section { in_section=1; next }  # Enter the section
    in_section && /^\[.*\]/ { exit }      # Exit on the next section
    in_section && $1 ~ /^mode=/ { split($0, a, "="); print a[2]; exit }
' "$CONFIG_FILE")

URL=$(awk -v section="$SECTION" '
    $0 == section { in_section=1; next }
    in_section && /^\[.*\]/ { exit }
    in_section && $1 ~ /^url=/ { split($0, a, "="); print a[2]; exit }
' "$CONFIG_FILE")

PORT=$(awk -v section="$SECTION" '
    $0 == section { in_section=1; next }
    in_section && /^\[.*\]/ { exit }
    in_section && $1 ~ /^port=/ { split($0, a, "="); print a[2]; exit }
' "$CONFIG_FILE")

PASSWORD=$(awk -v section="$SECTION" '
    $0 == section { in_section=1; next }
    in_section && /^\[.*\]/ { exit }
    in_section && $1 ~ /^password=/ { split($0, a, "="); print a[2]; exit }
' "$CONFIG_FILE")

TYPE=$(awk -v section="$SECTION" '
    $0 == section { in_section=1; next }
    in_section && /^\[.*\]/ { exit }
    in_section && $1 ~ /^type=/ { split($0, a, "="); print a[2]; exit }
' "$CONFIG_FILE")

# Unlink current mode
unlink_current_mode  
    
# Select the mode and tune the talkgroup
echo "Switching to mode $MODE, MASTER=${MASTER}, TG: $TG, URL: $URL, PORT: $PORT, PASSWORD: $PASSWORD, TYPE: $TYPE"

if [[ "$MODE" == "D-STAR" ]]; then
    if [[ "${TG: -1}" == "D" ]]; then
        TG="${TG%#}E"  # Remove the last character (D) and append E
    fi
    TG="${TYPE}${TG}L"  # Always prepend $TYPE (REF, XLX, ...) and append L for D-STAR
fi

if [[ "$MODE" == "DMR" && "${TG: -1}" == "D" ]]; then
    TG="${TG%?}#" # Transform 'D' suffix on TG to '#' for DMR mode which may need to be escaped
fi

case $MODE in
    DMR)
        ${DVSWITCH_APP} mode DMR
        echo Executing: ${DVSWITCH_APP} mode DMR
        echo Executing: ${DVSWITCH_APP} mode DMR >> $LOG_FILE 
        ${DVSWITCH_APP} tune "${PASSWORD}@${URL}:${PORT}" # Optionally, !${TG}, but this does not support private calls
        echo Executing: ${DVSWITCH_APP} tune "${PASSWORD}@${URL}:${PORT}"
        echo Executing: ${DVSWITCH_APP} tune "${PASSWORD}@${URL}:${PORT}" >> $LOG_FILE 
        ${DVSWITCH_APP} tune "${TG}" 
        echo Executing: ${DVSWITCH_APP} tune "${TG}"
        echo Executing: ${DVSWITCH_APP} tune "${TG}" >> $LOG_FILE         
        ;;
    D-STAR)
        ${DVSWITCH_APP} mode DSTAR
        echo Executing: ${DVSWITCH_APP} mode DSTAR >> $LOG_FILE 
        echo Executing: ${DVSWITCH_APP} mode DSTAR 
        ${DVSWITCH_APP} tune "${TG}"
        echo Executing: ${DVSWITCH_APP} tune "${TG}" >> $LOG_FILE 
        echo Executing: ${DVSWITCH_APP} tune "${TG}" 
        ;;
    YSF)
        ${DVSWITCH_APP} mode YSF
        echo Executing: ${DVSWITCH_APP} mode YSF >> $LOG_FILE 
        echo Executing: ${DVSWITCH_APP} mode YSF 
        ${DVSWITCH_APP} tune "${URL}:${PORT}"
        echo Executing: ${DVSWITCH_APP} tune "${URL}:${PORT}" >> $LOG_FILE 
        echo Executing: ${DVSWITCH_APP} tune "${URL}:${PORT}" 
        ;;
    NXDN)
        ${DVSWITCH_APP} mode NXDN
        echo Executing: ${DVSWITCH_APP} mode NXDN >> $LOG_FILE
        echo Executing: ${DVSWITCH_APP} mode NXDN
        ${DVSWITCH_APP} tune "${TG}"
        echo Executing: ${DVSWITCH_APP} tune "${TG}" >> $LOG_FILE
        echo Executing: ${DVSWITCH_APP} tune "${TG}"
        ;;
    P25)
        ${DVSWITCH_APP} mode P25
        echo Executing: ${DVSWITCH_APP} mode P25 >> $LOG_FILE 
        echo Executing: ${DVSWITCH_APP} mode P25
        ${DVSWITCH_APP} tune "${TG}"
        echo Executing: ${DVSWITCH_APP} tune "${TG}" >> $LOG_FILE 
        echo Executing: ${DVSWITCH_APP} tune "${TG}"
        ;;        
    *)
        echo "Unsupported mode: $MODE"
        echo "Unsupported mode: $MODE" >> $LOG_FILE 
        exit 1
        ;;
esac

# Log the action
echo "$(date): Connected to node $NODE_ID, Mode=$MODE, Master=$MASTER, TG=$TG" >> $LOG_FILE 
