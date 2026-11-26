#!/bin/bash
# SWAI - Sekigetsu's Workstation Auto Installer
# Run on a fresh Arch Linux installation (on an encrypted disk), from the user you made while installing:
#   sudo sh swai.sh            asks a few questions first, then runs by itself
#   sudo sh swai.sh -y         no questions: installs everything
#   sudo sh swai.sh -u NAME    set up NAME (when there's more than one user)
# It sets up that user (no new username or password needed). With an encrypted disk it also logs it in automatically
# at boot (you've typed the disk's password already); without one, ly asks for your password.

if [ -z "$BASH_VERSION" ] || shopt -qo posix 2>/dev/null; then exec bash "$0" "$@"; fi


# CONFIGURATION

DOTFILES="https://github.com/sekigetsu01/workrice.git"
WALLPAPERS="https://github.com/sekigetsu01/wallpapers.git"   # into ~/wallpapers
PROGSFILE="https://raw.githubusercontent.com/sekigetsu01/SWAI/main/static/progs.csv"
AURHELPER="yay"
BRANCH="main"
SESSION="mango"            # desktop session ly logs into automatically
LOG=/var/log/swai.log      # everything the installs print, to see why something failed
MIN_FREE_GB=20             # free space needed on /
# dotfiles copied only when missing: their scripts change them, so a rerun keeps yours (globs are fine)
KEEP=".config/times.conf .config/systemd/user/*.timer.d/times.conf .config/kp/config .config/kp/generator .config/clicker/config"
infocmp "$TERM" >/dev/null 2>&1 || export TERM=ansi
bar_full=blue bar_empty=black
if [ "$(tput colors 2>/dev/null || echo 8)" -ge 256 ]; then bar_full=color24 bar_empty=color236; fi
export NEWT_COLORS="
root=lightgray,black
roottext=lightgray,black
helpline=lightgray,black
border=cyan,black
window=lightgray,black
shadow=black,black
title=cyan,black
textbox=lightgray,black
acttextbox=black,cyan
label=lightgray,black
button=black,lightgray
actbutton=black,cyan
compactbutton=lightgray,black
entry=black,cyan
disentry=lightgray,black
checkbox=lightgray,black
actcheckbox=black,cyan
listbox=lightgray,black
actlistbox=black,cyan
sellistbox=black,cyan
actsellistbox=black,cyan
emptyscale=lightgray,$bar_empty
fullscale=lightgray,$bar_full
"


# OPTIONS

yes=0 name=""
usage() {
	sed -n '4,6s/^#   //p' "$0" >&2
	exit 1
}
while [ $# -gt 0 ]; do
	case $1 in
		-y|--yes) yes=1 ;;
		-u|--user) name=$2; shift; [ -n "$name" ] || usage ;;
		-h|--help) usage ;;
		*) usage ;;
	esac
	shift
done


# UTILITIES

die() { clear 2>/dev/null; printf "swai: %s\n" "$1" >&2; exit 1; }

BACK="SWAI"
step_line() { BACK="SWAI  ·  step $1 of 3: $2"; }
wt() {
	local a
	for a; do
		case $a in
			--inputbox|--passwordbox) whiptail --backtitle "$BACK" "$@"; return ;;
			--gauge) wt_gauge "$@"; return ;;
		esac
	done
	[ -t 0 ] && command -v script >/dev/null || { whiptail --backtitle "$BACK" "$@"; return; }
	wt_hl "$@"
}

hl_keys() {
	local k
	while :; do
		IFS= read -rn1 -d '' k || continue
		case $k in
			h) printf '\e[D' ;; l) printf '\e[C' ;; $'\n') printf '\r' ;;
			$'\x7f'|$'\b') if (( ${back_ok:-0} )); then : > "$WORK/wt-back"; printf '\r'; else printf '%s' "$k"; fi ;;
			y|Y) if (( wt_yn )); then : > "$WORK/wt-yes"; printf '\r'; else printf '%s' "$k"; fi ;;
			n|N) if (( wt_yn )); then : > "$WORK/wt-no"; printf '\r'; else printf '%s' "$k"; fi ;;
			*) printf '%s' "$k" ;;
		esac
	done
}
wt_hl() {
	local size saved in rc resized out=$WORK/wt-out a wt_yn=0
	for a; do [ "$a" = --yesno ] && wt_yn=1; done   # y and n answer a yes/no question
	saved=$(stty -g)
	rm -f "$WORK/wt-back" "$WORK/wt-yes" "$WORK/wt-no"
	stty -icanon -echo -icrnl min 1
	exec {in}< <(hl_keys)
	wt_kp=$!
	trap 'pkill -P "$wt_sp" 2>/dev/null && resized=1' WINCH
	while :; do
		resized=0
		rm -f "$out"
		size=$(stty size)
		SHELL=/bin/bash script -qefc "stty rows ${size% *} cols ${size#* }; exec whiptail --output-fd 3 $(printf '%q ' --backtitle "$BACK" "$@") 3>$(printf '%q' "$out")" /dev/null <&"$in" &
		wt_sp=$!
		while kill -0 "$wt_sp" 2>/dev/null; do sleep 0.05; done
		wait "$wt_sp"; rc=$?
		(( resized )) || break
	done
	trap - WINCH
	kill "$wt_kp" 2>/dev/null
	wt_kp='' wt_sp=''
	exec {in}<&-
	stty "$saved"
	if [ -e "$WORK/wt-back" ]; then rm -f "$WORK/wt-back" "$out"; return 10; fi
	if [ -e "$WORK/wt-yes" ]; then rc=0; elif [ -e "$WORK/wt-no" ]; then rc=1; fi
	rm -f "$WORK/wt-yes" "$WORK/wt-no"
	[ -s "$out" ] && cat "$out" >&2
	rm -f "$out"
	return "$rc"
}

