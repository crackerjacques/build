# Rockchip RK3506B triple core 512MB SoC EMMC USB2 (no WiFi/BT)
BOARD_NAME="Luckfox Lyra Ultra"
BOARD_VENDOR="luckfox"
BOARDFAMILY="rockchip"
BOOTCONFIG="luckfox-lyra-ultra-rk3506b_defconfig"
BOARD_MAINTAINER="crackerjacques"
INTRODUCED="2026"
KERNEL_TARGET="edge"
BOOT_FDT_FILE="rk3506b-luckfox-lyra-ultra.dtb"
BOOT_SCENARIO="spl-blobs"
IMAGE_PARTITION_TABLE="gpt"
BOOT_SOC="rk3506"
DDR_BLOB="rk35/rk3506b_ddr_750MHz_v1.06.bin"
SERIALCON="ttyS0"

function post_family_config__luckfox_lyra_ultra_boot() {
	# mainline console is uart0 = ttyS0 @ 0xff0a0000 (vendor used ttyFIQ0)
	declare -g BOOTSCRIPT="boot-rk3506-lyra.cmd:boot.cmd"
}
