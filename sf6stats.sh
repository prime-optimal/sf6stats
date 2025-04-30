#!/bin/bash
# sf6stats.sh
# MIT License © 2024 Nekorobi
version=v1.0.0

# Check if terminal supports colors
if [ -t 1 ]; then
    # Terminal supports colors
    RED='\033[0;31m'
    LIGHT_RED='\033[0;91m'
    GREEN='\033[0;32m'
    LIGHT_GREEN='\033[0;92m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    MAGENTA='\033[0;35m'
    CYAN='\033[0;36m'
    WHITE='\033[1;37m'
    BOLD='\033[1m'
    RESET='\033[0m'
else
    # Terminal doesn't support colors
    RED=''
    LIGHT_RED=''
    GREEN=''
    LIGHT_GREEN=''
    YELLOW=''
    BLUE=''
    MAGENTA=''
    CYAN=''
    WHITE=''
    BOLD=''
    RESET=''
fi

# Function to safely print colored text
print_color() {
    local color=$1
    shift
    printf '%b%s%b' "$color" "$*" "$RESET"
}

unset mode debug cacheDir yyyymm json  character rank ranking easyRanking input_type
rank=master  rankList=(rookie iron bronze silver gold platinum diamond master)

echo "Script starting..."

# Add trap to catch hanging processes
trap 'echo "Error: Script appears to be hanging. Exiting." >&2; exit 1' ALRM
trap 'rm -f "$json.tmp" 2>/dev/null' EXIT

help() {
  echo "In help function"
  cat << END
Usage: ./sf6stats.sh [Option]...

Show fighting stats of STREET FIGHTER 6.
Reference: https://www.streetfighter.com/6/buckler/stats/dia

Options:
  -c, --character Character (e.g. 'guile')
      Specify the character name in lowercase.
      Use --rank without --character to list all characters.
  -i, --interactive
      Select rank and character interactively (Ignore --character and --rank).
  -r, --rank rookie|iron|bronze|silver|gold|platinum|diamond|master
      Default: master
  -t, --type C|M
      Show stats for specific control type (Classic or Modern, case-insensitive).
      Default: Show consolidated stats for both types.
  --yyyymm YearMonth (since '202306')
      The stats are updated on the second Thursday of each month.
      Default: Latest stats

  -h, --help     Show help.
  -V, --version  Show version.

Cache: \$HOME/.cache/sf6stats/*.json
Dependent commands: jq, curl or wget

sf6stats.sh $version  https://github.com/nekorobi/sf6stats
MIT License © 2024 Nekorobi
END
}
error() { local s=$1; shift; echo -e "Error: $*" 1>&2; exit $s; }

echo "Processing arguments..."
# Store original arguments
original_args=("$@")
character_arg=""
character_val=""

# First pass: Process all arguments except --character
while [[ $# -gt 0 ]]; do
  case "$1" in
    -c|--character)
      # Store character argument for later processing
      character_arg=$1
      character_val=$2
      shift 2
      ;;
    -i|--interactive)
      mode=interactive
      shift
      ;;
    -r|--rank)
      [[ $# = 1 || $2 =~ ^- ]] && error 1 "$1: requires an argument"
      [[ $2 =~ ^(rookie|iron|bronze|silver|gold|platinum|diamond|master)$ ]] || error 1 "$1: no such rank: $2"
      rank=$2
      shift 2
      ;;
    -t|--type)
      [[ $# = 1 || $2 =~ ^- ]] && error 1 "$1: requires an argument"
      [[ $2 =~ ^[CcMm]$ ]] || error 1 "$1: must be either C or M: $2"
      # Convert to uppercase in a more compatible way
      if [[ $2 == "c" || $2 == "C" ]]; then
        input_type="C"
      else
        input_type="M"
      fi
      shift 2
      ;;
    --rm-cache)
      mode=rm-cache
      shift
      ;;
    --yyyymm)
      [[ $# = 1 || $2 =~ ^- ]] && error 1 "$1: requires an argument"
      [[ $2 =~ ^20[0-9]{4}$ ]] || error 1 "$1: incorrect format: $2"
      yyyymm=$2
      shift 2
      ;;
    --validate)
      mode=validate
      shift
      ;;
    --debug)
      debug=on
      shift
      ;;
    -h|--help)
      help
      exit 0
      ;;
    -V|--version)
      echo sf6stats.sh $version
      exit 0
      ;;
    # invalid
    -*)
      error 1 "$1: unknown option"
      ;;
    # Operand
    *)
      error 1 "$1: unknown argument"
      ;;
  esac
  echo "Processed argument: $1"
done

# Second pass: Process character argument if it exists
if [[ -n $character_arg ]]; then
  [[ -z $character_val || $character_val =~ ^- ]] && error 1 "$character_arg: requires an argument"
  # Always require lowercase letters for character name
  [[ $character_val =~ ^[a-z]+$ ]] || error 1 "$character_arg: incorrect format: $character_val (must be lowercase letters only)"
  character=$character_val
fi

echo "Arguments processed"
echo "Current yyyymm value: $yyyymm"


MakeCacheDir() {
  local dir=$XDG_CACHE_HOME; [[ $dir ]] || dir=$HOME/.cache; dir=$dir/$1
  mkdir -p "$dir" && [[ -w $dir && -x $dir ]] || return 1
  printf '%s' "$dir"
}
HttpGet() {
  echo "In HttpGet: Starting download from $1"
  local agent=$USER_AGENT; [[ $agent ]] || agent="Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"
  if type curl >/dev/null 2>&1; then
    echo "Using curl"
    # Try with different options to handle the receive error
    if ! curl -v -o "$2.tmp" --silent --compressed -A "$agent" --max-time 5 "$1" 2>&1; then
      # If that fails, try without compression
      echo "Retrying without compression..."
      if ! curl -v -o "$2.tmp" --silent -A "$agent" --max-time 5 "$1" 2>&1; then
        local curl_exit=$?
        echo "Curl exit code: $curl_exit"
        if [[ $curl_exit -eq 28 ]]; then
          error 11 "Request timed out. The server might be blocking access. Try again later."
        elif [[ $curl_exit -eq 56 ]]; then
          error 11 "Network error while receiving data. The server might be blocking access or the connection was interrupted."
        else
          error 11 "Failed to download data (curl exit code: $curl_exit). The server might be blocking access. Try again later."
        fi
      fi
    fi
    mv "$2.tmp" "$2"
  elif type wget >/dev/null 2>&1; then
    echo "Using wget"
    wget -O "$2.tmp" --quiet --compression=auto -U "$agent" --timeout=5 "$1" 2>&1
    local wget_exit=$?
    echo "Wget exit code: $wget_exit"
    [[ $wget_exit -ne 0 ]] && error 11 "Failed to download data. The server might be blocking access. Try again later."
    mv "$2.tmp" "$2"
  else return 3; fi
  echo "HttpGet completed"
}
SecondThursday() {
  # Format the date string with leading zeros for month
  local datestr=$(printf "%s-%02d-01" "$1" "$2")
  # Use macOS compatible date format to get day of week (0=Sunday, 4=Thursday)
  local first=$(date -j -f "%Y-%m-%d" "$datestr" "+%w")
  if [[ $first -le 4 ]]; then printf '%d' $((7 + 5 - $first)); else printf '%d' $((14 + 5 - $first)); fi
}

log() { if [[ $debug ]]; then echo -e "$@"; fi; }
getYyyymm() {
  export TZ=UTC; local today=$(date +%F) # e.g. 2024-01-23
  local year=${today:0:4}  month=${today:5:2}  day=${today: -2}; month=${month#0} day=${day#0} # '08' error
  if [[ $day -gt $(SecondThursday $year $month) ]]; then ((month--)); else ((month-=2)); fi
  if [[ $month -lt 1 ]]; then ((year--)); ((month+=12)); fi
  printf '%s%.2d' "$year" "$month"
}
downloadJson() {
  echo "In downloadJson"
  local url="https://www.streetfighter.com/6/buckler/api/en/stats/dia/$yyyymm"
  echo "Downloading from: $url"
  HttpGet "$url" "$json" || { [[ $? = 3 ]] && error 3 'requires curl or wget'; error 11 "can not GET: $url"; }
  echo "Download complete, validating JSON"
  jq -e '.diaData | type == "object"' "$json" >/dev/null || { rm "$json"; error 12 "can not GET JSON: $url"; }
}
validateJson() {
  echo "In validateJson"
  # Choose between consolidated (c) or input-specific (ci) data
  local data_path=".diaData"
  if [[ -n $input_type ]]; then
    data_path="$data_path.ci.d_sort.\"8\".opponent_header"
  else
    data_path="$data_path.c.d_sort.\"8\".opponent_header"
  fi
  
  local masterHeader=$(jq "$data_path" "$json")
  local length=$(jq "length" <<<$masterHeader)
  [[ $length =~ ^[1-9][0-9]*$ ]] || error 20 "can not parse JSON: $json"
  echo "opponent_header.length: $length"
  
  # Check for required fields based on data type
  if [[ -n $input_type ]]; then
    local every="map(has(\"input_type\"), has(\"tool_name\"), has(\"_dsort\")) | all"
  else
    local every="map(has(\"tool_name\"), has(\"_dsort\")) | all"
  fi
  jq -e "$every" <<<$masterHeader >/dev/null || error 21 "can not parse JSON: $json"
}

rankIndex() {
  echo "In rankIndex for rank: $rank" >&2
  for i in "${!rankList[@]}"; do
    if [[ ${rankList[$i]} = $rank ]]; then 
      echo "Found rank index: $((i+1))" >&2
      printf '%d' $((i+1))
      return 0
    fi
  done
  return 1
}
makeRanking() {
  echo "In makeRanking"
  local rank_idx
  rank_idx=$(rankIndex) || error 1 "Invalid rank: $rank"
  echo "Using rank index: $rank_idx"
  
  # Choose between consolidated (c) or input-specific (ci) data
  local data_path=".diaData"
  if [[ -n $input_type ]]; then
    data_path="$data_path.ci.d_sort.\"$rank_idx\".opponent_header[]"
    local data='.input_type + " " + .tool_name + " " + (if (._dsort | type) == "number" then (._dsort*10 | tostring) else "null" end)'
  else
    data_path="$data_path.c.d_sort.\"$rank_idx\".opponent_header[]"
    local data='.tool_name + " " + (if (._dsort | type) == "number" then (._dsort*10 | tostring) else "null" end)'
  fi
  
  echo "Running jq query: $data_path | $data"
  local lines; lines=$(jq -r "$data_path | $data" "$json") ||
    error 25 "can not parse JSON: $json"
  echo "Jq query completed, processing lines"
  unset ranking
  while IFS= read -r line; do
    if [[ $line =~ null$ ]]; then
      if [[ -n $input_type ]]; then
        # Format: "C deejay --"
        local type=${line%% *}
        local char=${line#* }
        char=${char%% *}
        ranking[${#ranking[@]}]=$(printf '%-10s -- %1s' "$char" "$type")
      else
        # Format: "deejay --"
        ranking[${#ranking[@]}]=$(printf '%-10s --' "${line%null}")
      fi
    else
      if [[ -n $input_type ]]; then
        # Format: "C deejay 5.123 C"
        local type=${line%% *}
        local rest=${line#* }
        local char=${rest%% *}
        local value=${rest##* }
        ranking[${#ranking[@]}]=$(printf '%-10s %6.3f %1s' "$char" "$value" "$type")
      else
        # Format: "deejay 5.123"
        local character=${line%% *}
        local value=${line##* }
        ranking[${#ranking[@]}]=$(printf '%-10s %6.3f' "$character" "$value")
      fi
    fi
  done <<<"$lines"
  echo "Processed ${#ranking[@]} ranking entries"
}
showRanking() {
  echo "In showRanking"
  local i=1
  # Display in 4 columns when input type is specified, otherwise 3 columns
  local cols
  if [[ -n $input_type ]]; then
    cols=4
  else
    cols=3
  fi
  local total=${#ranking[@]}
  local rows=$(( (total + cols - 1) / cols ))  # Ceiling division
  
  # Print header
  print_color "$BOLD$CYAN" "[$rank] win rate ranking: ${yyyymm:0:4}-${yyyymm:4}"
  echo
  
  # Print rankings in columns
  for ((row=0; row<rows; row++)); do
    for ((col=0; col<cols; col++)); do
      local idx=$((row + col*rows))
      if (( idx < total )); then
        local entry="${ranking[idx]}"
        local char=${entry%% *}
        local rest=${entry#* }
        
        printf '%2d) ' $((idx+1))
        print_color "$BOLD" "$char"  # Removed WHITE color
        printf ' '
        
        if [[ -n $input_type ]]; then
          # Format with input type: "char 5.123 C" or "char -- C"
          local value=${rest%% *}
          local type=${rest##* }
          
          # Handle self-matches without color
          if [[ $value == "--" ]]; then
            printf '%s %s' "$value" "$type"
          else
            # Use awk for floating-point comparison with multiple thresholds
            if awk -v val="$value" 'BEGIN { exit !(val >= 5.5) }'; then
              print_color "$GREEN" "$value"
            elif awk -v val="$value" 'BEGIN { exit !(val >= 5.2) }'; then
              print_color "$LIGHT_GREEN" "$value"
            elif awk -v val="$value" 'BEGIN { exit !(val >= 4.8) }'; then
              print_color "$YELLOW" "$value"  # Use yellow for middle range
            elif awk -v val="$value" 'BEGIN { exit !(val >= 4.5) }'; then
              print_color "$LIGHT_RED" "$value"
            else
              print_color "$RED" "$value"
            fi
            printf ' %s' "$type"
          fi
        else
          # Format without input type: "char 5.123" or "char --"
          local value=$rest
          
          # Handle self-matches without color
          if [[ $value == "--" ]]; then
            printf '%s' "$value"
          else
            # Use awk for floating-point comparison with multiple thresholds
            if awk -v val="$value" 'BEGIN { exit !(val >= 5.5) }'; then
              print_color "$GREEN" "$value"
            elif awk -v val="$value" 'BEGIN { exit !(val >= 5.2) }'; then
              print_color "$LIGHT_GREEN" "$value"
            elif awk -v val="$value" 'BEGIN { exit !(val >= 4.8) }'; then
              print_color "$YELLOW" "$value"  # Use yellow for middle range
            elif awk -v val="$value" 'BEGIN { exit !(val >= 4.5) }'; then
              print_color "$LIGHT_RED" "$value"
            else
              print_color "$RED" "$value"
            fi
          fi
        fi
        printf '  '
      fi
    done
    echo
  done
  echo
}
makeEasyRanking() {
  # Choose between consolidated (c) or input-specific (ci) data
  local data_path=".diaData"
  local char_name=$character
  local char_type=$input_type
  
  if [[ -n $input_type ]]; then
    data_path="$data_path.ci.d_sort.\"$(rankIndex)\".records[]"
    local select="select(.tool_name==\"$char_name\" and .input_type==\"$char_type\") | .values"
  else
    data_path="$data_path.c.d_sort.\"$(rankIndex)\".records[]"
    local select="select(.tool_name==\"$char_name\") | .values"
  fi
  
  echo "Running jq query: $data_path | $select"
  local val; val=$(jq "$data_path | $select" "$json") || error 26 "can not parse JSON: $json"
  [[ $(jq 'length' <<<$val) = ${#ranking[@]} ]] || error 27 "invalid JSON: $json"
  
  # Process the values and create arrays for sorting and display
  local sort_keys=()
  local display_values=()
  local i=1
  
  # Debug output (commented out)
  # echo "DEBUG: Processing values for makeEasyRanking"
  # echo "DEBUG: Character: $character, Input Type: $input_type"
  # echo "DEBUG: JSON value: $val"
  
  while IFS= read -r line; do
    # Remove quotes and handle special cases
    line=${line//\"/}
    local char=${ranking[i-1]%% *}
    local type=""
    
    # Extract type if available
    if [[ -n $input_type ]]; then
      if [[ ${ranking[i-1]} =~ [[:space:]][CM]$ ]]; then
        type=${ranking[i-1]##* }
      fi
    fi
    
    # echo "DEBUG: Processing line: $line for char: $char, type: $type"
    
    if [[ $line == "-" || $line == "-.---" ]]; then
      sort_keys+=("-1")  # Place self-matches at the end
      if [[ -n $input_type ]]; then
        display_values+=("$(printf '%-10s -- %1s' "$char" "$type")")
      else
        display_values+=("$(printf '%-10s --' "$char")")
      fi
    else
      # Format the value with three decimal places
      if [[ $line == "10.000" ]]; then
        sort_keys+=("10.000")
        if [[ -n $input_type ]]; then
          display_values+=("$(printf '%-10s 10.000 %1s' "$char" "$type")")
        else
          display_values+=("$(printf '%-10s 10.000' "$char")")
        fi
      else
        # Keep the raw value with three decimal places
        sort_keys+=("$line")
        if [[ -n $input_type ]]; then
          display_values+=("$(printf '%-10s %6.3f %1s' "$char" "$line" "$type")")
        else
          display_values+=("$(printf '%-10s %6.3f' "$char" "$line")")
        fi
      fi
    fi
    ((i++))
  done < <(jq ".[].val" <<<"$val")
  
  # echo "DEBUG: Processed ${#display_values[@]} display values"

  # Sort the indices based on the sort keys
  local sorted_indices=()
  for i in "${!sort_keys[@]}"; do
    sorted_indices+=("$i ${sort_keys[$i]}")
  done

  # Sort and create the final sorted display array
  local sorted_display=()
  while IFS= read -r line; do
    local idx=${line%% *}
    sorted_display+=("${display_values[$idx]}")
  done < <(printf '%s\n' "${sorted_indices[@]}" | sort -nr -k2,2)

  # Display in 4 columns when input type is specified, otherwise 3 columns
  local cols
  if [[ -n $input_type ]]; then
    cols=4
  else
    cols=3
  fi
  local total=${#sorted_display[@]}
  local rows=$(( (total + cols - 1) / cols ))  # Ceiling division
  
  print_color "$BOLD$CYAN" "[$rank] $character's win rate (1st column):"
  echo
  
  for ((row=0; row<rows; row++)); do
    for ((col=0; col<cols; col++)); do
      local idx=$((row + col*rows))
      if (( idx < total )); then
        local entry="${sorted_display[idx]}"
        # echo "DEBUG: Entry: $entry"
        local char=${entry%% *}
        local rest=${entry#* }
        
        printf '%2d) ' $((idx+1))
        print_color "$BOLD" "$char"  # Removed WHITE color
        printf ' '
        
        if [[ -n $input_type ]]; then
          # Format with input type: "char 5.123 C" or "char -- C"
          # Split rest into value and type
          local parts=($rest)
          local value=${parts[0]}
          local type=${parts[1]}
          
          # echo "DEBUG: Value: $value, Type: $type"
          
          # Handle self-matches without color
          if [[ $value == "--" ]]; then
            printf '%s %s' "$value" "$type"
          else
            # Use awk for floating-point comparison with multiple thresholds
            if awk -v val="$value" 'BEGIN { exit !(val >= 5.5) }'; then
              print_color "$GREEN" "$value"
            elif awk -v val="$value" 'BEGIN { exit !(val >= 5.2) }'; then
              print_color "$LIGHT_GREEN" "$value"
            elif awk -v val="$value" 'BEGIN { exit !(val >= 4.8) }'; then
              print_color "$YELLOW" "$value"  # Use yellow for middle range
            elif awk -v val="$value" 'BEGIN { exit !(val >= 4.5) }'; then
              print_color "$LIGHT_RED" "$value"
            else
              print_color "$RED" "$value"
            fi
            printf ' %s' "$type"
          fi
        else
          # Format without input type: "char 5.123" or "char --"
          local value=$rest
          
          # Handle self-matches without color
          if [[ $value == "--" ]]; then
            printf '%s' "$value"
          else
            # Use awk for floating-point comparison with multiple thresholds
            if awk -v val="$value" 'BEGIN { exit !(val >= 5.5) }'; then
              print_color "$GREEN" "$value"
            elif awk -v val="$value" 'BEGIN { exit !(val >= 5.2) }'; then
              print_color "$LIGHT_GREEN" "$value"
            elif awk -v val="$value" 'BEGIN { exit !(val >= 4.8) }'; then
              print_color "$YELLOW" "$value"  # Use yellow for middle range
            elif awk -v val="$value" 'BEGIN { exit !(val >= 4.5) }'; then
              print_color "$LIGHT_RED" "$value"
            else
              print_color "$RED" "$value"
            fi
          fi
        fi
        printf '  '
      fi
    done
    echo
  done
}
charaExists() {
  local char_name=$character
  local char_type=$input_type
  
  # For both modes, just check if the character name exists in the ranking
  for e in "${ranking[@]%% *}"; do 
    if [[ $e == "$char_name" ]]; then
      return 0
    fi
  done
  
  return 1
}

selectRank() {
  print_color "$BOLD$CYAN" "Select: rank"
  echo
  select rank in "${rankList[@]}" "Quit"; do 
    if [[ $rank == "Quit" ]]; then
      exit 0
    elif [[ $rank ]]; then 
      break
    fi
  done
  makeRanking
  selectCharacter
}
selectCharacter() {
  showRanking
  local choices=("${ranking[@]}" "Select: rank" "Quit")
  local total=${#ranking[@]}
  local choice
  
  while true; do
    printf '%bSelect character (1-%d) or option (%bq%b to quit, %br%b for rank): %b' \
      "$BOLD" "$total" "$YELLOW" "$RESET" "$YELLOW" "$RESET" "$RESET"
    read -r choice
    case "$choice" in
      [1-9]|[1-9][0-9])
        if (( choice <= total )); then
          character=${ranking[choice-1]%% *}
          makeEasyRanking
          echo
          selectMenu
          break
        fi
        ;;
      r|R)
        selectRank
        break
        ;;
      q|Q)
        exit 0
        ;;
    esac
    print_color "$RED" "Invalid selection. Please try again."
    echo
  done
}
selectMenu() {
  select e in 'Select: character' 'Select: rank' 'Quit'; do
    if [[ $e == "Quit" ]]; then
      exit 0
    elif [[ $e == 'Select: rank' ]]; then
      selectRank
    else
      selectCharacter
    fi
    break
  done
}

echo "Checking for jq..."
type jq >/dev/null 2>&1 || error 3 'requires jq command'
echo "jq found"

echo "Setting up cache directory..."
cacheDir=$(MakeCacheDir sf6stats/ranking) || error 5 "can not use cache directory: $cacheDir"
echo "Cache directory: $cacheDir"

if [[ $mode = rm-cache ]]; then rm "$cacheDir"/*.json; exit; fi

# Force yyyymm to be set from arguments if provided
if [[ -n $yyyymm ]]; then
  echo "Using provided date: $yyyymm"
else
  echo "Getting default date..."
  yyyymm=$(getYyyymm)
  echo "Using default date: $yyyymm"
fi

json=$cacheDir/$yyyymm.json
echo "JSON file: $json"

# Check if we have cached data first
if [[ -f $json ]]; then
  echo "Using cached data from $json"
else
  echo "No cached data found, attempting download"
  downloadJson
fi

echo "Validating JSON..."
validateJson
if [[ $mode = validate ]]; then exit; fi
#
if [[ $mode = interactive ]]; then
  selectRank
elif [[ $character ]]; then
  makeRanking; charaExists || error 50 "--character: no such character: $character"
  makeEasyRanking; echo
else
  makeRanking; showRanking
fi
