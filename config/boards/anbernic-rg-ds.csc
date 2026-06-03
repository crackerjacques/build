# Anbernic RG DS - Rockchip RK3568 quad-core, dual 4" 640x480 handheld
BOARD_NAME="Anbernic RG DS"
BOARD_VENDOR="Anbernic"
BOARDFAMILY="rk35xx"
BOARD_MAINTAINER="jackheinlein"
INTRODUCED="2025"
KERNEL_TARGET="edge"
KERNEL_TEST_TARGET="edge"

BOOT_FDT_FILE="rockchip/rk3568-anbernic-rg-ds.dtb"
BOOT_SCENARIO="spl-blobs"
SERIALCON="ttyS2" # RG DS serial console: ttyS2 @ 1500000
BOOTFS_TYPE="fat"
IMAGE_PARTITION_TABLE="gpt"

# rkbin blobs are not bundled in this repo. The bl31 v1.45 / ddr 1056MHz v1.23
# this board needs are not present in armbian/rkbin, so point the rkbin-tools
# fetch at Rockchip's official rkbin and reference its bin/rk35 layout. They are
# downloaded at build time (no binaries committed here).
declare -g RKBIN_GIT_URL="https://github.com/rockchip-linux/rkbin"
BL31_BLOB="bin/rk35/rk3568_bl31_v1.45.elf"
DDR_BLOB="bin/rk35/rk3568_ddr_1056MHz_v1.23.bin"

# Mainline U-Boot (quartz64-a-rk3566 defconfig + rk3568 DDR v1.23 / BL31 v1.45)
function post_family_config__anbernic_rg_ds_mainline_uboot() {
	[[ "${BOARD}" == "anbernic-rg-ds" ]] || return 0
	display_alert "$BOARD" "mainline U-Boot v2026.01 (quartz64-a-rk3566 + rk3568 DDR v1.23)" "info"
	declare -g BOOTCONFIG="quartz64-a-rk3566_defconfig"
	declare -g BOOTSOURCE="https://github.com/u-boot/u-boot.git"
	declare -g BOOTBRANCH="tag:v2026.01"
	declare -g BOOTDIR="u-boot-${BOARD}"
	declare -g BOOTPATCHDIR="v2026.01"
	declare -g UBOOT_TARGET_MAP="BL31=${RKBIN_DIR}/${BL31_BLOB} ROCKCHIP_TPL=${RKBIN_DIR}/${DDR_BLOB};;u-boot-rockchip.bin"
	unset uboot_custom_postprocess write_uboot_platform write_uboot_platform_mtd
	function write_uboot_platform() {
		dd "if=$1/u-boot-rockchip.bin" "of=$2" bs=32k seek=1 conv=notrunc status=none
	}
}

# Enable the RG DS drivers (generic-dsi panel, rocknix single-ADC joypad, aw87391
# amplifier) and their dependencies. The drivers themselves are added in-tree by
# the board-rgds-* kernel patches.
function custom_kernel_config__anbernic_rg_ds() {
	[[ ! -f .config ]] && return 0

	kernel_config_set_m DRM_PANEL_GENERIC_DSI
	kernel_config_set_m JOYSTICK_ROCKNIX_SINGLEADC
	kernel_config_set_y IIO
	kernel_config_set_m ROCKCHIP_SARADC
	kernel_config_set_m SND_SOC_AW87391
	kernel_config_set_y USB_GADGET
	kernel_config_set_y USB_LIBCOMPOSITE
	kernel_config_set_y USB_CONFIGFS
	kernel_config_set_y USB_CONFIGFS_ACM
	kernel_config_set_y USB_G_SERIAL
	kernel_config_set_y USB_DWC3
	kernel_config_set_y USB_DWC3_OF_SIMPLE
}

# Dual-screen (X11): stack the two DSI panels DS-style (DSI-2 top/primary over
# DSI-1 bottom) and bind each gt911 touchscreen to its panel. xrandr/xinput are
# X11-only, so this is wired through an xdg autostart entry: it runs on desktop
# login and never fires on a CLI/tty (or Wayland) session.
function post_family_tweaks__anbernic_rg_ds_dualscreen() {
	[[ "${BOARD}" == "anbernic-rg-ds" ]] || return 0
	display_alert "$BOARD" "installing X11 dual-screen layout helper" "info"

	install -d "${SDCARD}/usr/bin" "${SDCARD}/etc/xdg/autostart"

	cat > "${SDCARD}/usr/bin/rgds-screen" <<- 'RGDS_SCREEN'
		#!/bin/bash
		# Anbernic RG DS: DS-style dual-screen layout for X11.
		# Stacks DSI-2 (top, primary) over DSI-1 (bottom) and maps each gt911
		# touchscreen (i2c controllers fe5c0000 / fe5e0000) to its own panel.
		sleep 2
		xrandr --output DSI-1 --pos 0x480
		xrandr --output DSI-2 --primary --pos 0x0
		DISP_A=DSI-2; DISP_B=DSI-1
		ev_for(){ readlink -f /dev/input/by-path/platform-$1.i2c*-event 2>/dev/null; }
		id_for(){ local w="$1" id n; for id in $(xinput list --id-only); do
		n=$(xinput list-props "$id" 2>/dev/null | grep -oP 'Device Node[^"]*"\K[^"]+')
		[ "$n" = "$w" ] && { echo "$id"; return; }; done; }
		A=$(id_for "$(ev_for fe5c0000)"); B=$(id_for "$(ev_for fe5e0000)")
		[ -n "$A" ] && xinput map-to-output "$A" "$DISP_A"
		[ -n "$B" ] && xinput map-to-output "$B" "$DISP_B"
	RGDS_SCREEN
	chroot_sdcard chmod +x /usr/bin/rgds-screen

	cat > "${SDCARD}/etc/xdg/autostart/rgds-screen.desktop" <<- 'RGDS_DESKTOP'
		[Desktop Entry]
		Type=Application
		Name=Anbernic RG DS dual-screen layout
		Comment=Stack the two DSI panels and map each touchscreen (X11 only)
		Exec=/usr/bin/rgds-screen
		NoDisplay=true
		X-GNOME-Autostart-enabled=true
	RGDS_DESKTOP
}
