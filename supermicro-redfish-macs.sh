#!/usr/bin/env bash

set -euo pipefail

usage() {
  printf 'Usage: %s BMC_HOST [USERNAME]\n' "${0##*/}" >&2
  printf 'Reads the password interactively. Requires curl and jq.\n' >&2
}

if (( $# < 1 || $# > 2 )); then
  usage
  exit 2
fi

bmc_host=${1#https://}
bmc_host=${bmc_host#http://}
bmc_host=${bmc_host%/}
username=${2:-${REDFISH_USERNAME:-}}
if [[ -z $username ]]; then
  read -r -p 'Redfish username: ' username
fi
read -r -s -p 'Redfish password: ' password
printf '\n' >&2

for command_name in curl jq; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    printf 'Error: required command not found: %s\n' "$command_name" >&2
    exit 1
  fi
done

# Keep credentials out of curl's command-line arguments. The temporary config
# is private and removed on exit.
umask 077
auth_config=$(mktemp)
trap 'rm -f "$auth_config"' EXIT
printf 'user = %s\n' "$(jq -Rn --arg value "$username:$password" '$value')" > "$auth_config"
unset password

base_url="https://${bmc_host}"
curl_args=(--config "$auth_config" --silent --show-error --fail)
get() {
  local path=$1
  curl "${curl_args[@]}" "${base_url}${path}"
}

# Supermicro exposes BMC interfaces under Managers and, on supported systems,
# host interfaces under Systems. Discover collection members rather than
# assuming interface IDs.
declare -A seen=()
printf 'Resource\tMAC address\n'

for root_collection in /redfish/v1/Managers /redfish/v1/Systems; do
  collection_json=$(get "$root_collection") || {
    printf 'Warning: could not read %s\n' "$root_collection" >&2
    continue
  }

  while IFS= read -r parent_path; do
    [[ -n $parent_path ]] || continue
    interfaces_path="${parent_path%/}/EthernetInterfaces"
    interfaces_json=$(get "$interfaces_path") || continue

    while IFS= read -r interface_path; do
      [[ -n $interface_path ]] || continue
      [[ ${seen[$interface_path]+yes} ]] && continue
      seen[$interface_path]=1

      interface_json=$(get "$interface_path") || continue
      jq -r --arg path "$interface_path" '
        [(.MACAddress // empty), (.PermanentMACAddress // empty)]
        | unique[]
        | [$path, .]
        | @tsv
      ' <<< "$interface_json"
    done < <(jq -r '.Members[]? | ."@odata.id" // empty' <<< "$interfaces_json")
  done < <(jq -r '.Members[]? | ."@odata.id" // empty' <<< "$collection_json")
done
