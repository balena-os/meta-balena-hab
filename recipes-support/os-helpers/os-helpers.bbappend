FILESEXTRAPATHS:append := ":${THISDIR}/${PN}"

SRC_URI += " \
    file://os-helpers-sb \
"

RDEPENDS:${PN}-sb:prepend = "imx-misc-tools "

# For development use only - bypasses lock check
IS_SECURED_CHECK_SKIP ?= "0"
BALENA_IS_SECURED_CHECK_SKIP = "${@bb.utils.contains('DISTRO_FEATURES', 'osdev-image', "${IS_SECURED_CHECK_SKIP}", '0', d)}"

KERNEL_DEVICE_TREES = "${@' '.join(map(str, [os.path.basename(dt) for dt in d.getVar('KERNEL_DEVICETREE').split()]))}"

do_install:append() {
	install -m 0775 ${WORKDIR}/os-helpers-sb ${D}${libexecdir}
	sed -i -e "s,@@KERNEL_IMAGETYPE@@,${KERNEL_IMAGETYPE},g" ${D}${libexecdir}/os-helpers-sb
	sed -i -e "s,@@BALENA_IMAGE_FLAG_FILE@@,${BALENA_IMAGE_FLAG_FILE},g" ${D}${libexecdir}/os-helpers-sb
	sed -i -e "s,@@KERNEL_DEVICE_TREES@@,${KERNEL_DEVICE_TREES},g" ${D}${libexecdir}/os-helpers-sb
	if [ "${BALENA_IS_SECURED_CHECK_SKIP}" != "0" ]; then
		bbwarn "IS_SECURED_CHECK_SKIP set - do not use in production"
		sed -i -e "s,@@IS_SECURED_CHECK_SKIP@@,true,g" ${D}${libexecdir}/os-helpers-sb
	fi
	sed -i -e "s,@@IS_SECURED_CHECK_SKIP@@,false,g" ${D}${libexecdir}/os-helpers-sb
}
