#!/usr/bin/env bash
# build-archiso.sh
# YAMLでカスタム可能な Arch Linux ISO ビルドスクリプト（UEFI対応）
# 依存: archiso, yq (v4), git（relengコピーが必要な場合）
set -euo pipefail
rm -rf work/ out/


# ===== 設定 =====
WORKDIR="$PWD/work"
ISO_ROOT="$WORKDIR/iso"
AIROOTFS="$WORKDIR/airootfs"
ISO_NAME="frankos"
ISO_LABEL="FRANK_LIVE"
ISO_VERSION="$(date +%Y.%m.%d)"
OUTPUT="$PWD/out"
ARCH="x86_64"

# ===== 前準備 =====
echo "[*] 作業ディレクトリを初期化..."
rm -rf "$WORKDIR" "$OUTPUT"
mkdir -p "$AIROOTFS" "$ISO_ROOT" "$OUTPUT"

# ===== ベースシステム作成 =====
echo "[*] ベースシステムを pacstrap でインストール..."
pacstrap  "$AIROOTFS" base linux linux-firmware vim networkmanager archiso

# ===== 設定ファイル追加 =====
echo "[*] 基本設定を投入..."
echo "myarch" > "$AIROOTFS/etc/hostname"
cat <<EOF > "$AIROOTFS/etc/vconsole.conf"
KEYMAP=us
FONT=Lat2-Terminus16
EOF

cat <<EOF > "$AIROOTFS/etc/locale.gen"
en_US.UTF-8 UTF-8
EOF



arch-chroot "$AIROOTFS" locale-gen
mkdir -p "$AIROOTFS/etc/pacman.d"
cp /etc/pacman.conf "$AIROOTFS/etc/"
cp /etc/pacman.d/mirrorlist "$AIROOTFS/etc/pacman.d/"



# chroot先で archiso パッケージをインストール

# archisoパッケージ導入とHOOKS設定


sed -i 's/^HOOKS=.*/HOOKS=(base udev archiso block filesystems keyboard fsck)/' \
    "$AIROOTFS/etc/mkinitcpio.conf"

arch-chroot "$AIROOTFS" mkinitcpio -P || true









# root パスワード設定（例: "root"）
echo "root:root" | arch-chroot "$AIROOTFS" chpasswd

# systemdサービス有効化
arch-chroot "$AIROOTFS" systemctl enable NetworkManager

# ===== カスタムファイル追加例 =====
mkdir -p "$AIROOTFS/root"
echo "Welcome to MyArch Live!" > "$AIROOTFS/root/README.txt"

# ===== squashfs 作成 =====
echo "[*] squashfs イメージ作成..."
mkdir -p "$ISO_ROOT/arch"
mksquashfs "$AIROOTFS" "$ISO_ROOT/arch/rootfs.sfs" \
  -comp zstd -Xcompression-level 1


# ===== ブートローダー構築 (systemd-boot UEFI) =====
echo "[*] EFI ブートローダー準備..."
# 1. EFI用FATイメージ作成
dd if=/dev/zero of="$ISO_ROOT/efiboot.img" bs=1M count=200
mkfs.vfat "$ISO_ROOT/efiboot.img"


# 2. マウントしてファイルコピー
mkdir mnt_esp


# 2. マウントしてファイルコピー
sudo mount "$ISO_ROOT/efiboot.img" mnt_esp

mkdir -p mnt_esp/EFI/BOOT
cp /usr/lib/systemd/boot/efi/systemd-bootx64.efi mnt_esp/EFI/BOOT/BOOTX64.EFI

# loader.conf と arch.conf を配置
mkdir -p mnt_esp/loader/entries
cat <<EOF | sudo tee mnt_esp/loader/loader.conf
default  arch
timeout  3
console-mode max
editor   no
EOF

cat <<EOF | sudo tee mnt_esp/loader/entries/arch.conf
title   FrankOS Live (${ISO_VERSION})
linux   /vmlinuz-linux
initrd  /initramfs-linux.img
options archisobasedir=arch archisolabel=${ISO_LABEL}
EOF

sudo umount mnt_esp
rmdir mnt_esp

# カーネルと initramfs を ISOルートにコピー
cp "$AIROOTFS/boot/vmlinuz-linux" "$ISO_ROOT/"
cp "$AIROOTFS/boot/initramfs-linux.img" "$ISO_ROOT/"

# ===== ISO 作成 =====
echo "[*] ISO イメージ生成..."
xorriso -as mkisofs \
  -iso-level 3 \
  -full-iso9660-filenames \
  -volid "${ISO_LABEL}" \
  -eltorito-alt-boot \
  -e efiboot.img \
  -no-emul-boot \
  -isohybrid-gpt-basdat \
  -output "${OUTPUT}/${ISO_NAME}-${ISO_VERSION}-${ARCH}.iso" \
  "$ISO_ROOT"

echo "[*] 完了! 出力: ${OUTPUT}/${ISO_NAME}-${ISO_VERSION}-${ARCH}.iso"
