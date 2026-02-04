# Rockchip RK3566 quad core 4/8GB RAM SoC WIFI/BT eMMC USB2 USB3 NVMe PCIe GbE HDMI SPI
BOARD_NAME="Orange Pi 3B"
BOARD_VENDOR="xunlong"
BOARDFAMILY="rk35xx"
BOARD_MAINTAINER=""
BOOTCONFIG="orangepi-3b-rk3566_defconfig"
BOOT_SOC="rk3566"
KERNEL_TARGET="vendor,vendor-rt,edge"
FULL_DESKTOP="yes"
BOOT_LOGO="desktop"
IMAGE_PARTITION_TABLE="gpt"
BOOT_SCENARIO="spl-blobs"
BOOT_SUPPORT_SPI="yes"
BOOT_SPI_RKSPI_LOADER="yes"

# Override family config for this board; let's avoid conditionals in family config.
function post_family_config__orangepi3b_use_mainline_uboot() {
	display_alert "$BOARD" "Using mainline U-Boot for $BOARD / $BRANCH" "info"

	declare -g BOOTSOURCE="https://github.com/u-boot/u-boot.git"
	declare -g BOOTBRANCH="tag:v2024.10"
	declare -g BOOTPATCHDIR="v2024.10"
	declare -g BOOTDELAY=1

	declare -g UBOOT_TARGET_MAP="BL31=${RKBIN_DIR}/${BL31_BLOB} ROCKCHIP_TPL=${RKBIN_DIR}/${DDR_BLOB};;u-boot-rockchip.bin u-boot-rockchip-spi.bin u-boot.itb idbloader.img idbloader-spi.img"
	unset uboot_custom_postprocess write_uboot_platform write_uboot_platform_mtd # disable stuff from rockchip64_common; we're using binman here which does all the work already

	# Just use the binman-provided u-boot-rockchip.bin, which is ready-to-go
	function write_uboot_platform() {
		dd if=${1}/u-boot-rockchip.bin of=${2} bs=32k seek=1 conv=fsync
	}

	# Smarter/faster/better to-spi writer using flashcp (hopefully with --partition), using the binman-provided 'u-boot-rockchip-spi.bin'
	function write_uboot_platform_mtd() {
		declare -a extra_opts_flashcp=("--verbose")
		if flashcp -h | grep -q -e '--partition'; then
			echo "Confirmed flashcp supports --partition -- read and write only changed blocks." >&2
			extra_opts_flashcp+=("--partition")
		else
			echo "flashcp does not support --partition, will write full SPI flash blocks." >&2
		fi
		flashcp "${extra_opts_flashcp[@]}" "${1}/u-boot-rockchip-spi.bin" /dev/mtd0
	}
}

function post_family_tweaks_bsp__orangepi3b() {
	display_alert "$BOARD" "Installing orangepi3b-sprd-bluetooth.service" "info"

	# Bluetooth on orangepi3b board is handled by a Spreadtrum (sprd) chip and requires
	# a custom hciattach_opi binary, plus a systemd service to run it at boot time
	install -m 755 $SRC/packages/bsp/rk3399/hciattach_opi $destination/usr/bin
	install -m 755 $SRC/packages/bsp/orangepi3b/orangepi3b-sprd-bluetooth $destination/usr/bin/
	cp $SRC/packages/bsp/orangepi3b/orangepi3b-sprd-bluetooth.service $destination/lib/systemd/system/

	display_alert "$BOARD" "Applying low-latency audio and RTP tuning" "info"

	mkdir -p $destination/etc/security/limits.d $destination/etc/sysctl.d $destination/etc/modprobe.d
	cat <<'EOF' > $destination/etc/security/limits.d/95-audio-rt.conf
@audio   -  rtprio     95
@audio   -  memlock    unlimited
EOF

	cat <<'EOF' > $destination/etc/sysctl.d/99-audio-rt.conf
net.core.rmem_default = 1048576
net.core.rmem_max = 16777216
net.core.wmem_default = 1048576
net.core.wmem_max = 16777216
net.core.netdev_max_backlog = 5000
net.ipv4.udp_mem = 4096 87380 16777216
net.ipv4.udp_rmem_min = 262144
net.ipv4.udp_wmem_min = 262144
kernel.sched_rt_runtime_us = -1
EOF

	cat <<'EOF' > $destination/etc/modprobe.d/alsa-lowlatency.conf
options snd_pcm prealloc_buffer_size_kb=2048
EOF

	return 0
}

function post_family_tweaks__orangepi3b_enable_services() {
	display_alert "$BOARD" "Enabling orangepi3b-sprd-bluetooth.service" "info"
	chroot_sdcard systemctl enable orangepi3b-sprd-bluetooth.service
	return 0
}

function post_family_tweaks__orangepi3b_naming_audios() {
	display_alert "$BOARD" "Renaming orangepi3b audios" "info"

	mkdir -p $SDCARD/etc/udev/rules.d/
	echo 'SUBSYSTEM=="sound", ENV{ID_PATH}=="platform-hdmi-sound", ENV{SOUND_DESCRIPTION}="HDMI Audio"' > $SDCARD/etc/udev/rules.d/90-naming-audios.rules
	echo 'SUBSYSTEM=="sound", ENV{ID_PATH}=="platform-rk809-sound", ENV{SOUND_DESCRIPTION}="RK809 Audio"' >> $SDCARD/etc/udev/rules.d/90-naming-audios.rules # vendor dts
	echo 'SUBSYSTEM=="sound", ENV{ID_PATH}=="platform-sound", ENV{SOUND_DESCRIPTION}="RK809 Audio"' >> $SDCARD/etc/udev/rules.d/90-naming-audios.rules       # mainline dts

	return 0
}
