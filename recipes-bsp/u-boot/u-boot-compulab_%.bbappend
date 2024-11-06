FILESEXTRAPATHS:prepend := "${THISDIR}/hab:"

do_generate_resin_uboot_configuration:prepend() {
    d.appendVar('UBOOT_VARS', ' KERNEL_SIGN_IVT_OFFSET DTB_SIGN_IVT_OFFSET')
    hab_auth_file = os.path.join(d.getVar('STAGING_DIR_TARGET'), "sysroot-only", "hab_auth")
    if os.path.exists(hab_auth_file):
        with open(hab_auth_file) as f:
            for line in f:
                if line.strip() and not line.startswith('#'):
                    key, value = line.strip().split('=', 1)
                    if key.startswith(d.getVar('KERNEL_IMAGETYPE')):
                        d.setVar('KERNEL_SIGN_IVT_OFFSET', value)
                        bb.note("KERNEL_SIGN_IVT_OFFSET is now %s" % d.getVar('KERNEL_SIGN_IVT_OFFSET'))
                    # Currently the device tree used is hardcoded in the U-Boot environment by the BSP layer
                    elif key.startswith('sb-iotgimx8-ied.dtb'):
                        d.setVar('DTB_SIGN_IVT_OFFSET', value)
                        bb.note("DTB_SIGN_IVT_OFFSET is now %s" % d.getVar('DTB_SIGN_IVT_OFFSET'))
    if d.getVar('KERNEL_SIGN_IVT_OFFSET') == None:
        bb.fatal("Kernel IVT offset not specified")
    if d.getVar('DTB_SIGN_IVT_OFFSET') == None:
        bb.fatal("Device tree IVT offset not specified")
}
do_generate_resin_uboot_configuration[depends] += " \
    virtual/balena-bootloader:do_sign_dtb \
    virtual/balena-bootloader:do_sign_kernel_bundle \
"

SRC_URI:append:iot-gate-imx8 = " \
    file://iot-gate-imx8-extend-the-load-address-for-FDT-files.patch \
    file://iot-gate-imx8-add-placeholder-for-IVT-offset-to-envi.patch \
    file://iot-gate-imx8-add-placeholder-for-DTB-IVT-offset-to-.patch \
"

SRC_URI:append:mx8m-generic-bsp = " \
    file://security.cfg \
    file://mach-imx-hab-allow-to-specify-custom-IVT-offset-from.patch \
    file://image-fdt-introduce-HAB-authentication-for-device-tr.patch \
"

do_configure:prepend:mx8m-generic-bsp () {
    cat ${WORKDIR}/security.cfg >> ${S}/configs/${MACHINE}_defconfig
}

# For KERNEL_SIGN_IVT_OFFSET and DTB_SIGN_IVT_OFFSET
do_generate_resin_uboot_configuration[depends] += " virtual/balena-bootloader:do_populate_sysroot"

