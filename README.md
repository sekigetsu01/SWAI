# Sekigetsu's Workstation Auto Installer

## Installation:

On a fresh Arch Linux install (made on an encrypted disk), log in as the user you made while installing and run:

```
sudo pacman -S git
git clone https://github.com/sekigetsu01/SWAI.git
cd SWAI/static
sudo sh swai.sh
```

If that user can't use sudo yet (a hand-made install has no sudo until SWAI sets it up), do the same as root:
`pacman -S git`, clone it the same way, and run `sh swai.sh`; it finds your user by itself.

SWAI sets up that user: no new username or password to enter (if there's no user yet, it makes one).
It asks a few things at the start (h and l, or the arrows, pick a button; y and n answer yes or no; Backspace goes back), shows what it's about to
do, and then runs by itself with a progress bar and the time left. When it's done, it lists anything
that didn't install, and after a reboot (and the disk's password) you go straight into the desktop.

It also asks for a passphrase for a new SSH key (twice; Skip makes none). The passphrase stays in
memory only. The key is `~/.ssh/id_ed25519` (ed25519), never made over one you already have, and
the end screen shows its public key for GitHub (`cat ~/.ssh/id_ed25519.pub`). The dotfiles turn on
openssh's `ssh-agent` and their `sys-setup` adds `AddKeysToAgent yes` to `~/.ssh/config`, so you type
the passphrase once per login. With `-y` no key is made.

