#!/usr/bin/env bash
# ============================================================
#  ikajokw OS — build.sh
#  แปลงจาก Debian → ikajokw OS แล้ว export เป็น .iso
#
#  รัน: sudo bash build.sh
#  เวลา: ~10-20 นาที
#  พื้นที่: ~5GB
# ============================================================

set -euo pipefail

OS_NAME="ikajokw"
OS_VERSION="1.0.0"
OS_ARCH="x86_64"

BUILD_ROOT="/tmp/ikajokw-build"
ROOTFS="${BUILD_ROOT}/rootfs"
ISO_DIR="${BUILD_ROOT}/iso"
LOG_DIR="${BUILD_ROOT}/logs"
OUTPUT="$(pwd)/ikajokw-${OS_VERSION}-${OS_ARCH}.iso"

G='\033[0;32m'; Y='\033[1;33m'; B='\033[0;34m'
R='\033[0;31m'; W='\033[1;37m'; DIM='\033[2m'; RESET='\033[0m'

log()  { echo -e "${G}[  OK  ]${RESET} $*"; }
info() { echo -e "${B}[ INFO ]${RESET} $*"; }
warn() { echo -e "${Y}[ WARN ]${RESET} $*"; }
fail() { echo -e "${R}[ FAIL ]${RESET} $*"; exit 1; }
step() {
    echo ""
    echo -e "${G}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo -e "${W}  $*${RESET}"
    echo -e "${G}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
}

banner() {
cat << 'EOF'

  ██╗██╗  ██╗ █████╗      ██╗ ██████╗ ██╗  ██╗██╗    ██╗
  ██║██║ ██╔╝██╔══██╗     ██║██╔═══██╗██║ ██╔╝██║    ██║
  ██║█████╔╝ ███████║     ██║██║   ██║█████╔╝ ██║ █╗ ██║
  ██║██╔═██╗ ██╔══██║██   ██║██║   ██║██╔═██╗ ██║███╗██║
  ██║██║  ██╗██║  ██║╚█████╔╝╚██████╔╝██║  ██╗╚███╔███╔╝
  ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚════╝  ╚═════╝ ╚═╝  ╚═╝ ╚══╝╚══╝

     ikajokw OS Builder — based on Debian
     Debian → strip → rebrand → ISO
     เวลาประมาณ 10-20 นาที
EOF
echo ""
}

# ── CHECK ────────────────────────────────────────────────────
check_root() {
    [[ $EUID -eq 0 ]] || fail "รัน: sudo bash build.sh"
}

check_deps() {
    step "Step 1/6 — Installing build tools"
    apt-get update -qq > "${LOG_DIR}/apt-update.log" 2>&1
    apt-get install -y \
        debootstrap \
        squashfs-tools \
        xorriso \
        grub-pc-bin \
        grub-efi-amd64-bin \
        mtools \
        cpio \
        gzip \
        > "${LOG_DIR}/apt-install.log" 2>&1 \
        || fail "ติดตั้ง tools ไม่สำเร็จ — ดู ${LOG_DIR}/apt-install.log"
    log "Build tools ready"

    local FREE_GB
    FREE_GB=$(df /tmp --output=avail -BG | tail -1 | tr -d 'G ')
    [[ ${FREE_GB} -lt 4 ]] \
        && warn "พื้นที่เหลือ ${FREE_GB}GB — แนะนำ 5GB+" \
        || log "Disk space: ${FREE_GB}GB OK"
}

# ── PREPARE ──────────────────────────────────────────────────
prepare_dirs() {
    step "Step 2/6 — Preparing directories"
    rm -rf "${BUILD_ROOT}"
    mkdir -p "${ROOTFS}" "${ISO_DIR}/boot/grub" "${ISO_DIR}/live" "${LOG_DIR}"
    log "Directories ready"
}

# ── DEBOOTSTRAP ──────────────────────────────────────────────
run_debootstrap() {
    step "Step 3/6 — Bootstrapping Debian (this takes ~5-10 min)"
    info "Downloading Debian bookworm minimal..."
    debootstrap \
        --arch=amd64 \
        --variant=minbase \
        --include=linux-image-amd64,grub-pc,bash,coreutils,util-linux,\
procps,net-tools,iproute2,iputils-ping,curl,wget,nano,vim-tiny,\
htop,openssh-server,ca-certificates,locales,systemd,dbus \
        bookworm \
        "${ROOTFS}" \
        http://deb.debian.org/debian \
        > "${LOG_DIR}/debootstrap.log" 2>&1 \
        || fail "debootstrap failed — ดู ${LOG_DIR}/debootstrap.log"
    log "Debian base installed: $(du -sh ${ROOTFS} | cut -f1)"
}

