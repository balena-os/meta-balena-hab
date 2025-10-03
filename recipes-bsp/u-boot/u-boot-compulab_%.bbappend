FILESEXTRAPATHS:prepend := "${THISDIR}/hab:${THISDIR}/hab/${PV}"

do_generate_resin_uboot_configuration:prepend() {
    d.appendVar('UBOOT_VARS', ' KERNEL_SIGN_IVT_OFFSET DTB_SIGN_IVT_OFFSET')
    hab_auth_file = os.path.join(d.getVar('STAGING_DIR_TARGET'), "sysroot-only", "hab_auth")
    devicetrees = [os.path.basename(dt) for dt in d.getVar('KERNEL_DEVICETREE').split()]
    if os.path.exists(hab_auth_file):
        with open(hab_auth_file) as f:
            for line in f:
                if line.strip() and not line.startswith('#'):
                    key, value = line.strip().split('=', 1)
                    if key.startswith(d.getVar('KERNEL_IMAGETYPE')):
                        d.setVar('KERNEL_SIGN_IVT_OFFSET', value)
                        bb.note("KERNEL_SIGN_IVT_OFFSET is now %s" % d.getVar('KERNEL_SIGN_IVT_OFFSET'))
                    # Currently the device tree used is hardcoded in the U-Boot environment by the BSP layer
                    elif any(key.startswith(dt) for dt in devicetrees):
                        dtb_sign_ivt_offset = d.getVar('DTB_SIGN_IVT_OFFSET', True)
                        if dtb_sign_ivt_offset is None:
                            d.setVar('DTB_SIGN_IVT_OFFSET', value)
                            bb.note("DTB_SIGN_IVT_OFFSET is now %s" % d.getVar('DTB_SIGN_IVT_OFFSET', True))
                        elif dtb_sign_ivt_offset != value:
                            bb.fatal(f"IVT offset {value} should be the same {dtb_sign_ivt_offset} as other device trees.")
    if d.getVar('KERNEL_SIGN_IVT_OFFSET') == None:
        bb.fatal("Kernel IVT offset not specified")
    if d.getVar('DTB_SIGN_IVT_OFFSET') == None:
        bb.fatal("Device tree IVT offset not specified")
}
do_generate_resin_uboot_configuration[depends] += " \
    virtual/balena-bootloader:do_sign_dtb \
    virtual/balena-bootloader:do_sign_kernel_bundle \
"

SRC_URI:append:mx8m-generic-bsp = " \
    file://security.cfg \
    file://mach-imx-hab-allow-to-specify-custom-IVT-offset-from.patch \
    file://image-fdt-introduce-HAB-authentication-for-device-tr.patch \
    file://cmd-boot-panic-if-image-authentication-fails.patch \
    file://hab-set-hab-status-in-environment.patch \
"

SRC_URI:append:iot-gate-imx8 = " \
    file://iot-gate-imx8-extend-the-load-address-for-FDT-files.patch \
    file://iot-gate-imx8-add-placeholder-for-IVT-offset-to-envi.patch \
    file://iot-gate-imx8-add-placeholder-for-DTB-IVT-offset-to-.patch \
"

SRC_URI:append:iot-gate-imx8plus = " \
    file://compulab-imx8m-plus-adjust-environment-for-secure-bo.patch \
    file://u-boot-compulab-iot-gate-imx8plus-configure-for-secu.patch \
    file://mach-imx-dt_optee-bail-out-if-optee-nodes-exists.patch \
    file://spl-delay-before-panic-on-authentication-failure.patch \
"

do_configure:prepend:mx8m-generic-bsp () {
    cat ${WORKDIR}/security.cfg >> ${S}/configs/${MACHINE}_defconfig
}

# For KERNEL_SIGN_IVT_OFFSET and DTB_SIGN_IVT_OFFSET
do_generate_resin_uboot_configuration[depends] += " virtual/balena-bootloader:do_populate_sysroot"

# Do not use A/B u-boot support as the loading of environmental files is disabled
# the balena-bootloader will deal with A/B rollbacks
OS_BOOTCOUNT_SKIP = "1"