Before anything else it checks that this is Arch Linux with systemd (the dotfiles' `update`,
`sys-setup` and timers need it, so Artix isn't supported), that there's internet and at least
20 GB free, and that pacman isn't busy, and stops with a clear message if not.

Options:

```
sudo sh swai.sh -y          no questions: installs everything
sudo sh swai.sh -u NAME     set up NAME (when there's more than one user)
```

## What is SWAI?

SWAI is a script that autoinstalls and autoconfigures a minimal terminal-and-vim-based
Arch Linux desktop on Wayland, for a work machine: the same desktop as my VMs, sized for a real
screen, with brightness keys, night mode, encrypted drives (`lk`) and TradingView. It doesn't set up
virtual machines.

It installs everything in the list, closed source programs included (TradingView and Vesktop), without asking.

It also installs the real-time kernel (`linux-rt` and `linux-rt-headers`, from the Arch repos) next to the one
you have. It isn't added to your boot menu: with GRUB run `sudo grub-mkconfig -o /boot/grub/grub.cfg`, with
systemd-boot add an entry for it. To leave it out, delete those two lines from `progs.csv`.

SWAI is inspired by [LARBS](https://github.com/LukeSmithxyz/LARBS).

## Customization

By default, SWAI uses the programs [here in progs.csv](static/progs.csv) and installs
[my dotfiles repo here](https://github.com/sekigetsu01/workrice), and puts
[my wallpapers](https://github.com/sekigetsu01/wallpapers) in `~/wallpapers` (where `wallpaper` picks
from). Once the dotfiles are in place it runs their `update` (sys-setup, plugins, then its clean-up).
Run again, it copies the dotfiles over yours again, except the few files their scripts change (`KEEP` in
`swai.sh`: `~/.config/times.conf`, the timers' `times.conf`, kp's and the clicker's config): those it only adds when missing.

### The `progs.csv` list

SWAI will parse the given programs list and install all given programs. Note
that the programs file must be a three column `.csv`. SWAI uses the `progs.csv` next to
`swai.sh`, so your edits are used straight away (the copy on GitHub only if there isn't one).

The first column is a "tag" that determines how the program is installed, ""
(blank) for the main repository, `A` for installation via the AUR, or `F` for a flatpak (from Flathub).

The second column is the name of the program in the repository, and the third column is a description
that describes the program.
During installation, SWAI shows it under the program's name. It also doubles as documentation
for people who read the CSV and want to install my dotfiles manually.

SWAI installs every repo program (blank tag) first, all in one pacman run, then the others one by one, from the
top of the list to the bottom. If you include commas in your program
descriptions, put double quotes around the whole description.

### The script itself

The main work is done by `install_all`, which runs under the progress bar. It updates the
system first, then
installs every repo package in one pacman run (much faster than one at a time; any name pacman
doesn't know is tried on its own, so one bad name doesn't stop the rest), then goes through the
other programs one by one, choosing how to install each from its tag (`other_packages`). New methods
of installation and tags go there.

It also makes the folders `Downloads`, `Documents`, `Pictures`, `Audiobooks`, `sync` and `github`, adds you to
the `input` group (the clicker reads the keyboard and mouse), turns off the PC speaker beep, lets you read
kernel messages (`dmesg`) without sudo, and allows screen tearing in games (`WLR_DRM_NO_ATOMIC=1`).

Everything the installs print goes to `/var/log/swai.log`. If anything fails to install,
SWAI lists it at the end, and the log says why.

Programs from the AUR can only be built by a non-root user, so SWAI lets your user use `sudo`
without a password while it runs. At the end that's removed, leaving only exactly `sudo pacman -Syu`
(nothing added to it) without a password. `update` still asks for yours once, at the start.
The VPN (`Super+u`) starts without one too: SWAI runs the dotfiles' `vpn-install`, which installs the VPN's
root half (`/usr/local/lib/vpn-root`) and a sudo rule for exactly that.

## Login screen

SWAI sets this up itself: it copies `~/.config/ly/config.ini` from the dotfiles to
`/etc/ly/config.ini` and turns ly on (`ly@tty1.service`). If your disk is encrypted, it also logs you in automatically: you've already typed
the disk's password at boot, so a second password is a waste of time (not when the disk unlocks itself,
with a TPM or a key file: then nobody types one, so ly asks). Without an encrypted disk,
ly asks for your password.

## Network

The wifi menu (`Super+F5`) and the network in the bar use NetworkManager. SWAI turns it on (from the next boot)
when nothing else runs your network. If iwd, systemd-networkd, dhcpcd, connman, netctl or wpa_supplicant does
(also per interface or profile, like `dhcpcd@enp1s0`), it's left as it is (switching could leave you without
internet, or with two DHCP clients) and the end screen says so: switch by hand if you want the menu.

## Encrypted DNS

SWAI sets up [DNSCrypt](https://github.com/DNSCrypt/dnscrypt-proxy) (`dnscrypt-proxy` from the Arch
repos, so pacman keeps it up to date): every name lookup is encrypted, and goes through an
anonymizing relay, so your internet provider can't see which sites you look up, and the DNS server
doesn't see your address.

- `/etc/dnscrypt-proxy/dnscrypt-proxy.toml`: it listens on `127.0.0.1:53`, and `[anonymized_dns]`
  gets `routes = [ { server_name = '*', via = ['*'] } ]` (any server, through any relay) and
  `skip_incompatible = true` (servers that can't be anonymized are left out).
- `/etc/resolv.conf` is `nameserver 127.0.0.1` and `options edns0` (the old one is kept as
  `/etc/resolv.conf.bak`). NetworkManager, dhcpcd and systemd-resolved, if you have them, are told
  to leave it alone (dhcpcd is restarted so it takes that in straight away).
- The service is turned on and started straight away.

To change servers or relays, edit that file and restart it: `sudo systemctl restart dnscrypt-proxy`.

## Manual setup (if something fails)

The same things SWAI sets up for encrypted DNS and the login screen, done by hand, in case a step of
`swai.sh` fails (its log says which).

### DNS Crypt

```
sudo pacman -S dnscrypt-proxy
```
```
sudo nvim /etc/dnscrypt-proxy/dnscrypt-proxy.toml
```
At the top, set:
```
listen_addresses = ['127.0.0.1:53']
```
and under `[anonymized_dns]`:
```
routes = [ { server_name = '*', via = ['*'] } ]
skip_incompatible = true
```
Stop NetworkManager (and dhcpcd, if you use it) from writing `/etc/resolv.conf`:
```
sudo mkdir -p /etc/NetworkManager/conf.d
printf '[main]\ndns=none\n' | sudo tee /etc/NetworkManager/conf.d/dns.conf
sudo nmcli general reload conf
```
```
echo 'nohook resolv.conf' | sudo tee -a /etc/dhcpcd.conf
```
If systemd-resolved is on, turn it off:
```
sudo systemctl disable --now systemd-resolved
```
Turn dnscrypt-proxy on (the service, not its socket):
```
sudo systemctl disable dnscrypt-proxy.socket
```
```
sudo systemctl enable --now dnscrypt-proxy.service
```
Point the system at it, keeping the old file:
```
sudo cp -L /etc/resolv.conf /etc/resolv.conf.bak
```
```
sudo rm /etc/resolv.conf
```
```
sudo nvim /etc/resolv.conf
```
```
nameserver 127.0.0.1
options edns0
```
Check it answers:
```
dnscrypt-proxy -config /etc/dnscrypt-proxy/dnscrypt-proxy.toml -resolve archlinux.org
```

### Autologin

Only with an encrypted disk (you've typed its password at boot already). Copy the dotfiles' ly config:
```
sudo cp ~/.config/ly/config.ini /etc/ly/config.ini
```
```
sudo nvim /etc/ly/config.ini
```
Add at the bottom (your username):
```
auto_login_user = user
auto_login_session = mango
```
```
sudo nvim /etc/pam.d/ly-autologin
```
```
#%PAM-1.0

auth       required     pam_permit.so
account    include      login
password   include      login
-session   optional     pam_systemd.so       class=greeter
session    include      login
```
Turn ly on, then the plain text login off:
```
sudo systemctl enable ly@tty1.service
```
```
sudo systemctl disable getty@tty1.service
```
It takes over at the next boot (`sudo systemctl restart ly@tty1.service` does it now, but logs you out).
