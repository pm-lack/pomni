#!/bin/sh

# pm’s Optimized Minimal Nest Installer  (pomni)
# by pm-lackthereof.xyz
# License: GNU GPLv3

aurhelper="yay"
# Load program list from CSV
progsfile="https://raw.githubusercontent.com/pm-lack/pomni/refs/heads/main/progs.csv"

# Sanitize potential stray CRLF and quotes in program names
program="$(echo "$program" | tr -d '\r' | tr -d '"')"

export NEWT_COLORS="
root=,blue
window=,black
shadow=,blue
border=blue,black
title=blue,black
textbox=blue,black
radiolist=black,black
label=black,blue
checkbox=black,blue
compactbutton=black,blue
button=black,red"

max() {
	echo -e "$1\n$2" | sort -n | tail -1
}
getbiggestword() {
	echo "$@" | sed "s/ /\n/g" | wc -L
}
replicate() {
	local n="$1"
	local x="$2"
	local str

	for _ in $(seq 1 "$n"); do
		str="$str$x"
	done
	echo "$str"
}

programchoices() {
	choices=()
	local maxlen
	maxlen="$(getbiggestword "${!checkboxes[@]}")"
	linesize="$(max "$maxlen" 42)"
	local spacer
	spacer="$(replicate "$((linesize - maxlen))" " ")"

	for key in "${!checkboxes[@]}"; do
		# A portable way to check if a command exists in $PATH and is executable.
		# If it doesn't exist, we set the tick box to OFF.
		# If it exists, then we set the tick box to ON.
		if ! command -v "${checkboxes[$key]}" >/dev/null; then
			# $spacer length is defined in the individual window functions based
			# on the needed length to make the checkbox wide enough to fit window.
			choices+=("${key}" "${spacer}" "OFF")
		else
			choices+=("${key}" "${spacer}" "ON")
		fi
	done
}

# Shows a whiptail checklist window and captures selected items
selectedprograms() {
	result=$(
		# Creates the whiptail checklist. Also, we use a nifty
		# trick to swap stdout and stderr.
		whiptail --title "$title" \
			--checklist "$text" 22 "$((linesize + 16))" 12 \
			"${choices[@]}" \
			3>&2 2>&1 1>&3
	)
}

exitorinstall() {
	local exitstatus="$?"
	# Check the exit status, if 0 we will install the selected
	# packages. A command which exits with zero (0) has succeeded.
	# A non-zero (1-255) exit status indicates failure.
	if [ "$exitstatus" = 0 ]; then
		# Take the results and remove the "'s and add new lines.
		# Otherwise, pacman is not going to like how we feed it.
		programs=$(echo "$result" | sed 's/" /\n/g' | sed 's/"//g')
		echo "$programs"
		$aurhelper --noconfirm -S "$programs" ||
			echo "Failed to install required packages."
	else
		echo "User selected Cancel."
	fi
}

install() {
	local title="${1}"
	local text="${2}"
	declare -A checkboxes

	# Loop through all the remaining arguments passed to the install function
	for ((i = 3; i <= $#; i += 2)); do
		key="${!i}"
		value=""
		eval "value=\${$((i + 1))}"
		if [ -z "$value" ]; then
			value="$key"
		fi
		checkboxes["$key"]="$value"
	done

	programchoices && selectedprograms && exitorinstall
}

# Fetch CSV (either from file or URL)
([ -f "$progsfile" ] && cp "$progsfile" /tmp/progs.csv) ||
	curl -Ls "$progsfile" | sed '/^#/d' >/tmp/progs.csv

# Build a list of browsers from CSV
browsers=()
while IFS=, read -r tag program comment; do
	# Remove surrounding quotes from the comment if present
	comment="$(echo "$comment" | sed -E 's/^"//;s/"$//')"

	# Only include entries tagged as browsers (B)
	if [ "$tag" = "B" ]; then
		# Append to array as key/value pair
		browsers+=("$program" "$program")
	fi
done </tmp/progs.csv

# Call the install function with dynamically loaded browser list
install "Web Browsers" \
	"Select one or more web browsers to install.\nNon-binaries will need time to compile." \
	"${browsers[@]}"
