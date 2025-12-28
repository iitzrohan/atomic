#!/usr/bin/bash

# shellcheck disable=SC1091
. /ctx/common.sh

set -eoux pipefail

# Ublue Staging
dnf5 -y copr enable ublue-os/staging

# Ublue Packages
dnf5 -y copr enable ublue-os/packages

# OBS-VKcapture
dnf5 -y copr enable bazzite-org/obs-vkcapture

# Bazzite Repos
dnf5 -y copr enable bazzite-org/bazzite
dnf5 -y copr enable bazzite-org/bazzite-multilib
dnf5 -y copr enable bazzite-org/LatencyFleX

# Sunshine
dnf5 -y copr enable lizardbyte/beta

# VS Code
echo -e "[code]\nname=Visual Studio Code\nbaseurl=https://packages.microsoft.com/yumrepos/vscode\nenabled=1\nautorefresh=1\ntype=rpm-md\ngpgcheck=1\ngpgkey=https://packages.microsoft.com/keys/microsoft.asc" | tee /etc/yum.repos.d/vscode.repo > /dev/null

# Layered Applications
LAYERED_PACKAGES=(
    adw-gtk3-theme
    cascadia-fonts-all
    code
    git-credential-libsecret
    git-credential-oauth
    emacs
    qemu-ui-gtk
    spice-gtk-tools
    sunshine
    uupd
)

if [[ "${IMAGE}" =~ aurora ]]; then
    LAYERED_PACKAGES+=(krdp)
fi

if [[ "${IMAGE}" =~ bluefin ]]; then
    LAYERED_PACKAGES+=(
        gnome-shell-extension-compiz-windows-effect
        gnome-shell-extension-hotedge
        gnome-shell-extension-just-perfection
    )
fi

if [[ "${IMAGE}" =~ bluefin|bazzite ]]; then
    LAYERED_PACKAGES+=(gnome-shell-extension-drive-menu)
fi

dnf5 install --setopt=install_weak_deps=False -y "${LAYERED_PACKAGES[@]}"

dnf5 remove -y google-noto-fonts-all

# Services / Use uupd updater
dnf5 remove -y ublue-os-update-services
systemctl disable rpm-ostreed-automatic.timer
systemctl disable flatpak-system-update.timer
systemctl --global disable flatpak-user-update.timer
systemctl disable brew-update.timer
systemctl disable brew-upgrade.timer
systemctl enable uupd.timer

# Devpod cli
curl -Lo /usr/bin/devpod "https://github.com/loft-sh/devpod/releases/latest/download/devpod-linux-amd64"
chmod +x /usr/bin/devpod
/usr/bin/devpod completion bash >/etc/bash_completion.d/devpod.sh
/usr/bin/devpod completion fish >/usr/share/fish/completions/devpod.fish

# Macadam
mkdir -p /usr/share/factory/opt/macadam/bin/
curl -Lo /usr/share/factory/opt/macadam/bin/macadam https://github.com/crc-org/macadam/releases/latest/download/macadam-linux-amd64
chmod +x /usr/share/factory/opt/macadam/bin/macadam
ln -s /usr/share/factory/opt/macadam/bin/macadam /usr/bin/macadam
/usr/bin/macadam completion bash >/etc/bash_completion.d/macadam.sh
/usr/bin/macadam completion fish >/usr/share/fish/completions/macadam.fish

# Zed because why not?
curl -Lo /tmp/zed.tar.gz https://zed.dev/api/releases/stable/latest/zed-linux-x86_64.tar.gz
mkdir -p /usr/lib/zed.app/
tar -xvf /tmp/zed.tar.gz -C /usr/lib/zed.app/ --strip-components=1
chown 0:0 -R /usr/lib/zed.app
ln -sf /usr/lib/zed.app/bin/zed /usr/bin/zed
cp /usr/lib/zed.app/share/applications/zed.desktop /usr/share/applications/dev.zed.Zed.desktop
mkdir -p /usr/share/icons/hicolor/1024x1024/apps
cp {/usr/lib/zed.app,/usr}/share/icons/hicolor/512x512/apps/zed.png
cp {/usr/lib/zed.app,/usr}/share/icons/hicolor/1024x1024/apps/zed.png
sed -i "s@Exec=zed@Exec=/usr/lib/zed.app/libexec/zed-editor@g" /usr/share/applications/dev.zed.Zed.desktop

# Sysexts
# mkdir -p /usr/lib/sysupdate.d
# SYSEXTS=(emacs)
# for s in "${SYSEXTS[@]}"; do
#     tee /usr/lib/sysupdate.d/"$s".transfer <<EOF
# [Transfer]
# Verify=false

# [Source]
# Type=url-file
# Path=https://extensions.fcos.fr/fedora/$s/
# MatchPattern=emacs-@v-%w-%a.raw

# [Target]
# InstancesMax=2
# Type=regular-file
# Path=/var/lib/extensions.d/
# MatchPattern=emacs-@v-%w-%a.raw
# CurrentSymlink=/var/lib/extensions/emacs.raw
# EOF
# done
