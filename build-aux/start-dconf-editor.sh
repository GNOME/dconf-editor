#!/usr/bin/bash

IFS=: read -ra host_data_dirs < <(flatpak-spawn --host sh -c 'echo $XDG_DATA_DIRS')

# To avoid potentially muddying up $XDG_DATA_DIRS too much, we link the schema paths
# into a temporary directory.
bridge_dir=$XDG_RUNTIME_DIR/dconf-bridge
mkdir -p "$bridge_dir"

for dir in "${host_data_dirs[@]}"; do
  if [[ "$dir" == /usr/* ]]; then
    dir=/run/host/"$dir"
  fi

  schemas="$dir/glib-2.0/schemas"
  if [[ -d "$schemas" ]]; then
    bridged=$(mktemp -d XXXXXXXXXX -p "$bridge_dir")
    mkdir -p "$bridged"/glib-2.0
    ln -s "$schemas" "$bridged"/glib-2.0
    XDG_DATA_DIRS=$XDG_DATA_DIRS:"$bridged"
  fi
done

export XDG_DATA_DIRS
exec dconf-editor "$@"
