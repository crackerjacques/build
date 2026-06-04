# Anbernic RG DS - Rockchip RK3568 quad-core, dual 4" 640x480 handheld
BOARD_NAME="Anbernic RG DS"
BOARD_VENDOR="Anbernic"
BOARDFAMILY="rk35xx"
BOOT_SOC="rk3568"
BOARD_MAINTAINER="crackerjacques"
INTRODUCED="2025"
KERNEL_TARGET="edge"
KERNEL_TEST_TARGET="edge"

PACKAGE_LIST_BOARD+=" python3-evdev python3-libevdev xinput"

BOOT_FDT_FILE="rockchip/rk3568-anbernic-rg-ds.dtb"
BOOT_SCENARIO="spl-blobs"
SERIALCON="ttyS2" # RG DS serial console: ttyS2 @ 1500000
BOOTFS_TYPE="fat"
IMAGE_PARTITION_TABLE="gpt"

# rk3568 DDR v1.23 / BL31 v1.45 (matches the ROCKNIX-proven bootloader on this
# board). Fetched from armbian/rkbin at build time; no binaries committed here.
BL31_BLOB="rk35/rk3568_bl31_v1.45.elf"
DDR_BLOB="rk35/rk3568_ddr_1056MHz_v1.23.bin"

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

# RG DS kernel options. Panel (jadard JD9365DA-H3) and input (adc-joystick) are
# already in mainline; only the aw87391 speaker amplifier driver is added in-tree
# by a board-rgds patch. Most of these may already be on in the rockchip64 edge
# config; set explicitly so the board is self-contained.
function custom_kernel_config__anbernic_rg_ds() {
	[[ ! -f .config ]] && return 0

	# Display: mainline jadard JD9365DA-H3 dual-DSI panels
	kernel_config_set_m DRM_PANEL_JADARD_JD9365DA_H3
	# Input: adc-joystick (via io-channel-mux + gpio-mux) and adc-keys
	kernel_config_set_m JOYSTICK_ADC
	kernel_config_set_m IIO_MUX
	kernel_config_set_m MUX_GPIO
	kernel_config_set_y MULTIPLEXER
	kernel_config_set_m KEYBOARD_ADC
	kernel_config_set_y IIO
	kernel_config_set_m ROCKCHIP_SARADC
	# Audio: aw87391 speaker amplifiers (driver added in-tree by board-rgds patch)
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

# Console + input helpers. ttyGS0 is the USB-C gadget serial console (this board
# has no easily accessible physical UART). pad2key maps the gamepad D-pad and the
# Select/Start/Home/North buttons to keyboard keys so the handheld is usable in a
# desktop without an external keyboard (evdev/uinput; works on X11 and Wayland).
# python3-evdev is pulled in via PACKAGE_LIST_BOARD.
function post_family_tweaks__anbernic_rg_ds_console_input() {
	[[ "${BOARD}" == "anbernic-rg-ds" ]] || return 0
	display_alert "$BOARD" "enabling ttyGS0 console + gamepad-to-keyboard" "info"

	# USB-gadget serial console login on the OTG port
	mkdir -p "${SDCARD}/etc/systemd/system/getty.target.wants"
	ln -sf /lib/systemd/system/serial-getty@.service \
		"${SDCARD}/etc/systemd/system/getty.target.wants/serial-getty@ttyGS0.service"

	# Gamepad / HOME buttons -> keyboard
	install -d "${SDCARD}/usr/bin"
	cat > "${SDCARD}/usr/bin/rgds-pad2key" <<'RGDS_PAD2KEY'
#!/usr/bin/env python3
# RG DS: gamepad/HOME buttons -> keyboard (evdev/uinput, X11/Wayland-safe).
# Reads every input device that emits a mapped BTN_* code (gpio gamepad keys AND
# the separate adc HOME key) and injects keyboard keys. Analog sticks untouched.
import time, select, evdev
from evdev import ecodes as e, UInput
MAP = {
    e.BTN_DPAD_UP: e.KEY_UP,     e.BTN_DPAD_DOWN: e.KEY_DOWN,
    e.BTN_DPAD_LEFT: e.KEY_LEFT, e.BTN_DPAD_RIGHT: e.KEY_RIGHT,
    e.BTN_SELECT: e.KEY_SPACE,
    e.BTN_START:  e.KEY_LEFTMETA,
    e.BTN_SOUTH:  e.KEY_ENTER,
    e.BTN_EAST:   e.KEY_ESC,
    e.BTN_WEST:   e.KEY_HOME,
}
# Chords: on a single press, tap the whole combo (modifiers down first, up last).
COMBO = {
    e.BTN_MODE:  (e.KEY_LEFTALT,  e.KEY_TAB),   # HOME -> Alt+Tab
    e.BTN_NORTH: (e.KEY_LEFTCTRL, e.KEY_F4),    # X -> Ctrl+F4
}
ALL = set(MAP) | set(COMBO)
def sources():
    out = {}
    for p in evdev.list_devices():
        try: d = evdev.InputDevice(p)
        except Exception: continue
        if d.name == "rgds-pad2key": continue
        if any(k in d.capabilities().get(e.EV_KEY, []) for k in ALL):
            out[d.fd] = d
    return out
devs = {}
while not devs:
    devs = sources()
    if not devs: time.sleep(2)
_keys = set(MAP.values())
for _seq in COMBO.values(): _keys.update(_seq)
ui = UInput({e.EV_KEY: sorted(_keys)}, name="rgds-pad2key")
while True:
    r, _, _ = select.select(devs, [], [])
    for fd in r:
        try: events = list(devs[fd].read())
        except OSError: continue
        for ev in events:
            if ev.type != e.EV_KEY: continue
            if ev.code in COMBO:
                if ev.value == 1:                 # press: tap the chord once
                    seq = COMBO[ev.code]
                    for k in seq: ui.write(e.EV_KEY, k, 1)
                    for k in reversed(seq): ui.write(e.EV_KEY, k, 0)
                    ui.syn()
            elif ev.code in MAP:
                ui.write(e.EV_KEY, MAP[ev.code], ev.value); ui.syn()
RGDS_PAD2KEY
	chroot_sdcard chmod +x /usr/bin/rgds-pad2key

	cat > "${SDCARD}/etc/systemd/system/rgds-pad2key.service" <<'RGDS_PAD2KEY_SVC'
[Unit]
Description=RG DS gamepad-to-keyboard remap
[Service]
ExecStart=/usr/bin/rgds-pad2key
Restart=always
RestartSec=2
[Install]
WantedBy=multi-user.target
RGDS_PAD2KEY_SVC
	mkdir -p "${SDCARD}/etc/systemd/system/multi-user.target.wants"
	ln -sf /etc/systemd/system/rgds-pad2key.service \
		"${SDCARD}/etc/systemd/system/multi-user.target.wants/rgds-pad2key.service"

	# Desktop toggle: turn the remap OFF before gaming (raw gamepad), ON for nav.
	cat > "${SDCARD}/usr/bin/rgds-pad2key-toggle" <<'RGDS_TOGGLE'
#!/bin/bash
if systemctl is-active --quiet rgds-pad2key; then
	systemctl stop rgds-pad2key && m="Pad-as-keyboard OFF — raw gamepad (for games)"
else
	systemctl start rgds-pad2key && m="Pad-as-keyboard ON — D-pad = keyboard"
fi
command -v notify-send >/dev/null 2>&1 && notify-send -t 1500 -i input-gaming "RG DS" "$m"
RGDS_TOGGLE
	chroot_sdcard chmod +x /usr/bin/rgds-pad2key-toggle

	# Allow the local desktop user to start/stop the service without a password.
	mkdir -p "${SDCARD}/etc/polkit-1/rules.d"
	cat > "${SDCARD}/etc/polkit-1/rules.d/49-rgds-pad2key.rules" <<'RGDS_POLKIT'
polkit.addRule(function(action, subject) {
	if (action.id == "org.freedesktop.systemd1.manage-units" &&
	    action.lookup("unit") == "rgds-pad2key.service" &&
	    subject.local && subject.active) {
		return polkit.Result.YES;
	}
});
RGDS_POLKIT

	# Application-menu launcher (the "icon").
	install -d "${SDCARD}/usr/share/applications"
	cat > "${SDCARD}/usr/share/applications/rgds-pad2key-toggle.desktop" <<'RGDS_LAUNCH'
[Desktop Entry]
Type=Application
Name=Toggle Pad-as-Keyboard
Comment=Gamepad-to-keyboard remap: off for games, on for desktop navigation
Exec=/usr/bin/rgds-pad2key-toggle
Icon=input-gaming
Categories=Settings;System;
RGDS_LAUNCH

	# Plain-text controls reference on the desktop (new users via /etc/skel).
	install -d "${SDCARD}/etc/skel/Desktop"
	cat > "${SDCARD}/etc/skel/Desktop/RG-DS-controls.txt" <<'RGDS_README'
Anbernic RG DS - controls
=========================

Gamepad -> keyboard (pad2key) for desktop navigation:
  D-pad        arrow keys
  Select       Space
  Start        Super / Meta
  A (South)    Enter
  B (East)     Esc
  Y (West)     Home
  X (North)    Ctrl+F4   (close window)
  HOME (Mode)  Alt+Tab   (switch window)

Analog sticks are NOT remapped - they always work as a gamepad.

Playing games?
  The injected keys (Esc, Ctrl+F4, Alt+Tab...) interfere with games.
  Turn the remap OFF before gaming, ON again for the desktop:

    OFF :  systemctl stop  rgds-pad2key
    ON  :  systemctl start rgds-pad2key

  Or use "Toggle Pad-as-Keyboard" in the application menu (no password).
RGDS_README
}
