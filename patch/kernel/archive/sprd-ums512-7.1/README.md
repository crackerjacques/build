# sprd-ums512 kernel patches

The kernel for this family is a fork of `beebono/linux-mainline-sprd` (branch
`rg-rotate`, rebased onto v7.1.13 with the two follow-up fixes that the bump
needed), which already carries the bulk of the UMS512/T618 support - DRM/DSI
panel, SC2355 Wi-Fi and Bluetooth, the DSP-mediated audio stack, the panfrost
match for Mali-G52, the sharkl5pro cpufreq driver and the AP-APB address
fixes. `KERNELBRANCH` pins an exact commit, so the tree is reproducible.

Only two patches live here, both because they touch mainline files and so have
somewhere upstream to go:

- `general-musb-gadget-*` - `drivers/usb/musb/musb_gadget.c`.
- `general-sprd-ums512-thermal-*` - the passive trip in
  `arch/arm64/boot/dts/sprd/ums512.dtsi`.

Everything else edits code that exists only in that fork - the board's own DTS,
and the Android-BSP vendor code under `sound/soc/sprd/vendor/`,
`drivers/net/wireless/unisoc/` and `drivers/net/wireless/sprdwcn/`. Carrying it
here would buy nothing, so it sits in the fork on branch `armbian-7113`, one
commit per fix, with the reasoning in each commit message:

- `3499f9e27872` arm64: dts: sprd: rg-rotate: do not claim the last DRAM page
- `4938dfdb24e1` arm64: dts: sprd: rg-rotate: wire the goodix touchscreen IRQ
- `cfe363369e9a` wifi: sc23xx: finish the scan when the interface goes down
- `2abce199e016` wifi: sc23xx: notify the firmware of the interface's IPv4 address
- `c860d2b63680` wifi: sc23xx: report the fallback MAC address as random
- `7d0a9897263a` ASoC: sprd: stop rejecting the 96 kHz DAC mode
- `1c1be21f3564` ASoC: sprd: wait for audcp rather than dropping the write
- `c5cf299d1e00` ASoC: sprd: step the non-interleaved DMA by the sample width
- `551e930a41c4` ASoC: sprd: resume the DMA channel instead of re-submitting
- `fab31c6d4bcd` ASoC: sprd: pcm-routing: mark the AIF widgets SND_SOC_NOPM
- `c24d34ba5cc6` ASoC: sprd: give the VBC path a buffer a desktop can feed
- `b062ca60cf25` ASoC: sprd: stop the DSP when the fast scene stops
- `05116cd18ad8` sprdwcn: only toggle pub_int on an actual power transition
- `f6d39ed145ba` sprdwcn: do not latch the firmware-partition fallback on a missing blob
- `19f8fc99365d` sprdwcn: fail fast when the BTWF firmware is missing

Three more changes were hypotheses the evidence did not support. They are kept
for the reasoning in their commit messages, on branch `rg-rotate-experiments` of
the same fork, and are not applied.
