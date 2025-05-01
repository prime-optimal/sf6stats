#!/bin/bash

if [[ ${debug:-} == on ]]; then
  PS4='+ ${BASH_SOURCE##*/}:${LINENO}:${FUNCNAME[0]}: '
  set -x
fi

set -eo pipefail
IFS=$'\n\t'

dir="${XDG_CACHE_HOME:-$HOME/.cache}/"
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

[[ $debug ]] && {
  echo "Script starting..."
}

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

[[ $debug ]] && {
  echo "Processing arguments..."
}

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

[[ $debug ]] && {
  echo "Arguments processed"
  echo "Current yyyymm value: $yyyymm"
}


MakeCacheDir() {
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

log() { if [[ $debug ]]; then echo -e "${YELLOW}DEBUG:${RESET} $*" 1>&2; fi; } # Print to stderr, add prefix

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
  # pick the correct path for your opponent_header
  local path
  if [[ -n $input_type ]]; then
    path='.diaData.ci.d_sort["8"].opponent_header'
  else
    path='.diaData.c.d_sort["8"].opponent_header'
  fi

  # ensure it's a non-empty array and every element has tool_name & _dsort
  if ! jq -e "$path
                | type == \"array\" and length > 0
                and all(.tool_name and ._dsort $( [[ -n $input_type ]] && echo 'and .input_type'))" \
            "$json" &>/dev/null
  then
    error 20 "JSON schema validation failed at $path in $json"
  fi
}

