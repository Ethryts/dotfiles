#!/usr/bin/env bash
set -euo pipefail

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH:-}"

QUERY="${1:-}"
LIMIT="${2:-24}"

SSH_CONFIG_FILE="${HOME}/.ssh/config"
CACHE_DIR="${XDG_CACHE_HOME:-${HOME}/.cache}/quickshell"
CACHE_FILE="${CACHE_DIR}/ssh-launcher.tsv"

cache_needs_refresh() {
  [[ ! -e "${CACHE_FILE}" ]] && return 0
  [[ ! -e "${SSH_CONFIG_FILE}" ]] && return 0
  [[ "${SSH_CONFIG_FILE}" -nt "${CACHE_FILE}" ]] && return 0
  return 1
}

refresh_cache() {
  mkdir -p "${CACHE_DIR}"

  local tmp_file="${CACHE_FILE}.tmp.$$"

  if [[ ! -r "${SSH_CONFIG_FILE}" ]]; then
    : > "${tmp_file}"
    mv "${tmp_file}" "${CACHE_FILE}"
    return
  fi

  awk '
    function trim(value) {
      sub(/^[[:space:]]+/, "", value)
      sub(/[[:space:]]+$/, "", value)
      return value
    }

    function sanitize(value) {
      gsub(/\t/, " ", value)
      gsub(/\r/, " ", value)
      gsub(/\n/, " ", value)
      return value
    }

    function is_explicit_host(alias) {
      return alias != "" && alias !~ /[*?!\[]/
    }

    function flush_hosts(    i, alias, clean_hostname, search_blob) {
      clean_hostname = sanitize(hostname)

      for (i = 1; i <= host_count; ++i) {
        alias = sanitize(hosts[i])
        if (!is_explicit_host(alias)) {
          continue
        }

        search_blob = alias
        if (clean_hostname != "") {
          search_blob = search_blob " " clean_hostname
        }
        search_blob = search_blob " ssh"

        printf "%s\t%s\t%s\t%s\n", alias, alias, clean_hostname, sanitize(search_blob)
      }

      delete hosts
      host_count = 0
      hostname = ""
    }

    {
      line = $0
      sub(/[[:space:]]*#.*/, "", line)
      if (line ~ /^[[:space:]]*$/) {
        next
      }

      if (!match(line, /^[[:space:]]*([[:alnum:]]+)[[:space:]]+(.*)$/, parts)) {
        next
      }

      key = tolower(parts[1])
      value = trim(parts[2])

      if (key == "host") {
        flush_hosts()

        alias_count = split(value, aliases, /[[:space:]]+/)
        for (i = 1; i <= alias_count; ++i) {
          if (aliases[i] == "") {
            continue
          }

          ++host_count
          hosts[host_count] = aliases[i]
        }
      } else if (key == "hostname" && host_count > 0 && hostname == "") {
        hostname = value
      }
    }

    END {
      flush_hosts()
    }
  ' "${SSH_CONFIG_FILE}" \
    | sort -f -t $'\t' -k2,2 \
    | awk -F $'\t' '!seen[tolower($1)]++' > "${tmp_file}"

  mv "${tmp_file}" "${CACHE_FILE}"
}

if cache_needs_refresh; then
  refresh_cache
fi

if [[ ! -s "${CACHE_FILE}" ]]; then
  exit 0
fi

if [[ -n "${QUERY}" ]]; then
  printf '%s\n' "$(<"${CACHE_FILE}")" \
    | fzf --filter "${QUERY}" \
    | head -n "${LIMIT}" \
    | cut -f1-3 \
    || true
else
  head -n "${LIMIT}" "${CACHE_FILE}" | cut -f1-3
fi
