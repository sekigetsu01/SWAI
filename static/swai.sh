#!/bin/sh
# SWAI - Sekigetsu's Wayland Arch Installer
# Run as root on a fresh Arch/Artix installation.


# CONFIGURATION

DOTFILES="https://github.com/sekigetsu01/mangorice.git"
PROGSFILE="https://raw.githubusercontent.com/sekigetsu01/SWAI/main/static/progs.csv"
AURHELPER="yay"
BRANCH="main"
export TERM=ansi


# UTILITIES

# Install a package silently via pacman.
pkg() { pacman --noconfirm --needed -S "$1" >/dev/null 2>&1; }

# Print error to stderr and exit.
die() { printf "%s\n" "$1" >&2; exit 1; }

# Display a non-blocking info box.
info() { whiptail --title "SWAI" --infobox "$1" 8 70; }


# DIALOG PROMPTS

welcome() {
	whiptail --title "Welcome to SWAI!" \
		--msgbox "Welcome to Sekigetsu's Wayland Arch Installer.\n\nThis script will automatically set up a full desktop environment.\n\n-Sekigetsu" 10 60

	whiptail --title "Before we begin..." \
		--yes-button "Ready!" --no-button "Go back" \
		--yesno "Make sure your system has up-to-date pacman mirrors and a refreshed Arch keyring before continuing.\n\nIf unsure, run: pacman -Sy archlinux-keyring" 9 65
}

get_credentials() {
	name=$(whiptail --inputbox "Enter a username for the new account." 10 60 3>&1 1>&2 2>&3 3>&1) || exit 1

	while ! echo "$name" | grep -q "^[a-z_][a-z0-9_-]*$"; do
		name=$(whiptail --nocancel \
			--inputbox "Invalid username. Use lowercase letters, numbers, - or _ only. Must start with a letter." \
			10 65 3>&1 1>&2 2>&3 3>&1)
	done

	pass1=$(whiptail --nocancel --passwordbox "Enter a password for '$name'." 10 60 3>&1 1>&2 2>&3 3>&1)
	pass2=$(whiptail --nocancel --passwordbox "Confirm password." 10 60 3>&1 1>&2 2>&3 3>&1)

	while [ "$pass1" != "$pass2" ]; do
		unset pass2
		pass1=$(whiptail --nocancel --passwordbox "Passwords did not match. Try again." 10 60 3>&1 1>&2 2>&3 3>&1)
		pass2=$(whiptail --nocancel --passwordbox "Confirm password." 10 60 3>&1 1>&2 2>&3 3>&1)
	done
}

check_existing_user() {
	id -u "$name" >/dev/null 2>&1 && \
		whiptail --title "User already exists" \
			--yes-button "Continue anyway" --no-button "Go back" \
			--yesno "The user '$name' already exists.\n\nSWAI will overwrite conflicting dotfiles and settings but will NOT touch personal files (Documents, Videos, etc).\n\nThe password will also be updated." 12 65
}

confirm_install() {
	whiptail --title "Ready to install" \
		--yes-button "Let's go!" --no-button "Cancel" \
		--yesno "Everything is set. The installation will now run automatically.\n\nThis may take a while. Sit back and relax." 10 60 || { clear; exit 1; }
}


# SYSTEM SETUP

refresh_keys() {
	case "$(readlink -f /sbin/init)" in
		*systemd*)
			info "Refreshing Arch keyring..."
			pacman --noconfirm -S archlinux-keyring >/dev/null 2>&1
			;;
		*)
			info "Enabling Arch repositories for Artix..."
			if ! grep -q "^\[universe\]" /etc/pacman.conf; then
				cat >> /etc/pacman.conf << 'EOF'

[universe]
Server = https://universe.artixlinux.org/$arch
Server = https://mirror1.artixlinux.org/universe/$arch
Server = https://mirror.pascalpuffke.de/artix-universe/$arch
EOF
				pacman -Sy --noconfirm >/dev/null 2>&1
			fi
			pacman --noconfirm --needed -S artix-keyring artix-archlinux-support >/dev/null 2>&1
			for repo in extra community; do
				grep -q "^\[$repo\]" /etc/pacman.conf || \
					printf "\n[%s]\nInclude = /etc/pacman.d/mirrorlist-arch\n" "$repo" >> /etc/pacman.conf
			done
			pacman -Sy >/dev/null 2>&1
			pacman-key --populate archlinux >/dev/null 2>&1
			;;
	esac
}

configure_pacman() {
	grep -q "ILoveCandy" /etc/pacman.conf || sed -i "/#VerbosePkgLists/a ILoveCandy" /etc/pacman.conf
	sed -Ei "s/^#(ParallelDownloads).*/\1 = 5/;/^#Color$/s/#//" /etc/pacman.conf
}

configure_makepkg() {
	sed -i "s/-j2/-j$(nproc)/;/^#MAKEFLAGS/s/^#//" /etc/makepkg.conf
}


