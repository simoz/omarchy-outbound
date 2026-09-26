#!/usr/bin/env bash
set -euo pipefail

plugin_id=io.github.simoz.outbound
repository_url=https://github.com/simoz/omarchy-outbound.git
data_dir="${XDG_DATA_HOME:-$HOME/.local/share}/outbound"
keep_data=0
assume_yes=0
for argument in "$@"; do
  case "$argument" in
    --keep-data) keep_data=1 ;;
    --yes) assume_yes=1 ;;
    --help)
      printf '%s\n' 'Usage: ./reinstall.sh [--keep-data] [--yes]' \
        'Remove Outbound, its settings and (unless --keep-data) the installed collector' \
        'and GeoIP database, then add it again from GitHub and restart the Omarchy shell.'
      exit 0 ;;
    *) printf '%s\n' 'Unexpected argument. Use --help.' >&2; exit 2 ;;
  esac
done

if (( ! assume_yes )); then
  printf 'Reinstall %s from %s' "$plugin_id" "$repository_url"
  (( keep_data )) || printf ' and delete %s' "$data_dir"
  read -r -p '? [y/N] ' answer
  [[ $answer == [yY] ]] || exit 1
fi

# Removing the plugin disables it, which also drops its bar entry and settings.
if [[ -e ${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/plugins/$plugin_id ]]; then
  omarchy plugin remove "$plugin_id" --yes
fi
(( keep_data )) || rm -rf -- "$data_dir"
omarchy plugin add "$repository_url" --enable --yes
# A full restart, because the shell's plugin reload can keep the old QML in memory.
omarchy restart shell
printf '%s\n' 'Outbound reinstalled.'
(( keep_data )) || printf '%s\n' 'Open it and click Install collector, then Install GeoIP.'