# ── REBRAND → ikajokw ────────────────────────────────────────
rebrand_as_ikajokw() {
    step "Step 4/6 — Rebranding Debian → ikajokw OS"

    # Mount pseudo-fs for chroot
    mount --bind /proc    "${ROOTFS}/proc"
    mount --bind /sys     "${ROOTFS}/sys"
    mount --bind /dev     "${ROOTFS}/dev"
    mount --bind /dev/pts "${ROOTFS}/dev/pts"
    trap "umount -lf ${ROOTFS}/dev/pts ${ROOTFS}/dev ${ROOTFS}/proc ${ROOTFS}/sys 2>/dev/null || true" EXIT

    # ── Hostname ─────────────────────────────────────────────
    info "Setting hostname → ${OS_NAME}"
    echo "${OS_NAME}" > "${ROOTFS}/etc/hostname"
    cat > "${ROOTFS}/etc/hosts" << EOF
127.0.0.1   localhost
127.0.1.1   ${OS_NAME}
::1         localhost ip6-localhost ip6-loopback
EOF

    # ── OS Identity ───────────────────────────────────────────
    info "Writing OS identity..."
    cat > "${ROOTFS}/etc/os-release" << EOF
NAME="${OS_NAME} OS"
VERSION="${OS_VERSION}"
ID=ikajokw
ID_LIKE=debian
PRETTY_NAME="${OS_NAME} OS ${OS_VERSION} (Debian base)"
VERSION_CODENAME=ikajokw
HOME_URL="https://github.com/ikajokw"
SUPPORT_URL="https://github.com/ikajokw"
BUG_REPORT_URL="https://github.com/ikajokw/issues"
EOF

    # ── Remove Debian branding ────────────────────────────────
    info "Removing Debian branding..."
    chroot "${ROOTFS}" /bin/bash -c "
        apt-get remove -y --purge \
            base-files debian-archive-keyring 2>/dev/null || true
        apt-get autoremove -y 2>/dev/null || true
        apt-get clean 2>/dev/null || true
        rm -rf /var/lib/apt/lists/*
    " > "${LOG_DIR}/debrand.log" 2>&1 || true

    # ── MOTD ──────────────────────────────────────────────────
    info "Writing MOTD..."
    rm -f "${ROOTFS}/etc/motd" "${ROOTFS}/etc/motd.d/"* 2>/dev/null || true
    cat > "${ROOTFS}/etc/motd" << 'MOTD'

  ██╗██╗  ██╗ █████╗      ██╗ ██████╗ ██╗  ██╗██╗    ██╗
  ██║██║ ██╔╝██╔══██╗     ██║██╔═══██╗██║ ██╔╝██║    ██║
  ██║█████╔╝ ███████║     ██║██║   ██║█████╔╝ ██║ █╗ ██║
  ██║██╔═██╗ ██╔══██║██   ██║██║   ██║██╔═██╗ ██║███╗██║
  ██║██║  ██╗██║  ██║╚█████╔╝╚██████╔╝██║  ██╗╚███╔███╔╝
  ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚════╝  ╚═════╝ ╚═╝  ╚═╝ ╚══╝╚══╝

  Welcome to ikajokw OS v1.0.0
  Kernel: Linux  |  Base: Debian bookworm
  Type 'sysinfo' for system info.

MOTD

    # ── ikajokw prompt ────────────────────────────────────────
    info "Setting ikajokw\$ prompt..."
    cat > "${ROOTFS}/etc/profile.d/ikajokw.sh" << 'EOF'
#!/bin/bash
# ikajokw OS profile

export PS1='\[\033[01;32m\]ikajokw\$\[\033[00m\] '
export TERM=xterm-256color
export LANG=C.UTF-8

# Aliases
alias ls='ls --color=auto'
alias ll='ls -la --color=auto'
alias la='ls -A --color=auto'
alias grep='grep --color=auto'
alias cls='clear'
alias ..='cd ..'
alias df='df -h'
alias free='free -h'
alias ip='ip --color=auto'

# sysinfo function
sysinfo() {
    echo ""
    echo -e "  \033[1;32mHostname\033[0m : $(hostname)"
    echo -e "  \033[1;32mOS      \033[0m : $(cat /etc/os-release | grep PRETTY_NAME | cut -d= -f2 | tr -d '\"')"
    echo -e "  \033[1;32mKernel  \033[0m : $(uname -r)"
    echo -e "  \033[1;32mUptime  \033[0m : $(uptime -p)"
    echo -e "  \033[1;32mCPU     \033[0m : $(grep 'model name' /proc/cpuinfo | head -1 | cut -d: -f2 | xargs)"
    echo -e "  \033[1;32mMemory  \033[0m : $(free -h | grep Mem | awk '{print $3"/"$2}')"
    echo -e "  \033[1;32mDisk    \033[0m : $(df -h / | tail -1 | awk '{print $3"/"$2" ("$5")"}')"
    echo -e "  \033[1;32mIP      \033[0m : $(ip route get 1 2>/dev/null | grep -oP 'src \K\S+' || echo 'N/A')"
    echo ""
}
EOF
    chmod +x "${ROOTFS}/etc/profile.d/ikajokw.sh"

    # ── /root/.bashrc ─────────────────────────────────────────
    cat > "${ROOTFS}/root/.bashrc" << 'EOF'
# ikajokw OS
source /etc/profile.d/ikajokw.sh 2>/dev/null
EOF

    # ── /etc/issue ────────────────────────────────────────────
    echo "ikajokw OS ${OS_VERSION} \n \l" > "${ROOTFS}/etc/issue"
    echo "ikajokw OS ${OS_VERSION}" > "${ROOTFS}/etc/issue.net"

    # ── root password ─────────────────────────────────────────
    info "Setting root password → ikajokw"
    chroot "${ROOTFS}" /bin/bash -c "echo 'root:ikajokw' | chpasswd"

    # ── Auto-login on tty1 ────────────────────────────────────
    info "Configuring auto-login on tty1..."
    mkdir -p "${ROOTFS}/etc/systemd/system/getty@tty1.service.d"
    cat > "${ROOTFS}/etc/systemd/system/getty@tty1.service.d/autologin.conf" << 'EOF'
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin root --noclear %I $TERM
EOF

    # ── Enable networking ─────────────────────────────────────
    info "Configuring network (DHCP)..."
    cat > "${ROOTFS}/etc/network/interfaces" << 'EOF'
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet dhcp

auto ens3
iface ens3 inet dhcp

auto enp0s3
iface enp0s3 inet dhcp
EOF

    # ── Locale ────────────────────────────────────────────────
    chroot "${ROOTFS}" /bin/bash -c "
        echo 'en_US.UTF-8 UTF-8' >> /etc/locale.gen
        locale-gen 2>/dev/null || true
        update-locale LANG=en_US.UTF-8 2>/dev/null || true
    " > "${LOG_DIR}/locale.log" 2>&1 || true

    # ── Strip Debian packages list ────────────────────────────
    info "Cleaning up..."
    rm -rf "${ROOTFS}/var/lib/apt/lists/"*
    rm -rf "${ROOTFS}/var/cache/apt/"*.bin
    rm -rf "${ROOTFS}/usr/share/doc/"*
    rm -rf "${ROOTFS}/usr/share/man/"*
    rm -rf "${ROOTFS}/usr/share/locale/"*
    rm -rf "${ROOTFS}/tmp/"*

    # Unmount pseudo-fs
    umount -lf "${ROOTFS}/dev/pts" "${ROOTFS}/dev" \
               "${ROOTFS}/proc"    "${ROOTFS}/sys" 2>/dev/null || true
    trap - EXIT

    log "Rebranding complete"
}

# ── BUILD ISO ────────────────────────────────────────────────
build_iso() {
    step "Step 5/6 — Building SquashFS + ISO"

    # Copy kernel & initrd from rootfs
    info "Copying kernel..."
    local VMLINUZ
    local INITRD
    VMLINUZ=$(find "${ROOTFS}/boot" -name "vmlinuz-*" | sort -V | tail -1)
    INITRD=$(find "${ROOTFS}/boot" -name "initrd.img-*" | sort -V | tail -1)

    [[ -z "${VMLINUZ}" ]] && fail "ไม่พบ kernel ใน ${ROOTFS}/boot — ตรวจสอบ debootstrap log"

    cp "${VMLINUZ}" "${ISO_DIR}/boot/vmlinuz"
    cp "${INITRD}"  "${ISO_DIR}/boot/initrd.img"
    log "Kernel: $(basename ${VMLINUZ})"
    log "Initrd: $(basename ${INITRD})"

    # SquashFS
    info "Compressing rootfs (SquashFS xz) — อาจใช้เวลาสักครู่..."
    mksquashfs "${ROOTFS}" "${ISO_DIR}/live/filesystem.squashfs" \
        -comp xz -b 1M -noappend \
        -e "${ROOTFS}/proc" \
        -e "${ROOTFS}/sys" \
        -e "${ROOTFS}/dev" \
        > "${LOG_DIR}/squashfs.log" 2>&1
    log "SquashFS: $(du -sh ${ISO_DIR}/live/filesystem.squashfs | cut -f1)"

    # Manifest
    chroot "${ROOTFS}" dpkg-query -W --showformat='${Package} ${Version}\n' \
        > "${ISO_DIR}/live/filesystem.manifest" 2>/dev/null || true

    # GRUB config
    cat > "${ISO_DIR}/boot/grub/grub.cfg" << EOF
set default=0
set timeout=5
set color_normal=green/black
set color_highlight=black/green

menuentry "${OS_NAME} OS ${OS_VERSION}" {
    linux  /boot/vmlinuz boot=live quiet loglevel=3 console=tty1 \
           hostname=${OS_NAME}
    initrd /boot/initrd.img
}

menuentry "${OS_NAME} OS (verbose)" {
    linux  /boot/vmlinuz boot=live loglevel=7 console=tty1 \
           hostname=${OS_NAME}
    initrd /boot/initrd.img
}
EOF

    # ISO metadata
    cat > "${ISO_DIR}/.disk/info" << EOF
${OS_NAME} OS ${OS_VERSION} "${OS_ARCH}" - Release $(date +%Y%m%d)
EOF
    mkdir -p "${ISO_DIR}/.disk"
    echo "${OS_NAME} OS ${OS_VERSION}" > "${ISO_DIR}/.disk/info"

    # Build ISO
    info "Building bootable ISO with grub-mkrescue..."
    grub-mkrescue \
        -o "${OUTPUT}" \
        "${ISO_DIR}" \
        --modules="normal iso9660 linux ext2 squash4 loopback search" \
        > "${LOG_DIR}/grub.log" 2>&1 \
        || fail "grub-mkrescue failed — ดู ${LOG_DIR}/grub.log"

    log "ISO built: $(du -sh ${OUTPUT} | cut -f1)"
}

# ── VERIFY ───────────────────────────────────────────────────
verify_iso() {
    step "Step 6/6 — Verifying ISO"
    [[ -f "${OUTPUT}" ]] || fail "ISO file not found!"
    local SIZE
    SIZE=$(du -sh "${OUTPUT}" | cut -f1)
    log "ISO verified: ${OUTPUT} (${SIZE})"
    # Generate SHA256
    sha256sum "${OUTPUT}" > "${OUTPUT}.sha256"
    log "Checksum: $(cat ${OUTPUT}.sha256 | cut -d' ' -f1)"
}

# ── SUMMARY ──────────────────────────────────────────────────
print_summary() {
    local MIN=$(( SECONDS / 60 ))
    echo ""
    echo -e "${G}╔══════════════════════════════════════════════════════╗${RESET}"
    echo -e "${G}║          ikajokw OS Build Complete! ✓                ║${RESET}"
    echo -e "${G}╚══════════════════════════════════════════════════════╝${RESET}"
    echo ""
    echo -e "  ISO      : ${Y}${OUTPUT}${RESET}"
    echo -e "  Checksum : ${Y}${OUTPUT}.sha256${RESET}"
    echo -e "  Size     : $(du -sh ${OUTPUT} | cut -f1)"
    echo -e "  Time     : ~${MIN} minutes"
    echo -e "  Base     : Debian bookworm"
    echo ""
    echo -e "${W}  Flash ลง USB:${RESET}"
    echo -e "  ${DIM}sudo dd if=${OUTPUT} of=/dev/sdX bs=4M status=progress && sync${RESET}"
    echo ""
    echo -e "${W}  หรือใช้ Rufus / Ventoy / Balena Etcher (Windows/Mac)${RESET}"
    echo ""
    echo -e "${W}  ทดสอบด้วย QEMU (ไม่ต้อง USB):${RESET}"
    echo -e "  ${DIM}qemu-system-x86_64 -m 1G -cdrom ${OUTPUT} -boot d -enable-kvm${RESET}"
    echo ""
    echo -e "${W}  Boot login:${RESET}"
    echo -e "  ${DIM}auto-login as root  (password: ikajokw)${RESET}"
    echo -e "  ${DIM}prompt: ikajokw\$${RESET}"
    echo ""
    echo -e "  Build logs: ${DIM}${LOG_DIR}/${RESET}"
    echo ""
}

cleanup_on_fail() {
    umount -lf "${ROOTFS}/dev/pts" "${ROOTFS}/dev" \
               "${ROOTFS}/proc" "${ROOTFS}/sys" 2>/dev/null || true
    echo -e "\n${R}[ FAIL ] Build failed!${RESET} ดู logs ใน ${LOG_DIR}/"
    ls "${LOG_DIR}/" 2>/dev/null || true
}
trap cleanup_on_fail ERR

# ── MAIN ─────────────────────────────────────────────────────
main() {
    banner
    mkdir -p "${LOG_DIR}"
    check_root
    check_deps
    prepare_dirs
    run_debootstrap
    rebrand_as_ikajokw
    build_iso
    verify_iso
    print_summary
}

main "$@"
