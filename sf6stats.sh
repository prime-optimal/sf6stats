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

unset mode debug cacheDir yyyymm json  chara rank ranking easyRanking
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
  -c, --chara Type-Chara (e.g. 'C-guile')
      Specify control type 'C' or 'M', followed by '-' and name (lower case).
      Use --rank without --chara to list all characters.
  -i, --interactive
      Select rank and chara interactively (Ignore --chara and --rank).
  -r, --rank rookie|iron|bronze|silver|gold|platinum|diamond|master
      Default: master
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
while [[ $# -gt 0 ]]; do
  case "$1" in
    -c|--chara)
      [[ $# = 1 || $2 =~ ^- ]] && error 1 "$1: requires an argument"
      [[ $2 =~ ^(C|M)-[a-z]+$ ]] || error 1 "$1: incorrect format: $2"
      chara=$2
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
  local masterHeader=$(jq ".diaData.ci.d_sort.\"8\".opponent_header" "$json")
  local length=$(jq "length" <<<$masterHeader)
  [[ $length =~ ^[1-9][0-9]*$ ]] || error 20 "can not parse JSON: $json"
  echo "opponent_header.length: $length"
  local every="map(has(\"input_type\"), has(\"tool_name\"), has(\"_dsort\")) | all"
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
  local opponent_header=".diaData.ci.d_sort.\"$rank_idx\".opponent_header[]"
  local data='.input_type + "-" + .tool_name + " " + (if (._dsort | type) == "number" then (._dsort*100 | tostring) else "null" end)'
  echo "Running jq query: $opponent_header | $data"
  local lines; lines=$(jq -r "$opponent_header | $data" "$json") ||
    error 25 "can not parse JSON: $json"
  echo "Jq query completed, processing lines"
  unset ranking
  while IFS= read -r line; do # e.g. C-terry 54.51220338217697
    if [[ $line =~ null$ ]]; then
      ranking[${#ranking[@]}]=$(printf '%-10s --' "${line%null}") # e.g. --yyyymm 202408
    else
      local chara=${line% *}
      local value=${line##* }
      ranking[${#ranking[@]}]=$(printf '%-10s %.2f%%' "$chara" "$value")
    fi
  done <<<"$lines"
  echo "Processed ${#ranking[@]} ranking entries"
}
showRanking() {
  echo "In showRanking"
  local i=1
  local cols=3  # Number of columns to display
  local total=${#ranking[@]}
  local rows=$(( (total + cols - 1) / cols ))  # Ceiling division
  
  # Print header
  print_color "$BOLD$CYAN" "[$rank] win rate ranking: ${yyyymm:0:4}-${yyyymm:4}"
  print_color "$BOLD" "Select: chara"
  echo
  
  # Print rankings in columns
  for ((row=0; row<rows; row++)); do
    for ((col=0; col<cols; col++)); do
      local idx=$((row + col*rows))
      if (( idx < total )); then
        local entry="${ranking[idx]}"
        local char=${entry%% *}
        local value=${entry#* }
        
        printf '%2d) ' $((idx+1))
        print_color "$BOLD" "$char"  # Removed WHITE color
        printf ' '
        
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
            printf '%s' "$value"  # Use default terminal color
          elif awk -v val="$value" 'BEGIN { exit !(val >= 4.5) }'; then
            print_color "$LIGHT_RED" "$value"
          else
            print_color "$RED" "$value"
          fi
        fi
        printf '  '
      fi
    done
    echo
  done
  print_color "$BOLD$YELLOW" "q) Quit"
  echo
}
makeEasyRanking() {
  local records=".diaData.ci.d_sort.\"$(rankIndex)\".records[]"
  local select="select(.tool_name==\"${chara:2}\" and .input_type==\"${chara:0:1}\") | .values"
  local val; val=$(jq "$records | $select" "$json") || error 26 "can not parse JSON: $json"
  [[ $(jq 'length' <<<$val) = ${#ranking[@]} ]] || error 27 "invalid JSON: $json"
  
  # Process the values and create arrays for sorting and display
  local sort_keys=()
  local display_values=()
  local i=1
  while IFS= read -r line; do
    # Remove quotes and handle special cases
    line=${line//\"/}
    local char=${ranking[i-1]%% *}
    if [[ $line == "-" || $line == "-.---" ]]; then
      sort_keys+=("-1")  # Place self-matches at the end
      display_values+=("$(printf '%-10s --' "$char")")
    else
      # Format the value with three decimal places
      if [[ $line == "10.000" ]]; then
        sort_keys+=("10.000")
        display_values+=("$(printf '%-10s 10.000' "$char")")
      else
        # Keep the raw value with three decimal places
        sort_keys+=("$line")
        display_values+=("$(printf '%-10s %6.3f' "$char" "$line")")
      fi
    fi
    ((i++))
  done < <(jq ".[].val" <<<"$val")

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

  # Display in 3 columns
  local cols=3
  local total=${#sorted_display[@]}
  local rows=$(( (total + cols - 1) / cols ))  # Ceiling division
  
  print_color "$BOLD$CYAN" "[$rank] $chara's win rate (1st column):"
  echo
  
  for ((row=0; row<rows; row++)); do
    for ((col=0; col<cols; col++)); do
      local idx=$((row + col*rows))
      if (( idx < total )); then
        local entry="${sorted_display[idx]}"
        local char=${entry%% *}
        local value=${entry#* }
        
        printf '%2d) ' $((idx+1))
        print_color "$BOLD" "$char"  # Removed WHITE color
        printf ' '
        
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
            printf '%s' "$value"  # Use default terminal color
          elif awk -v val="$value" 'BEGIN { exit !(val >= 4.5) }'; then
            print_color "$LIGHT_RED" "$value"
          else
            print_color "$RED" "$value"
          fi
        fi
        printf '  '
      fi
    done
    echo
  done
}
charaExists() { for e in "${ranking[@]%% *}"; do [[ $e =~ $chara ]] && return 0; done; return 1; }

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
  selectChara
}
selectChara() {
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
          chara=${ranking[choice-1]%% *}
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
  select e in 'Select: chara' 'Select: rank' 'Quit'; do
    if [[ $e == "Quit" ]]; then
      exit 0
    elif [[ $e == 'Select: rank' ]]; then
      selectRank
    else
      selectChara
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
elif [[ $chara ]]; then
  makeRanking; charaExists || error 50 "--chara: no such chara: $chara"
  makeEasyRanking; echo
else
  makeRanking; showRanking
fi
