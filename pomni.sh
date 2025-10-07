#!/bin/sh

# pm’s Optimized Minimal Nest Installer  (pomni)
# by pm-lackthereof.xyz
# License: GNU GPLv3

# Load program list from CSV
progsfile="https://raw.githubusercontent.com/pm-lack/pomni/refs/heads/main/progs.csv"

# Ensure the file is available
([ -f "$progsfile" ] && cp "$progsfile" /tmp/progs.csv) ||
	curl -Ls "$progsfile" | sed '/^#/d' >/tmp/progs.csv

# Prepare dynamic arrays for browser entries
browser_entries=()

# Read the CSV and extract programs tagged with "B"
while IFS=, read -r tag program comment; do
	# Skip empty or malformed lines
	[[ -z "$tag" || -z "$program" ]] && continue

	# Clean up stray quotes and whitespace
	tag="${tag//\"/}"
	program="$(echo "$program" | tr -d '\r' | tr -d '"')"

	if [[ "$tag" == "B" ]]; then
		browser_entries+=("$program" "$program")
	fi
done </tmp/progs.csv

# Now feed the collected browser programs to the whiptail checklist
if ((${#browser_entries[@]})); then
	install "Web Browsers" \
		"Select one or more web browsers to install.\nAll programs marked with '*' are already installed.\nUnselecting them will NOT uninstall them." \
		"${browser_entries[@]}"
else
	echo "No browsers found in CSV (no entries tagged 'B')."
fi
