FILESEXTRAPATHS:prepend := "${THISDIR}/hab/${PV}:${THISDIR}/hab:"

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
    file://fit-fdt-signature.cfg \
    file://spl-size.cfg \
    file://mach-imx-hab-allow-to-specify-custom-IVT-offset-from.patch \
    file://image-fdt-introduce-HAB-authentication-for-device-tr.patch \
    file://cmd-boot-panic-if-image-authentication-fails.patch \
    file://hab-set-hab-status-in-environment.patch \
    file://spl-delay-before-panic-on-authentication-failure.patch \
    file://spl-delay-before-panic-on-fit-fdt-authentication-failure.patch \
"

SRC_URI:append:iot-gate-imx8 = " \
    file://iot-gate-imx8-extend-the-load-address-for-FDT-files.patch \
    file://iot-gate-imx8-add-placeholder-for-IVT-offset-to-envi.patch \
    file://iot-gate-imx8-add-placeholder-for-DTB-IVT-offset-to-.patch \
"

SRC_URI:append:iot-gate-imx8plus = " \
    file://compulab-imx8m-plus-adjust-environment-for-secure-bo.patch \
    file://u-boot-compulab-iot-gate-imx8plus-configure-for-secu.patch \
"

do_configure:prepend:mx8m-generic-bsp () {
    cat ${WORKDIR}/security.cfg >> ${S}/configs/${MACHINE}_defconfig
    cat ${WORKDIR}/fit-fdt-signature.cfg >> ${S}/configs/${MACHINE}_defconfig
    cat ${WORKDIR}/spl-size.cfg >> ${S}/configs/${MACHINE}_defconfig
    # loadaddr, where the environment unpacks the kernel bundle, has to be the
    # address it is signed for
    echo "CONFIG_SYS_LOAD_ADDR=${HAB_KERNEL_LOAD_ADDR}" >> ${S}/configs/${MACHINE}_defconfig
}

# The environment patches load the device tree at HAB_DTB_LOAD_ADDR
UBOOT_VARS:append:mx8m-generic-bsp = " HAB_DTB_LOAD_ADDR"

# booti authenticates the kernel bundle and the device tree where the
# environment loads them, check that they are the addresses they are signed for
HAB_UBOOT_ENV_LOAD_ADDRS = ""
HAB_UBOOT_ENV_LOAD_ADDRS:iot-gate-imx8 = "loadaddr=HAB_KERNEL_LOAD_ADDR fdt_addr=HAB_DTB_LOAD_ADDR"
HAB_UBOOT_ENV_LOAD_ADDRS:iot-gate-imx8plus = "loadaddr=HAB_KERNEL_LOAD_ADDR fdt_addr_r=HAB_DTB_LOAD_ADDR"

python do_check_hab_load_addr () {
    checks = [c.split('=', 1) for c in d.getVar('HAB_UBOOT_ENV_LOAD_ADDRS').split()]
    if not checks:
        return

    # Read the default environment from u-boot.bin, where it is a list of
    # NUL terminated name=value strings. u-boot-initial-env is not the same,
    # the tool that writes it does not get the UBOOT_VARS from config_resin.h
    for machine in d.getVar('UBOOT_MACHINE').split():
        with open(os.path.join(d.getVar('B'), machine, 'u-boot.bin'), 'rb') as f:
            binary = f.read()
        for name, var in checks:
            signed = d.getVar(var)
            key = b'\0' + name.encode() + b'='
            values = set()
            start = binary.find(key)
            while start != -1:
                start += len(key)
                values.add(binary[start:binary.index(b'\0', start)].decode(errors='replace').strip())
                start = binary.find(key, start)
            if not values:
                bb.fatal("%s is not in the U-Boot environment of %s, it has to load at %s %s"
                         % (name, machine, var, signed))
            for value in values:
                # U-Boot reads addresses in the environment as hex, with or without 0x
                try:
                    matches = int(value, 16) == int(signed, 16)
                except ValueError:
                    matches = False
                if not matches:
                    bb.fatal("U-Boot %s loads at %s=%s, but it is signed for %s %s, HAB authentication would fail"
                             % (machine, name, value, var, signed))
            bb.note("U-Boot %s: %s=%s matches %s" % (machine, name, ' '.join(values), var))
}
do_check_hab_load_addr[vardeps] += "HAB_KERNEL_LOAD_ADDR HAB_DTB_LOAD_ADDR"
addtask check_hab_load_addr after do_compile before do_install

# For KERNEL_SIGN_IVT_OFFSET and DTB_SIGN_IVT_OFFSET
do_generate_resin_uboot_configuration[depends] += " virtual/balena-bootloader:do_populate_sysroot"

# Do not use A/B u-boot support as the loading of environmental files is disabled
# the balena-bootloader will deal with A/B rollbacks
OS_BOOTCOUNT_SKIP = "1"