wt_gauge() {
	local -a a=("$@") blk=()
	local n=$# g gp part buf= line inblk=0 resized=0 t
	trap 'resized=1' WINCH
	exec {g}> >(exec whiptail --backtitle "$BACK" "${a[@]}")
	gp=$!
	while :; do
		if IFS= read -r -t 0.3 part; then
			line=$buf$part buf=
			printf '%s\n' "$line" >&"$g"
			if (( inblk )); then
				if [ "$line" = XXX ]; then
					inblk=0
					printf -v t '%s\\n' "${blk[@]:1}"
					a[n-1]=${blk[0]:-0} a[n-4]=${t%\\n}
				else
					blk+=("$line")
				fi
			elif [ "$line" = XXX ]; then
				inblk=1 blk=()
			else
				a[n-1]=$line
			fi
		elif (( $? > 128 )); then
			buf+=$part
		else
			[ -n "$buf$part" ] && printf '%s\n' "$buf$part" >&"$g"
			break
		fi
		if (( resized && !inblk )); then
			resized=0
			exec {g}>&-
			wait "$gp"
			exec {g}> >(exec whiptail --backtitle "$BACK" "${a[@]}")
			gp=$!
		fi
	done
	exec {g}>&-
	wait "$gp"
	trap - WINCH
}

pac() { pacman --noconfirm --needed "$@" >>"$LOG" 2>&1; }

ly_user() {
	sed -n -E 's/^[[:space:]]*auto_login_user[[:space:]]*=[[:space:]]*([^[:space:]]+).*/\1/p' /etc/ly/config.ini 2>/dev/null | grep -vx null | tail -n 1
}

describe() { awk -F, -v p="$1" '$2 == p { sub(/^[^,]*,[^,]*,/, ""); gsub(/^"|"$/, ""); print; exit }' "$WORK/progs.csv"; }


# CHECKS BEFORE ANYTHING ELSE

preflight() {
	(( EUID == 0 )) || die "run it with sudo: sudo sh swai.sh"
	command -v pacman >/dev/null && [ -f /etc/arch-release ] && [ -d /run/systemd/system ] ||
		die "this is for Arch Linux (no pacman, arch-release or systemd found)."
	curl -fsI --max-time 15 https://archlinux.org >/dev/null 2>&1 ||
		curl -fsI --max-time 15 https://github.com >/dev/null 2>&1 ||
		die "no internet connection (couldn't reach archlinux.org or github.com)."
	free=$(df -Pk / | awk 'NR == 2 { print int($4 / 1048576) }')
	(( free >= MIN_FREE_GB )) || die "not enough free space: ${free} GB on /, it needs at least ${MIN_FREE_GB} GB."
	if [ -e /var/lib/pacman/db.lck ]; then
		pgrep -x 'pacman|yay|paru|makepkg|pamac' >/dev/null && die "pacman is busy in another window: let it finish first."
		rm -f /var/lib/pacman/db.lck
	fi
	WORK=$(mktemp -d) && : > "$LOG" || die "couldn't write $LOG"
	command -v whiptail >/dev/null || pacman --noconfirm -S --needed libnewt >>"$LOG" 2>&1 ||
		pacman --noconfirm -Syu --needed libnewt >>"$LOG" 2>&1 ||
		die "couldn't install whiptail (libnewt); see $LOG"
	encrypted=0
	local src map luks
	src=$(findmnt -nvo SOURCE /)
	if lsblk -nso TYPE "$src" 2>/dev/null | grep -qx crypt; then
		encrypted=1
		map=$(lsblk -nsro NAME,TYPE "$src" | awk '$2 == "crypt" { print $1; exit }')
		luks=$(lsblk -nspro NAME,FSTYPE "$src" | awk '$2 == "crypto_LUKS" { print $1; exit }')
		if { [ -n "$luks" ] && cryptsetup luksDump "$luks" 2>/dev/null | grep -q systemd-tpm2; } ||
			grep -qE 'tpm2-device|rd\.luks\.key=|cryptkey=' /proc/cmdline ||
			awk -v m="$map" '!/^[[:space:]]*#/ && $1 == m && (($3 != "" && $3 != "none" && $3 != "-") || $4 ~ /tpm2-device/)' \
				/etc/crypttab /etc/crypttab.initramfs 2>/dev/null | grep -q .; then
			encrypted=0
		fi
	fi
}


