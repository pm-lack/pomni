#!/bin/sh
set -e

progsfile="https://raw.githubusercontent.com/pm-lack/pomni/refs/heads/main/progs.csv"

fetch_browsers() {
	browsers=()
	curl -Ls "$progsfile" | sed '/^#/d;/^$/d' | while IFS=, read -r tag program comment; do
		[ -z "$program" ] && continue
		# Only include browsers
		if [ "$tag" = "A" ] || [ -z "$tag" ]; then
			# Shorten description to ~40 chars
			desc=$(echo "$comment" | sed 's/"/\\"/g' | cut -c1-40)
			browsers+=("$program" "$desc" "OFF")
		fi
	done
	echo "${browsers[@]}"
}

# Build array for whiptail
options_array=()
while IFS= read -r line; do
	options_array+=("$line")
done < <(fetch_browsers)

# Run whiptail
chosen=$(whiptail --title "Choose Browsers to Install" \
	--checklist "Select the browsers you want to install:" 20 78 12 \
	"${options_array[@]}" 3>&1 1>&2 2>&3) || exit 1

# Remove quotes
chosen=$(echo "$chosen" | tr -d '"')

echo "You selected: $chosen"
