#!/bin/sh
# Budget a FAT image for its payload, metadata, and free space.
fat_image_payload_bytes() {
  fat_payload_bytes=0
  for fat_payload_file in "$@"; do
    [ -f "${fat_payload_file}" ] || {
      printf 'fat image: missing payload: %s\n' "${fat_payload_file}" >&2
      return 1
    }
    fat_file_bytes="$(wc -c < "${fat_payload_file}")"
    [ "${fat_file_bytes}" -le 4294967295 ] || {
      printf 'fat image: payload exceeds FAT file limit: %s\n' "${fat_payload_file}" >&2
      return 1
    }
    fat_payload_bytes=$((fat_payload_bytes + fat_file_bytes))
  done
  printf '%s\n' "${fat_payload_bytes}"
}

fat_image_size_mb() {
  case "${1:-}" in
    ''|*[!0-9]*) printf 'fat image: invalid payload size\n' >&2; return 1 ;;
  esac
  # Leave 5% plus 16 MiB for FAT metadata, directories, and free space.
  fat_budget_bytes=$(($1 + $1 / 20 + 16 * 1024 * 1024))
  fat_budget_mb=$(((fat_budget_bytes + 1024 * 1024 - 1) / (1024 * 1024)))
  [ "${fat_budget_mb}" -ge 64 ] || fat_budget_mb=64
  printf '%s\n' "${fat_budget_mb}"
}
