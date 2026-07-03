# Rockchip RK3576 octa-core (4xA72+4xA53) handheld, 5.5" 1080p AMOLED,
# Mali-G52 MC3, SPI-MCU gamepad, eMMC/microSD, WiFi/BT, USB-C DP alt-mode
BOARD_NAME="Anbernic RG Vita Pro"
BOARD_VENDOR="Anbernic"
BOARDFAMILY="rk35xx"
BOOTCONFIG="generic-rk3576_defconfig"
BOARD_MAINTAINER="crackerjacques"
INTRODUCED="2026"
KERNEL_TARGET="edge"
KERNEL_TEST_TARGET="edge"

PACKAGE_LIST_BOARD+=" python3-evdev python3-libevdev xinput"

BOOT_FDT_FILE="rockchip/rk3576-anbernic-rg-vita-pro.dtb"
BOOT_SCENARIO="spl-blobs"
SERIALCON="ttyS0" # DTS chosen: serial0 (uart0) @ 1500000n8
IMAGE_PARTITION_TABLE="gpt"

# The RG Vita's own vendor image ships DDR fwver v1.09 (ddr-v1.09-2f85f4b2d4),
# so pin v1.09 here - the family default (v1.08) may not init this board's RAM.
DDR_BLOB="rk35/rk3576_ddr_lp4_2112MHz_lp5_2736MHz_v1.09.bin"

# The case is glued shut (no accessible debug UART), so bring up a USB-gadget
# serial console on the USB-C/OTG port: if the kernel boots, the device shows
# up as a USB serial device on a host PC (/dev/ttyACMx or /dev/cu.usbmodem*)
# and gives a login even with no display driver yet. Same trick as anbernic-rg-ds.
MODULES="g_serial"

# Default mixer state (captured on HW): es8388 OUT2 -> aw87391 amps ->
# "Internal Speakers" and OUT1 -> hp amp -> "Headphones" both enabled, so
# audio works out of the box on speakers and the headphone jack alike.
ASOUND_STATE="asound.state.anbernic-rg-vita-pro"

# Mainline U-Boot with the generic RK3576 defconfig (no bespoke U-Boot board
# port needed). The family's boot_merger/spl-blobs path supplies the rk3576
# DDR (pinned v1.08), BL31, usbplug and - crucially - the SD-card boost, which
# the RK3576 BootROM needs to load from SD. Mirrors nanopi-r76s.
function post_family_config__anbernic_rg_vita_pro_use_mainline_uboot() {
	display_alert "$BOARD" "mainline U-Boot v2026.04 (generic-rk3576) for $BOARD / $BRANCH" "info"

	declare -g BOOTDELAY=1
	declare -g BOOTSOURCE="https://github.com/u-boot/u-boot.git"
	declare -g BOOTBRANCH="tag:v2026.04"
	declare -g BOOTPATCHDIR="v2026.04"

	# boot_merger (uboot_custom_postprocess) injects the rk3576 SD boost;
	# binman's u-boot-rockchip.bin lacks it, so emit idbloader.img + u-boot.itb
	# and let the family postprocess assemble the loader.
	declare -g UBOOT_TARGET_MAP="BL31=${RKBIN_DIR}/${BL31_BLOB} ROCKCHIP_TPL=${RKBIN_DIR}/${DDR_BLOB};;idbloader.img u-boot.itb"

	unset write_uboot_platform write_uboot_platform_mtd

	function write_uboot_platform() {
		dd "if=$1/idbloader.img" "of=$2" seek=64    conv=notrunc status=none
		dd "if=$1/u-boot.itb"    "of=$2" seek=16384 conv=notrunc status=none
	}
}

# vita-jack-switch (bsp payload) watches the headphone-jack input device and
# mutes the internal speakers while headphones are plugged in.
PACKAGE_LIST_BOARD+=" python3-evdev alsa-utils"

# USB-gadget serial console login on the USB-C/OTG port (no physical UART),
# plus the headphone-jack speaker switch service shipped via bsp-cli.
function post_family_tweaks__anbernic_rg_vita_pro_gadget_console() {
	display_alert "$BOARD" "enabling ttyGS0 USB-gadget serial console + jack switch" "info"
	mkdir -p "${SDCARD}/etc/systemd/system/getty.target.wants"
	ln -sf /lib/systemd/system/serial-getty@.service \
		"${SDCARD}/etc/systemd/system/getty.target.wants/serial-getty@ttyGS0.service"
	mkdir -p "${SDCARD}/etc/systemd/system/multi-user.target.wants"
	ln -sf /etc/systemd/system/vita-jack-switch.service \
		"${SDCARD}/etc/systemd/system/multi-user.target.wants/vita-jack-switch.service"
}

# Upstream Linux DTS aliases: mmc0 = &sdhci (eMMC), mmc1 = &sdmmc (SD),
# mmc2 = &sdio. Boot SD first so a flashed card takes precedence over eMMC.
function pre_config_uboot_target__anbernic_rg_vita_pro_boot_order() {
	declare -a rockchip_uboot_targets=("mmc1" "mmc0" "nvme" "usb" "pxe" "dhcp")
	display_alert "u-boot for ${BOARD}/${BRANCH}" "boot order '${rockchip_uboot_targets[*]}'" "info"
	sed -i -e "s/#define BOOT_TARGETS.*/#define BOOT_TARGETS \"${rockchip_uboot_targets[*]}\"/" include/configs/rockchip-common.h
	regular_git diff -u include/configs/rockchip-common.h || true
}
