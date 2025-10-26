FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

INTERNAL_DEVICE_KERNEL ?= "mmcblk?"

SRC_URI:append = " \
    file://balena-init-flasher-imx-secureboot \
    file://balena-init-flasher-imx-diskenc \
"

SKIP_SECUREBOOT_SETUP ?= "0"
BALENA_SKIP_SECUREBOOT_SETUP = "${@bb.utils.contains('DISTRO_FEATURES', 'osdev-image', "${SKIP_SECUREBOOT_SETUP}", '0', d)}"

do_install:append() {
	if [ "x${SIGN_API}" != "x" ]; then
		install -d ${D}${libexecdir}
		install -m 0755 ${WORKDIR}/balena-init-flasher-imx-secureboot ${D}${libexecdir}/balena-init-flasher-secureboot
		sed -i -e "s,@@BALENA_FINGERPRINT_FILENAME@@,${BALENA_FINGERPRINT_FILENAME},g" ${D}${libexecdir}/balena-init-flasher-secureboot
		sed -i -e "s,@@BALENA_NONENC_BOOT_LABEL@@,${BALENA_NONENC_BOOT_LABEL},g" ${D}${libexecdir}/balena-init-flasher-secureboot
		sed -i -e "s,@@BALENA_FINGERPRINT_EXT@@,${BALENA_FINGERPRINT_EXT},g" ${D}${libexecdir}/balena-init-flasher-secureboot
		install -m 0755 ${WORKDIR}/balena-init-flasher-imx-diskenc ${D}${libexecdir}/balena-init-flasher-diskenc
		echo "USE_LUKS=${BALENA_USE_LUKS}" >> ${D}/${sysconfdir}/resin-init-flasher.conf
		if [ "${SKIP_SECUREBOOT_SETUP}" != "0" ]; then
			bbwarn "SKIP_SECUREBOOT_SETUP is set - do not use in production"
			sed -i -e "s,@@BALENA_SKIP_SECUREBOOT_SETUP@@,true,g" ${D}${libexecdir}/balena-init-flasher-secureboot
		fi
		sed -i -e "s,@@BALENA_SKIP_SECUREBOOT_SETUP@@,false,g" ${D}${libexecdir}/balena-init-flasher-secureboot
	fi
}

RDEPENDS:${PN}:append = "${@oe.utils.conditional('SIGN_API','','',' os-helpers-sb gnupg',d)}"