rankIndex() {  
  [[ $debug ]] && {
    echo "In rankIndex for rank: $rank" >&2
  }

  for i in "${!rankList[@]}"; do
    if [[ ${rankList[$i]} = $rank ]]; then 
      [[ $debug ]] && {
        echo "Found rank index: $((i+1))" >&2
      }
      printf '%d' $((i+1))
      return 0
    fi
  done
  return 1
}
makeRanking() {
  [[ $debug ]] && {
    echo ">>>> ENTER makeRanking()"
  }

  local rank_idx
  rank_idx=$(rankIndex) || error 1 "Invalid rank: $rank"

  [[ $debug ]] && {
    echo "Using rank index: $rank_idx"
  }

  # Choose between consolidated (c) or input-specific (ci) data
  local data_path=".diaData"
  if [[ -n $input_type ]]; then
    data_path="$data_path.ci.d_sort.\"$rank_idx\".opponent_header[]"
    local data='.input_type + " " + .tool_name + " " + (if (._dsort | type) == "number" then (._dsort*10 | tostring) else "null" end)'
  else
    data_path="$data_path.c.d_sort.\"$rank_idx\".opponent_header[]"
    local data='.tool_name + " " + (if (._dsort | type) == "number" then (._dsort*10 | tostring) else "null" end)'
  fi

  [[ $debug ]] && {
    echo "Running jq query: $data_path | $data"
  }
  local lines; lines=$(jq -r "$data_path | $data" "$json") ||
    error 25 "can not parse JSON: $json"
  
  [[ $debug ]] && {
    echo "Jq query completed, processing lines"
  }

  unset ranking       # Clear previous ranking
  ranking=()        # Initialize as empty array explicitly

  [[ $debug ]] && {
    echo "Processing jq lines for ranking array..." # Added echo
  }

  local count=0
  while IFS= read -r line; do
    ((count++))
    local type=""
    local char=""
    local value_str=""
    local formatted_entry="" # Define outside the if blocks

    # Extract data based on whether input_type was set
    if [[ -n $input_type ]]; then
      # input-type branch (C/M)
      type=${line%% *}
      rest=${line#* }
      char=${rest%% *}
      value_str=${rest##* }
    else
      # consolidated branch (no C/M)
      type="N/A"
      char=${line%% *}
      value_str=${line##* }
    fi


    # Trim the extracted character name
    char=$(echo "$char" | awk '{$1=$1; print $1}')

    # --- Simplified Logic ---
    if [[ "$value_str" == "--" || "$value_str" == "null" ]]; then
        # Handle non-numeric cases ("--" or "null" from jq)
        if [[ "$type" == "N/A" ]]; then
            formatted_entry="$(printf '%-10s --' "$char")"
        else
            formatted_entry="$(printf '%-10s -- %-2s' "$char" "$type")"
        fi
        # ADD TO ARRAY HERE
        ranking+=("$formatted_entry")
    else
        # Handle numeric cases (value_str should be like "51.490")
        # Ensure it has exactly 3 decimal places using printf formatting
        local value_formatted=$(printf '%.3f' "$value_str") # Format like 5.149

        if [[ "$type" == "N/A" ]]; then
            formatted_entry="$(printf '%-10s %6s' "$char" "$value_formatted")"
        else
            formatted_entry="$(printf '%-10s %6s %-2s' "$char" "$value_formatted" "$type")"
        fi
        # ADD TO ARRAY HERE
        ranking+=("$formatted_entry")
    fi
    # log "Added to ranking: [$formatted_entry]" # Optional: uncomment for detailed debug

  done <<<"$lines"

  [[ $debug ]] && {
    echo "Processed $count lines, created ${#ranking[@]} ranking entries." # Modified echo
  }
  # Check if ranking is empty (can stay)
  if [[ ${#ranking[@]} -eq 0 && $count -gt 0 ]]; then
      echo "Warning: Processed $count lines but generated 0 ranking entries. Check parsing logic." >&2
  elif [[ ${#ranking[@]} -eq 0 ]]; then
      echo "Warning: No ranking entries were generated (jq might have returned nothing)." >&2
  fi

}



# after makeRanking, before showRanking
# displayColumns <array-name> <cols>

displayColumns() {
  local arrName=$1 cols=$2 total rows idx val
  # get length of ${arrName}[@]
  eval "total=\${#${arrName}[@]}"
  rows=$(( (total + cols - 1) / cols ))
  for ((r=0; r<rows; r++)); do
    for ((c=0; c<cols; c++)); do
      idx=$(( r + c*rows ))
      if (( idx < total )); then
        eval "val=\${${arrName}[${idx}]}"
        printf '%2d) %s    ' $((idx+1)) "$val"
      fi
    done
    echo
  done
}


showRanking() {
  [[ $debug ]] && {
    echo ">>>> ENTER showRanking() cols(from input_type)='$input_type'"
  }

  [[ $debug ]] && { 
    echo "DEBUG: ranking length = ${#ranking[@]}"
    }

  [[ $debug ]] && {
    printf "DEBUG: ranking: %s\n" "${ranking[*]}"
  }
  # decide column-count purely from the real --type flag
  local cols=3
  [[ -n $input_type ]] && cols=4

  # optionally see what you're about to print
  [[ $debug ]] && printf "DEBUG: showRanking: cols=%d, entries=%d\n" \
                      "$cols" "${#ranking[@]}"

  # fail early if empty
  if (( ${#ranking[@]} == 0 )); then
    echo "Warning: ranking array is empty in showRanking()" >&2
    return 1
  fi

  # header
  print_color "$BOLD$CYAN" "[$rank] win rate ranking: ${yyyymm:0:4}-${yyyymm:4}"
  echo

  # use your displayColumns helper
  displayColumns ranking "$cols"
  echo
#  echo ">>>> EXIT showRanking()"

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
  [[ $debug ]] && {
    echo "Running jq query: $data_path | $select"
  }
  
  local val; val=$(jq "$data_path | $select" "$json") || error 26 "can not parse JSON: $json"
  [[ $(jq 'length' <<<$val) = ${#ranking[@]} ]] || error 27 "invalid JSON: $json"
  
  # Process the values and create arrays for sorting and display
  local sort_keys=()
  local display_values=()
  local i=1
  
  if [[ -n $input_type ]]; then
    # Create a query that properly cross-references values with opponent headers
    if [[ $debug ]]; then
      # Print more details about the JSON structure for debugging
      echo "DEBUG: Records structure:"
      jq -c '.diaData.ci.d_sort."'$(rankIndex)'".records[] | select(.tool_name=="'$char_name'" and .input_type=="'$char_type'") | {tool_name, input_type}' "$json" | head -1
      echo "DEBUG: Values structure:"
      jq -c '.diaData.ci.d_sort."'$(rankIndex)'".records[] | select(.tool_name=="'$char_name'" and .input_type=="'$char_type'") | .values[0]' "$json"
      
      # Print opponent header structure to understand the array
      echo "DEBUG: Opponent header array structure:"
      jq -c '.diaData.ci.d_sort."'$(rankIndex)'".opponent_header | to_entries | .[0:3] | .[] | {index: .key, id: .value.id, tool_name: .value.tool_name, input_type: .value.input_type}' "$json"
    fi
    
    local combined_query='
      # First store values and headers in variables
      .diaData.ci.d_sort."'$(rankIndex)'".opponent_header as $headers |
      .diaData.ci.d_sort."'$(rankIndex)'".records[] | 
      select(.tool_name=="'$char_name'" and .input_type=="'$char_type'") |
      .values as $values |
      # Convert headers to entries with index
      $headers | to_entries | .[] |
      # Create objects with the header data and corresponding value
      {
        # Get value from the values array at the matching position
        val: ($values[.key].val // "-"),
        oid: ($values[.key]._oid // 0),
        # Get name and type from the header
        name: .value.tool_name,
        type: .value.input_type,
        # Include index for debugging
        index: .key
      }'
    
    # Execute the combined query to get detailed opponent information
    local combined_val
    combined_val=$(jq "$combined_query" "$json") || error 26 "can not parse JSON: $json"
    
    if [[ $debug ]]; then
      # More comprehensive debugging to understand data structure
      echo "DEBUG: Opponent headers count:"
      jq '.diaData.ci.d_sort."'$(rankIndex)'".opponent_header | length' "$json"
      
      echo "DEBUG: Values array count:"
      jq '.diaData.ci.d_sort."'$(rankIndex)'".records[] | select(.tool_name=="'$char_name'" and .input_type=="'$char_type'") | .values | length' "$json"
      
      # Debug the combined query result
      echo "DEBUG: Combined query result (first few entries):"
      jq -c '.[0:5]' <<<"$combined_val"
      
      # Count total results
      echo "DEBUG: Total combined results:" 
      jq 'length' <<<"$combined_val"
    fi
    
    # Process the values with opponent information
    while IFS= read -r json_line; do
      # Extract values from the JSON
      local val=$(jq -r '.val // "-"' <<<"$json_line")
      local oid=$(jq -r '.oid' <<<"$json_line")
      local name=$(jq -r '.name // "unknown"' <<<"$json_line")
      local type=$(jq -r '.type // "-"' <<<"$json_line")
      
      if [[ $debug ]]; then
        echo "DEBUG: Processing line: $json_line"
        echo "DEBUG: Extracted: val=$val, oid=$oid, name=$name, type=$type"
      fi
      
      # Handle special cases
      if [[ $val == "-" || $val == "-.---" || $val == "null" ]]; then
        sort_keys+=("-1")  # Place self-matches at the end
        display_values+=("$(printf '%-10s -- %-2s' "$name" "$type")")
      else
        # Format the value with three decimal places
        if [[ $val == "10.000" ]]; then
          sort_keys+=("10.000")
          display_values+=("$(printf '%-10s 10.000 %-2s' "$name" "$type")")
        else
          # Keep the raw value with three decimal places
          sort_keys+=("$val")
          display_values+=("$(printf '%-10s %6.3f %-2s' "$name" "$val" "$type")")
        fi
      fi
      ((i++))
    done < <(jq -c '.[]' <<<"$combined_val" 2>/dev/null || echo '{}')
  else
    # Process the original values without opponent information
    while IFS= read -r line; do
      # Remove quotes and handle special cases
      line=${line//\"/}
      local char=${ranking[i-1]%% *}
      
      # echo "DEBUG: Processing line: $line for char: $char"
      
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
  fi
  
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
  # … after building sorted_display array …
  local cols=3
  [[ -n $input_type ]] && cols=4
  print_color "$BOLD$CYAN" "[$rank] $character's win rate (1st column):"
  echo
  displayColumns sorted_display "$cols"



  
  
  for ((row=0; row<rows; row++)); do
    for ((col=0; col<cols; col++)); do
      local idx=$((row + col*rows))
      if (( idx < total )); then
        local entry="${sorted_display[idx]}"
        # Debug output removed
        local char=${entry%% *}
        local rest=${entry#* }
        
        printf '%2d) ' $((idx+1))
        print_color "$BOLD" "$char"  # Removed WHITE color
        printf ' '
        
        if [[ -n $input_type ]]; then
          # Just print the rest of the entry (already formatted)
          printf '%s' "$rest"
        else
          # Just print the rest of the entry (already formatted)
          printf '%s' "$rest"
        fi
        printf '    '
      fi
    done
    echo
  done
}
# ----------------------------------------------------------------------------
# charaExists: return 0 if $character matches any entry in ${ranking[@]}
# ----------------------------------------------------------------------------
charaExists() {
  # Lowercase the user‐supplied argument
  local want=$(printf '%s' "$character" | tr '[:upper:]' '[:lower:]')

  # Walk the formatted ranking array
  for entry in "${ranking[@]}"; do
    # pull off the very first “word” (the character name, padded or not)
    local have="${entry%% *}"
    # down-case it
    local lh=$(printf '%s' "$have" | tr '[:upper:]' '[:lower:]')
    # debug trace
    [[ $debug ]] && printf 'DEBUG: comparing user "%s" vs entry "%s"\n' "$want" "$lh"
    if [[ $lh == "$want" ]]; then
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

[[ $debug ]] && {
  echo "Checking for jq..."
}
type jq >/dev/null 2>&1 || error 3 'requires jq command'

# Cache Setup
[[ $debug ]] && {
  echo "Setting up cache directory..."
}

cacheDir=$(MakeCacheDir sf6stats/ranking) || error 5 "can not use cache directory: $cacheDir"

[[ $debug ]] && {
  echo "Cache directory: $cacheDir"
}

if [[ $mode = rm-cache ]]; then rm "$cacheDir"/*.json; exit; fi

# Force yyyymm to be set from arguments if provided
if [[ -n $yyyymm ]]; then
  echo "Using provided date: $yyyymm"
else
  [[ $debug ]] && {
    echo "Getting default date..."
  }
  yyyymm=$(getYyyymm)
  [[ $debug ]] && {
    echo "Using default date: $yyyymm"
  }
fi

json=$cacheDir/$yyyymm.json
  [[ $debug ]] && {
    echo "JSON file: $json"
  }

# Check if we have cached data first
if [[ -f $json ]]; then
  [[ $debug ]] && {
    echo "Using cached data from $json"
  }
else
  echo "No cached data found, attempting download"
  downloadJson
fi

  [[ $debug ]] && {
    echo "Validating JSON..."
  }
validateJson

if [[ $mode = validate ]]; then exit; fi
    [[ $debug ]] && {
      echo ">>>> At dispatch: mode='$mode' character='$character' interactive?='${mode=='interactive'}'"
    }

if [[ $mode = interactive ]]; then
  [[ $debug ]] && {
    echo ">>>> At dispatch: mode='$mode' character='$character' interactive?='${mode=='interactive'}'"
  }
  selectRank
elif [[ $character ]]; then
  makeRanking; charaExists || error 50 "--character: no such character: $character"
  makeEasyRanking; echo
else
  makeRanking; showRanking
fi