# QUESTIONS

welcome() {
	(( yes )) && return 0
	wt --title "Welcome to SWAI!" --yes-button "Continue" --no-button "Cancel" --yesno \
		"Welcome to Sekigetsu's Workstation Auto Installer.\n\nThis sets up a full work desktop for your user: programs (TradingView included), dotfiles, and logging in automatically on your encrypted disk.\n\nA few questions first, then it runs by itself.\n\n-Sekigetsu" 15 65
}

get_user() {
	[ -n "$name" ] || name=${SUDO_USER:-}
	[ "$name" = root ] && name=""
	if [ -n "$name" ]; then
		id -u "$name" >/dev/null 2>&1 || die "there's no user called '$name'."
		return 0
	fi
	mapfile -t users < <(awk -F: '$3 >= 1000 && $3 < 60000 && $6 ~ "^/home/" { print $1 }' /etc/passwd)
	if (( ${#users[@]} == 1 )); then
		name=${users[0]}
	elif (( ${#users[@]} > 1 )); then
		(( yes )) && die "more than one user here: say which with -u NAME."
		local items=() u
		for u in "${users[@]}"; do items+=("$u" ""); done
		name=$(wt --title "Which user?" --nocancel --menu "Set up the desktop for:" 15 50 6 "${items[@]}" 3>&1 1>&2 2>&3) || exit 1
	else
		(( yes )) && die "there's no user yet: make one, or run it without -y to make one here."
		new_user=1
		get_credentials
	fi
}

get_credentials() {
	name=$(wt --inputbox "No user found. Enter a username for the new account." 10 60 3>&1 1>&2 2>&3) || exit 1
	until [[ $name =~ ^[a-z][a-z0-9_-]{0,31}$ ]] && ! getent passwd "$name" >/dev/null &&
		! getent group "$name" >/dev/null; do   # (a group name too: useradd makes a group of the same name)
		name=$(wt --nocancel --inputbox "Invalid or taken username. Use lowercase letters, numbers, - or _ only (up to 32). Must start with a letter, and not be a name the system already has." \
			11 65 3>&1 1>&2 2>&3)
	done
	pass1=$(wt --nocancel --passwordbox "Enter a password for '$name'." 10 60 3>&1 1>&2 2>&3)
	pass2=$(wt --nocancel --passwordbox "Confirm password." 10 60 3>&1 1>&2 2>&3)
	while [ -z "$pass1" ] || [ "$pass1" != "$pass2" ]; do
		pass1=$(wt --nocancel --passwordbox "Passwords were empty or didn't match. Try again." 10 60 3>&1 1>&2 2>&3)
		pass2=$(wt --nocancel --passwordbox "Confirm password." 10 60 3>&1 1>&2 2>&3)
	done
}

get_ssh_pass() {
	ssh_make=0 ssh_pass="" ssh_have=0
	local h p2
	h=$(getent passwd "$name" | cut -d: -f6)
	# (2: only the public half is there; no new key is made over it)
	[ -n "$h" ] && [ -e "$h/.ssh/id_ed25519" ] && { ssh_have=1; return 0; }
	[ -n "$h" ] && [ -e "$h/.ssh/id_ed25519.pub" ] && { ssh_have=2; return 0; }
	(( yes )) && return 0
	while :; do
		ssh_pass=$(wt --title "SSH key" --cancel-button "Skip" --passwordbox \
			"SWAI makes you an SSH key (for GitHub and servers). Choose its passphrase: you type it once per login.\n\nSkip: no key." \
			12 68 3>&1 1>&2 2>&3) || { ssh_pass=""; return 0; }
		p2=$(wt --title "SSH key" --nocancel --passwordbox "Same passphrase again." 9 68 3>&1 1>&2 2>&3)
		if [ "$ssh_pass" != "$p2" ]; then
			wt --title "SSH key" --msgbox "The passphrases didn't match. Try again." 8 50
			continue
		fi
		[ -n "$ssh_pass" ] && break
		wt --title "SSH key" --yes-button "No passphrase" --no-button "Back" --yesno \
			"No passphrase?\n\nAnyone who gets a copy of the key file can use it." 10 60 && break
	done
	unset p2
	ssh_make=1
}

get_progs() {
	local here
	here=$(dirname "$(readlink -f "$0")")
	if [ -f "$here/progs.csv" ]; then
		cat "$here/progs.csv"
	else
		curl -fLs --max-time 60 "$PROGSFILE"
	fi | tr -d '\r' | sed '/^#/d;/^[[:space:]]*$/d' > "$WORK/progs.csv"
	[ -s "$WORK/progs.csv" ] || die "couldn't get the programs list (progs.csv)."
}

plan() {
	local tag program
	repo=() other=()
	while IFS=, read -r tag program _; do
		case ${tag//C/} in
			"") repo+=("$program") ;;
			*) other+=("$tag,$program") ;;
		esac
	done < "$WORK/progs.csv"
}

summary() {
	local aur=0 flat=0 rest=0 t minutes login_text
	for t in "${other[@]}"; do
		case ${t%%,*} in A|AC) aur=$((aur + 1)) ;; F|FC) flat=$((flat + 1)) ;; *) rest=$((rest + 1)) ;; esac
	done
	minutes=$(( 8 + ${#repo[@]} / 15 + aur * 2 + flat + rest + 10 ))
	(( yes )) && return 0
	if (( ssh_have == 2 )); then ssh_text="only the public half is here (~/.ssh/id_ed25519.pub): copy in the private key"
	elif (( ssh_have )); then ssh_text="the one you have (~/.ssh/id_ed25519)"
	elif (( ! ssh_make )); then ssh_text="none (skipped)"
	elif [ -n "$ssh_pass" ]; then ssh_text="a new one, with your passphrase"
	else ssh_text="a new one, no passphrase"; fi
	if (( encrypted )); then login_text="automatic (your disk is encrypted)"
	else login_text="ly asks for your password (no encrypted disk, or it unlocks without one)"; fi
	wt --title "Ready to install" --yes-button "Start" --no-button "Cancel" --yesno \
"For:            $name$([ -n "${new_user:-}" ] && echo " (new user)")
Programs:       ${#repo[@]} from the Arch repos, $aur from the AUR, $flat flatpaks$( (( rest )) && echo ", $rest other")
SSH key:        $ssh_text
Login at boot:  $login_text
DNS:            encrypted and anonymized (DNSCrypt)
Then:           your dotfiles, wallpapers, then their own setup and clean-up

Roughly $minutes minutes, depending on your internet.
It runs by itself from here. The log is $LOG." 19 76
}


# THE INSTALL

progress_init() {
	local t
	total_w=$(( 6 + 1 + 3 + ${#repo[@]} + 2 + 2 + 1 + 2 + 12 + 2 ))
	for t in "${other[@]}"; do
		case ${t%%,*} in A|AC) total_w=$((total_w + 4)) ;; *) total_w=$((total_w + 3)) ;; esac
	done
	done_w=0 started=$(date +%s)
}
show() {
	local pct left="" elapsed
	pct=$(( done_w * 100 / total_w )); (( pct > 99 )) && pct=99
	elapsed=$(( $(date +%s) - started ))
	if (( pct >= 5 && elapsed > 60 )); then
		left=$(( elapsed * (total_w - done_w) / done_w / 60 + 1 ))
		left="  ·  about $left min left"
	fi
	printf 'XXX\n%d\n%s%s\\n\\n%s\nXXX\n' "$pct" "$1" "$left" "${2:-}" >&3
}
advance() { done_w=$(( done_w + $1 )); }
fail() { echo "$1" >> "$WORK/failed"; }

update_system() {
	show "Updating the system" "keyring, then all packages (a fresh install's packages can be old)"
	pac -Sy archlinux-keyring
	grep -q "ILoveCandy" /etc/pacman.conf || sed -i "/#VerbosePkgLists/a ILoveCandy" /etc/pacman.conf
	sed -Ei "s/^#(ParallelDownloads).*/\1 = 5/;/^#Color$/s/#//" /etc/pacman.conf
	sed -i -E "s/^#?MAKEFLAGS=.*/MAKEFLAGS=\"-j$(nproc)\"/" /etc/makepkg.conf
	pacman -Syu --noconfirm >>"$LOG" 2>&1 || pacman -Syu --noconfirm >>"$LOG" 2>&1 ||
		{ fail "system update"; return 1; }
	advance 6

	show "Installing the basics" "curl, base-devel, git, zsh, sudo"
	pac -S curl ca-certificates base-devel git zsh sudo || fail "base-devel / git / zsh / sudo"
	timedatectl set-ntp true >>"$LOG" 2>&1
	advance 1
}

setup_user() {
	if [ -n "${new_user:-}" ]; then
		useradd -m -G wheel,input -s /bin/zsh "$name" >>"$LOG" 2>&1 || { fail "creating the user $name"; return 1; }
		echo "$name:$pass1" | chpasswd
		unset pass1 pass2
	else
		usermod -aG wheel,input "$name"
	fi
	chsh -s /bin/zsh "$name" >>"$LOG" 2>&1
	home=$(getent passwd "$name" | cut -d: -f6)
	export REPODIR="$home/.local/src"
	as_user mkdir -p "$REPODIR" "$home/Downloads" "$home/Documents" "$home/Pictures" "$home/Audiobooks" "$home/sync" \
		"$home/github" "$home/.cache/zsh"
	echo "%wheel ALL=(ALL:ALL) ALL" > /etc/sudoers.d/00-wheel-sudo
	printf '%s\n' "Defaults verifypw=any, listpw=any" "%wheel ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/swai-temp
	chmod 440 /etc/sudoers.d/00-wheel-sudo /etc/sudoers.d/swai-temp
}

as_user() { sudo -u "$name" -H "$@"; }

service_on() { systemctl enable "${2:-$1.service}" >>"$LOG" 2>&1; }
service_start() { systemctl start "$1.service" >>"$LOG" 2>&1; }
service_off() { systemctl disable --now "$1.service" >>"$LOG" 2>&1; return 0; }

aur_helper() {
	show "Building $AURHELPER" "installs programs from the AUR"
	if ! command -v "$AURHELPER" >/dev/null; then
		local dir=$REPODIR/$AURHELPER
		rm -rf "$dir"
		as_user git clone --depth 1 -q "https://aur.archlinux.org/$AURHELPER.git" "$dir" >>"$LOG" 2>&1 &&
			(cd "$dir" && as_user makepkg -sif --noconfirm >>"$LOG" 2>&1) ||
			{ fail "$AURHELPER"; return 1; }
	fi
	advance 3
}

repo_packages() {
	(( ${#repo[@]} )) || return 0
	local known=() unknown=() p line n=0 m=${#repo[@]} base=$done_w count=${#repo[@]}
	declare -A in_repos
	while read -r p; do in_repos[$p]=1; done < <(pacman -Slq 2>/dev/null)
	for p in "${repo[@]}"; do
		if [ -n "${in_repos[$p]:-}" ] || pacman -Sgq "$p" >/dev/null 2>&1; then known+=("$p"); else unknown+=("$p"); fi
	done
	show "Installing ${#known[@]} programs from the Arch repos" "downloading..."
	LC_ALL=C pacman -S --noconfirm --needed "${known[@]}" 2>&1 | tee -a "$LOG" | while IFS= read -r line; do
		if [[ $line =~ ^Packages\ \(([0-9]+)\) ]]; then
			m=${BASH_REMATCH[1]}
		elif [[ $line =~ ^(installing|upgrading|reinstalling|downgrading)\ ([^ ]+)\.\.\.$ ]]; then
			n=$(( n + 1 ))
			(( n > m )) && m=$n
			done_w=$(( base + count * n / m ))
			show "Installing from the Arch repos ($n of $m)" "${BASH_REMATCH[2]}"
		fi
	done
	if (( PIPESTATUS[0] )); then
		unknown+=("${known[@]}")
	fi
	done_w=$(( base + count ))
	for p in "${unknown[@]}"; do
		pacman -Q "$p" >/dev/null 2>&1 && continue
		show "Installing $p" "$(describe "$p")"
		pac -S "$p" || fail "$p"
	done
}

other_packages() {
	local entry tag program i=0 n=${#other[@]} aur_done
	aur_done=$(pacman -Qqm 2>/dev/null)
	for entry in "${other[@]}"; do
		tag=${entry%%,*} program=${entry#*,} i=$((i + 1))
		show "$i of $n  ·  $(basename "$program" .git | sed -E 's/-(bin|git)$//')" "$(describe "$program")"
		case ${tag//C/} in
			A)
				grep -qx "$program" <<< "$aur_done" ||
					as_user "$AURHELPER" -S --needed --noconfirm --answerclean None --answerdiff None \
						--answeredit None --removemake --mflags --nocheck "$program" >>"$LOG" 2>&1 || fail "$program"
				advance 4 ;;
			F)
				{ pac -S flatpak &&
					flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo >>"$LOG" 2>&1 &&
					flatpak install -y --noninteractive flathub "$program" >>"$LOG" 2>&1; } || fail "$program"
				advance 3 ;;
			*)
				echo "unknown tag '$tag' for $program" >> "$LOG"; fail "$program (unknown tag $tag)"
				advance 3 ;;
		esac
	done
}

mark_explicit() {
	local entry names=("${repo[@]}")
	for entry in "${other[@]}"; do
		case ${entry%%,*} in A|AC) names+=("${entry#*,}") ;; esac
	done
	mapfile -t names < <(pacman -Qq -- "${names[@]}" 2>/dev/null)
	(( ${#names[@]} )) && pacman -D --asexplicit -- "${names[@]}" >>"$LOG" 2>&1
	return 0
}

install_dotfiles() {
	show "Installing your dotfiles" "$DOTFILES"
	local tmp f
	tmp=$(as_user mktemp -d "$home/.swai-clone.XXXXXX")   # (not /tmp: it's in RAM, and can be too small)
	if as_user git clone --depth 1 --single-branch --no-tags -q -b "$BRANCH" "$DOTFILES" "$tmp/d" >>"$LOG" 2>&1; then
		rm -rf "$tmp/d/.git"
		# shellcheck disable=SC2086
		(cd "$tmp/d" && for f in $KEEP; do [ -e "$home/$f" ] && rm -f "$f"; done)
		as_user cp -rfT "$tmp/d" "$home" >>"$LOG" 2>&1 || fail "copying the dotfiles"
		# a few files need a full path (desktop files, kitty's link opener): they're written for /home/user
		[ "$home" = /home/user ] || as_user sh -c 'grep -rlZF /home/user/ "$1/.config" "$1/.local/share/applications" 2>/dev/null |
			xargs -0 -r sed -i "s#/home/user/#$1/#g"' _ "$home" >>"$LOG" 2>&1
	else
		fail "dotfiles (couldn't clone $DOTFILES)"
	fi
	rm -rf "$tmp"
	advance 2
}

install_wallpapers() {
	show "Downloading the wallpapers" "$WALLPAPERS  →  ~/wallpapers"
	local tmp
	tmp=$(as_user mktemp -d "$home/.swai-clone.XXXXXX")   # (not /tmp: it's in RAM, and can be too small)
	if as_user git clone --depth 1 --single-branch --no-tags -q "$WALLPAPERS" "$tmp/w" >>"$LOG" 2>&1; then
		rm -rf "$tmp/w/.git"
		as_user cp -rfT "$tmp/w" "$home/wallpapers" >>"$LOG" 2>&1 || fail "copying the wallpapers"
	else
		fail "wallpapers (couldn't clone $WALLPAPERS)"
	fi
	rm -rf "$tmp"
	advance 2
}

setup_ssh() {
	show "Setting up SSH" "your key"
	local d=$home/.ssh
	as_user mkdir -p "$d" && chmod 700 "$d"
	if (( ssh_make )) && [ ! -e "$d/id_ed25519" ] && [ ! -e "$d/id_ed25519.pub" ]; then
		printf '%s\n%s\n' "$ssh_pass" "$ssh_pass" |
			as_user env SSH_ASKPASS_REQUIRE=never setsid -w ssh-keygen -q -t ed25519 -a 100 \
				-C "$name@$(uname -n)" -f "$d/id_ed25519" >>"$LOG" 2>&1 || fail "SSH key"
	fi
	unset ssh_pass
	advance 1
}

configure() {
	show "Setting things up" "the login screen, system settings"
	configure_login
	rmmod pcspkr 2>/dev/null
	echo "blacklist pcspkr" > /etc/modprobe.d/nobeep.conf
	mkdir -p /etc/sysctl.d
	echo "kernel.dmesg_restrict = 0" > /etc/sysctl.d/dmesg.conf
	grep -qx "WLR_DRM_NO_ATOMIC=1" /etc/environment 2>/dev/null || echo "WLR_DRM_NO_ATOMIC=1" >> /etc/environment
	advance 2
}

configure_login() {
	pacman -Q ly >/dev/null 2>&1 || { fail "the login screen (ly isn't installed)"; return; }
	mkdir -p /etc/ly
	[ -f "$home/.config/ly/config.ini" ] && cp -f "$home/.config/ly/config.ini" /etc/ly/config.ini
	if [ -f /etc/ly/config.ini ]; then
		sed -i -E "/^[[:space:]]*auto_login_(user|session)[[:space:]]*=/d" /etc/ly/config.ini
		(( encrypted )) && printf "auto_login_user = %s\nauto_login_session = %s\n" "$name" "$SESSION" >> /etc/ly/config.ini
	fi
	(( encrypted )) && [ ! -f /etc/pam.d/ly-autologin ] && cat > /etc/pam.d/ly-autologin << 'EOF'
#%PAM-1.0

auth       required     pam_permit.so
account    include      login
password   include      login
-session   optional     pam_systemd.so       class=greeter
session    include      login
EOF
	local unit=ly@tty1.service
	[ -e /usr/lib/systemd/system/ly@.service ] || unit=ly.service
	# getty off only once ly is on, so tty1 always has a login
	if service_on ly "$unit"; then systemctl disable getty@tty1.service >>"$LOG" 2>&1
	else fail "the login screen (turning ly on: do it by hand)"; fi
}

# which of these are turned on (NAME@: any instance, turned on or running, like dhcpcd@enp1s0)
net_units() {
	local u
	for u; do
		case $u in
			*@) compgen -G "/etc/systemd/system/*.wants/$u*.service" | sed 's#.*/##'
				systemctl list-units -q --plain --no-legend --state=active "$u*.service" 2>/dev/null | awk '{print $1}' ;;
			*) systemctl is-enabled -q "$u.service" 2>/dev/null && echo "$u.service" ;;
		esac
	done | sed 's/\.service$//' | sort -u | paste -sd ' '
}

# the wifi menu and the bar's network need NetworkManager: turned on (from the next boot) when nothing else runs the
# network; with iwd, systemd-networkd, dhcpcd, connman, netctl or wpa_supplicant@ in charge (instances too, like
# dhcpcd@enp1s0), switching could leave no internet, or two DHCP clients
setup_network() {
	pacman -Q networkmanager >/dev/null 2>&1 || return 0
	systemctl is-enabled -q NetworkManager.service 2>/dev/null && return 0
	local nets
	nets=$(net_units iwd systemd-networkd dhcpcd dhcpcd@ connman netctl netctl@ netctl-auto@ netctl-ifplugd@ wpa_supplicant@)
	if [ -z "$nets" ]; then
		service_on NetworkManager || fail "the wifi menu (turning NetworkManager on)"
	else
		fail "the wifi menu: it needs NetworkManager, but $nets runs the network (switch by hand if you want it)"
	fi
}

setup_dns() {
	show "Encrypting DNS" "dnscrypt-proxy, through anonymizing relays"
	local t=/etc/dnscrypt-proxy/dnscrypt-proxy.toml
	pac -S dnscrypt-proxy && [ -f "$t" ] || { fail "encrypted DNS (dnscrypt-proxy)"; advance 2; return; }
	awk '
		/^\[/ { sec = $0 }
		sec == "" && /^listen_addresses[[:space:]]*=/ { print "listen_addresses = [\x27127.0.0.1:53\x27]"; next }
		sec == "[anonymized_dns]" && /^(routes|skip_incompatible)[[:space:]]*=/ { next }
		{ print }
		/^\[anonymized_dns\]/ { print "routes = [ { server_name = \x27*\x27, via = [\x27*\x27] } ]"; print "skip_incompatible = true" }
	' "$t" > "$t.new" && mv -f "$t.new" "$t"
	grep -q '^listen_addresses' "$t" || sed -i "1i listen_addresses = ['127.0.0.1:53']" "$t"
	[ -e /etc/resolv.conf ] && [ ! -e /etc/resolv.conf.bak ] && cp -L /etc/resolv.conf /etc/resolv.conf.bak
	systemctl is-enabled -q systemd-resolved 2>/dev/null && service_off systemd-resolved
	[ -d /etc/NetworkManager ] && mkdir -p /etc/NetworkManager/conf.d &&
		printf '[main]\ndns=none\n' > /etc/NetworkManager/conf.d/dns.conf
	command -v nmcli >/dev/null 2>&1 && nmcli general reload conf >>"$LOG" 2>&1
	if [ -f /etc/dhcpcd.conf ] && ! grep -qx 'nohook resolv.conf' /etc/dhcpcd.conf; then
		echo 'nohook resolv.conf' >> /etc/dhcpcd.conf
		systemctl try-restart dhcpcd.service 'dhcpcd@*.service' >>"$LOG" 2>&1   # (a running dhcpcd doesn't re-read it)
	fi
	service_off dnsmasq
	systemctl disable dnscrypt-proxy.socket >>"$LOG" 2>&1
	service_on dnscrypt-proxy || { fail "encrypted DNS (turning dnscrypt-proxy on)"; advance 2; return; }
	systemctl restart dnscrypt-proxy.service >>"$LOG" 2>&1   # (restart: a re-run's edited config is loaded)
	[ -L /etc/resolv.conf ] && rm -f /etc/resolv.conf
	printf 'nameserver 127.0.0.1\noptions edns0\n' > /etc/resolv.conf
	local i=0
	until grep -qx 'nameserver 127.0.0.1' /etc/resolv.conf || printf 'nameserver 127.0.0.1\noptions edns0\n' > /etc/resolv.conf
		dnscrypt-proxy -config "$t" -resolve archlinux.org >>"$LOG" 2>&1 && ss -lun 2>/dev/null | grep -q '127.0.0.1:53 ' &&
		sleep 2 && grep -qx 'nameserver 127.0.0.1' /etc/resolv.conf; do
		i=$((i + 1)); (( i > 15 )) && { fail "encrypted DNS (dnscrypt-proxy didn't start yet: it should after the reboot)"; break; }
		sleep 2
	done
	advance 2
}

finish() {
	local up=$home/.local/bin/update
	command -v pywalfox >/dev/null 2>&1 &&
		as_user pywalfox install --manifest-path "$home/.glide-browser/native-messaging-hosts" >>"$LOG" 2>&1
	if [ -f "$home/.local/lib/vpn-install" ]; then
		SUDO_USER=$name sh "$home/.local/lib/vpn-install" >>"$LOG" 2>&1 ||
			fail "VPN without a password (run: sudo sh ~/.local/lib/vpn-install)"
	fi
	advance 2

	show "Running update" "system settings, plugins, clean-up; it takes a while"
	as_user "$up" >>"$LOG" 2>&1 || fail "update (some steps: run update again after logging in)"
	advance 10
}

configure_sudo() {
	[ -d /etc/sudoers.d ] || return 0   # (sudo isn't installed: the system update failed before it)
	echo "%wheel ALL=(ALL:ALL) ALL" > /etc/sudoers.d/00-wheel-sudo
	echo "%wheel ALL=(ALL:ALL) NOPASSWD: /usr/bin/pacman -Syu" > /etc/sudoers.d/01-passwordless-cmds
	echo "Defaults editor=/usr/bin/nvim:/usr/bin/vim:/usr/bin/vi" > /etc/sudoers.d/02-visudo-editor
	chmod 440 /etc/sudoers.d/0[012]-*
	rm -f /etc/sudoers.d/swai-temp
}

install_all() {
	progress_init
	update_system || return
	setup_user || return
	aur_helper
	repo_packages
	other_packages
	mark_explicit
	install_dotfiles
	install_wallpapers
	setup_ssh
	configure
	setup_network
	finish
	setup_dns
	done_w=$total_w
	printf 'XXX\n100\nDone\nXXX\n' >&3
}


# MAIN

preflight
trap '[ -n "${wt_sp:-}" ] && pkill -P "$wt_sp"; kill ${wt_kp:-} ${wt_sp:-} 2>/dev/null; rm -f /etc/sudoers.d/swai-temp; rm -rf "$WORK"; [ -t 0 ] && stty sane' EXIT
trap 'exit 1' HUP INT QUIT TERM

step_line 1 "a few questions"
welcome || die "cancelled."
get_user
get_progs
# Backspace on the summary goes back a screen (the SSH key question, or the welcome screen when there's a key already)
while :; do
	get_ssh_pass
	plan
	back_ok=1 summary
	case $? in
		0) break ;;
		10) (( ssh_have )) && { welcome || die "cancelled."; } ;;
		*) die "cancelled." ;;
	esac
done

step_line 2 "installing"
: > "$WORK/failed"
{ install_all 3>&1 1>>"$LOG" 2>&1 </dev/null; } | wt --title "Installing" --gauge "Starting...\n\n " 12 74 0
unset ssh_pass
configure_sudo
[ -n "${home:-}" ] || home=$(getent passwd "$name" | cut -d: -f6)

step_line 3 "done"
mapfile -t failed < <(sort -u "$WORK/failed")
if grep -qx "system update" "$WORK/failed"; then
	msg="The system update failed, so nothing else was installed (installing onto a half-updated system can break it).\n\nWhy is in $LOG (often a mirror that's down, or a package conflict: run  sudo pacman -Syu  to see it). Fix that, then run swai again."
	if (( yes )); then clear; printf '%b\n' "$msg"; else wt --title "Stopped" --msgbox "$msg" 13 76; clear; fi
	exit 1
fi
if (( ${#failed[@]} )); then
	result="Done, but these didn't install:\n\n$(printf '  %s\\n' "${failed[@]}")\nWhy is in $LOG. Install them later with: yay -S NAME"
	height=$(( 14 + ${#failed[@]} ))
else
	result="Everything installed."
	height=12
fi
pub=$home/.ssh/id_ed25519.pub
if [ -f "$pub" ]; then
	if [ -f "$home/.ssh/id_ed25519" ]; then result+="\n\nYour SSH key is ~/.ssh/id_ed25519."
	else result+="\n\nOnly the public half of your SSH key is here: copy its private half to ~/.ssh/id_ed25519."; fi
	result+="\nFor GitHub, paste its public key (cat ~/.ssh/id_ed25519.pub):\n\n$(cat "$pub")\n\nFingerprint: $(ssh-keygen -lf "$pub" | cut -d' ' -f2)"
	height=$(( height + 9 ))
fi
if [ "$(ly_user)" = "$name" ]; then after="After a reboot you go straight into your desktop as '$name', once the disk is unlocked."
else after="After a reboot, log in as '$name' at the login screen."; fi
rows=$(tput lines 2>/dev/null || echo 24) scroll=()
(( height > rows - 2 )) && { height=$(( rows - 2 )); scroll=(--scrolltext); }
if (( yes )); then
	clear
	printf '%b\n\n%s\n' "$result" "$after"
elif wt --title "All done!" "${scroll[@]}" --yes-button "Reboot now" --no-button "Later" --yesno \
	"$result\n\n$after\n\n-Sekigetsu" "$height" 78; then
	clear
	trap '' HUP
	pkill -TERM -u "$name"; sleep 2; pkill -KILL -u "$name"
	rm -rf "$WORK"
	exec reboot
else
	clear
fi