# USER CREATION

create_user() {
	info "Creating user '$name'..."

	useradd -m -g wheel -s /bin/zsh "$name" >/dev/null 2>&1 || \
		usermod -a -G wheel "$name"

	mkdir -p "/home/$name"
	chown "$name":wheel "/home/$name"

	export REPODIR="/home/$name/.local/src"
	mkdir -p "$REPODIR"
	chown -R "$name":wheel "$(dirname "$REPODIR")"

	echo "$name:$pass1" | chpasswd
	unset pass1 pass2
}

create_directories() {
	info "Creating home directories..."
	for dir in Downloads Pictures sync github; do
		mkdir -p "/home/$name/$dir"
		chown "$name":wheel "/home/$name/$dir"
	done
}


# PACKAGE INSTALLATION

manual_install() {
	# Build and install a package from the AUR or a custom git URL.
	# Used for the AUR helper itself and any custom sources.
	if [ -z "$2" ]; then
		reponame="$1"
		reposource="https://aur.archlinux.org/$reponame.git"
		pacman -Qq "$reponame" >/dev/null 2>&1 && return 0
	else
		reponame=$(basename "$1" .git)
		reposource="$1"
	fi

	info "Manually building '$reponame'..."
	sudo -u "$name" mkdir -p "$REPODIR/$reponame"

	# Clone the repo; if it already exists, pull the latest instead.
	sudo -u "$name" git -C "$REPODIR" clone --depth 1 --single-branch --no-tags -q \
		"$reposource" "$REPODIR/$reponame" 2>/dev/null || \
		sudo -u "$name" git -C "$REPODIR/$reponame" pull --force origin HEAD

	cd "$REPODIR/$reponame" || return 1
	sudo -u "$name" makepkg -sif --noconfirm >/dev/null 2>&1 || return 1
}

aur_install() {
	# Skip if already installed via AUR.
	echo "$aurinstalled" | grep -q "^$1$" && return 0
	whiptail --title "SWAI – Installing ($n/$total)" --infobox "AUR: $1\n$2" 8 70
	sudo -u "$name" $AURHELPER -S --noconfirm "$1" >/dev/null 2>&1
}

git_make_install() {
	progname=$(basename "$1" .git)
	dir="$REPODIR/$progname"
	whiptail --title "SWAI – Installing ($n/$total)" --infobox "git+make: $progname\n$2" 8 70

	# Clone the repo; if it already exists, pull the latest instead.
	sudo -u "$name" git -C "$REPODIR" clone --depth 1 --single-branch --no-tags -q \
		"$1" "$dir" 2>/dev/null || \
		sudo -u "$name" git -C "$dir" pull --force origin HEAD

	cd "$dir" || return 1
	make >/dev/null 2>&1
	make install >/dev/null 2>&1
	cd /tmp || return 1
}

pipx_install() {
	# Install a Python package via pipx into an isolated environment.
	whiptail --title "SWAI – Installing ($n/$total)" --infobox "pipx: $1\n$2" 8 70
	[ -x "$(command -v pipx)" ] || pkg python-pipx
	sudo -u "$name" pipx install "$1" >/dev/null 2>&1
	sudo -u "$name" pipx ensurepath >/dev/null 2>&1
}

flatpak_install() {
	whiptail --title "SWAI – Installing ($n/$total)" --infobox "flatpak: $1\n$2" 8 70
	pkg flatpak
	flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo >/dev/null 2>&1
	flatpak install flathub "$1" -y >/dev/null 2>&1
}

pacman_install() {
	whiptail --title "SWAI – Installing ($n/$total)" --infobox "pacman: $1\n$2" 8 70
	pkg "$1"
}

installation_loop() {
	# CSV format:  TAG,package,"description"
	#   (blank) = pacman   A = AUR   F = Flatpak   G = git+make   P = pipx   S = manual AUR
	([ -f "$PROGSFILE" ] && cp "$PROGSFILE" /tmp/progs.csv) || \
		curl -Ls "$PROGSFILE" | sed '/^#/d' > /tmp/progs.csv

	total=$(wc -l < /tmp/progs.csv)
	aurinstalled=$(pacman -Qqm)
	n=0

	while IFS=, read -r tag program comment; do
		n=$((n + 1))
		comment=$(echo "$comment" | sed -E 's/(^"|"$)//g')
		case "$tag" in
			A) aur_install      "$program" "$comment" ;;
			F) flatpak_install  "$program" "$comment" ;;
			G) git_make_install "$program" "$comment" ;;
			S) manual_install   "$program" ;;
			P) pipx_install     "$program" "$comment" ;;
			*) pacman_install   "$program" "$comment" ;;
		esac
	done < /tmp/progs.csv
}


# DOTFILES & BROWSER

install_dotfiles() {
	info "Installing dotfiles..."
	tmpdir=$(mktemp -d)
	chown "$name":wheel "$tmpdir"
	sudo -u "$name" git clone --depth 1 --single-branch --no-tags -q \
		--recurse-submodules -b "$BRANCH" "$DOTFILES" "$tmpdir"
	sudo -u "$name" cp -rfT "$tmpdir" "/home/$name"
	rm -rf "$tmpdir"
}

makeuserjs() {
	# Apply hardened user.js privacy settings to the Librewolf profile.
	userjs="/home/$name/.config/librewolf/user.js"
	[ -f "$userjs" ] && cp "$userjs" "$pdir/user.js"
}

setup_browser() {
	info "Configuring Librewolf..."

	# Launch headless to generate a fresh profile directory, then kill it.
	sudo -u "$name" librewolf --headless >/dev/null 2>&1 &
	sleep 3
	pkill -u "$name" librewolf 2>/dev/null
	sleep 1

	profilesini="/home/$name/.librewolf/profiles.ini"

	# Bail out cleanly if Librewolf didn't generate a profile.
	[ -f "$profilesini" ] || { info "Librewolf profile not found — skipping browser config."; return 0; }

	profile=$(sed -n "/Default=.*.default-default/ s/.*=//p" "$profilesini")
	pdir="/home/$name/.librewolf/$profile"

	[ -d "$pdir" ] && makeuserjs
}


# POST-INSTALL CONFIGURATION

configure_shell() {
	info "Configuring shell..."
	chsh -s /bin/zsh "$name" >/dev/null 2>&1
	sudo -u "$name" mkdir -p "/home/$name/.cache/zsh"
}

configure_system() {
	# Silence the PC speaker beep permanently.
	rmmod pcspkr 2>/dev/null
	echo "blacklist pcspkr" > /etc/modprobe.d/nobeep.conf

	# Allow non-root users to read kernel logs.
	mkdir -p /etc/sysctl.d
	echo "kernel.dmesg_restrict = 0" > /etc/sysctl.d/dmesg.conf

	# Generate a dbus machine ID — required on Artix runit systems.
	dbus-uuidgen > /var/lib/dbus/machine-id 2>/dev/null

	# Export dbus session for apps that need it.
	echo 'export $(dbus-launch)' > /etc/profile.d/dbus.sh

	# Create GnuPG directory with correct permissions.
	export GNUPGHOME="/home/$name/.local/share/gnupg"
	sudo -u "$name" mkdir -p "$GNUPGHOME"
	chmod 0700 "$GNUPGHOME"
}

cleanup() {
	info "Cleaning up..."

	rm -rf /var/cache/pacman/pkg/download-*

	orphans=$(pacman -Qtdq 2>/dev/null)
	[ -n "$orphans" ] && pacman --noconfirm -Rns $orphans

	sudo -u "$name" $AURHELPER -Scc --noconfirm >/dev/null 2>&1

	rm -rf "/home/$name/.cache"
}

configure_sudo() {
	# Must run last — replaces the temporary NOPASSWD rule set earlier.
	echo "%wheel ALL=(ALL:ALL) ALL" \
		> /etc/sudoers.d/00-wheel-sudo
	echo "%wheel ALL=(ALL:ALL) NOPASSWD: \
/usr/bin/shutdown,/usr/bin/reboot,/usr/bin/systemctl suspend,\
/usr/bin/wifi-menu,/usr/bin/mount,/usr/bin/umount,\
/usr/bin/pacman -Syu,/usr/bin/pacman -Syyu,/usr/bin/pacman -Syyu --noconfirm,\
/usr/bin/loadkeys,/usr/bin/pacman -Syyuw --noconfirm" \
		> /etc/sudoers.d/01-passwordless-cmds
	echo "Defaults editor=/usr/bin/nvim" \
		> /etc/sudoers.d/02-visudo-editor
}


# MAIN

pacman --noconfirm --needed -Sy libnewt >/dev/null 2>&1 || \
	die "Run this script as root on an Arch-based system with an active internet connection."

welcome              || die "Aborted."
get_credentials      || die "Aborted."
check_existing_user  || die "Aborted."
confirm_install      || die "Aborted."

refresh_keys         || die "Failed to refresh keyrings."
configure_pacman
configure_makepkg

for dep in curl ca-certificates base-devel git ntp zsh; do
	info "Installing dependency: $dep..."
	pkg "$dep"
done

info "Syncing system clock..."
ntpd -q -g >/dev/null 2>&1

create_user          || die "Failed to create user."
create_directories

trap 'rm -f /etc/sudoers.d/swai-temp' HUP INT QUIT TERM PWR EXIT
echo "%wheel ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/swai-temp

manual_install "$AURHELPER" || die "Failed to install AUR helper ($AURHELPER)."
installation_loop

install_dotfiles
setup_browser

configure_shell
configure_system
cleanup
configure_sudo

whiptail --title "All done!" \
	--msgbox "Installation complete!\n\nLog out and back in as '$name' to launch your desktop.\n\n.t Sekigetsu" 10 65
