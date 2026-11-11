# Version-specific patches take precedence over the generic ones
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
    file://mach-imx-hab-allow-to-specify-custom-IVT-offset-from.patch \
    file://hab-set-hab-status-in-environment.patch \
    file://cmd-boot-panic-if-image-authentication-fails.patch \
    file://image-fdt-introduce-HAB-authentication-for-device-tr.patch \
    file://spl-delay-before-panic-on-authentication-failure.patch \
"

# Since 2026.04 U-Boot finds an existing optee node itself, and the board
# environment is in a text file that hab_variscite_env adjusts instead
HAB_UBOOT_2026 = "${@'1' if bb.utils.vercmp_string_op(d.getVar('PV'), '2026.04', '>=') else '0'}"
SRC_URI:append:mx8m-generic-bsp = "${@'' if d.getVar('HAB_UBOOT_2026') == '1' else ' file://mach-imx-dt_optee-bail-out-if-optee-nodes-exists.patch'}"
SRC_URI:append:imx8mp-var-dart-pl1000pp = "${@'' if d.getVar('HAB_UBOOT_2026') == '1' else ' file://imx8mp-var-dart-adjust-environment-for-secure-boot.patch'}"

# Load the compressed kernel bundle out of the way of the unpacked one, which
# can then be up to 124M, and the device tree at the address it is signed for.
# Add the IVT offsets, which config_resin.h defines, and check the kernel is
# unpacked at the address it is signed for. This runs after all the patches,
# as the BSP layer patches the same lines.
HAB_IMG_ADDR ?= "0x70000000"
hab_variscite_env() {
    env="${S}/board/variscite/imx8mp_var_dart/imx8mp_var_dart.env"
    kernel_ivt=$(sed -n 's/^#define KERNEL_SIGN_IVT_OFFSET //p' ${S}/include/config_resin.h)
    dtb_ivt=$(sed -n 's/^#define DTB_SIGN_IVT_OFFSET //p' ${S}/include/config_resin.h)
    if [ -z "$kernel_ivt" ] || [ -z "$dtb_ivt" ]; then
        bbfatal "IVT offsets not found in config_resin.h"
    fi
    if ! grep -q "^CONFIG_SYS_LOAD_ADDR=${HAB_KERNEL_LOAD_ADDR}$" ${S}/configs/imx8mp_var_dart_defconfig; then
        bbfatal "The kernel is not unpacked at ${HAB_KERNEL_LOAD_ADDR}, where it is signed for"
    fi
    sed -i -e 's/^img_addr=.*/img_addr=${HAB_IMG_ADDR}/' \
        -e 's/^fdt_addr_r=.*/fdt_addr_r=${HAB_DTB_LOAD_ADDR}/' \
        -e 's/^fdt_addr=.*/fdt_addr=${HAB_DTB_LOAD_ADDR}/' \
        -e '/^ivt_offset=/d' -e '/^dtb_ivt_offset=/d' "$env"
    printf 'ivt_offset=%s\ndtb_ivt_offset=%s\n' "$kernel_ivt" "$dtb_ivt" >> "$env"
    for v in img_addr=${HAB_IMG_ADDR} fdt_addr_r=${HAB_DTB_LOAD_ADDR} fdt_addr=${HAB_DTB_LOAD_ADDR}; do
        grep -q "^$v$" "$env" || bbfatal "Failed to set $v in the U-Boot environment"
    done
}
do_configure:prepend:imx8mp-var-dart-pl1000pp() {
    if [ "${HAB_UBOOT_2026}" = "1" ]; then
        hab_variscite_env
    fi
}

# For KERNEL_SIGN_IVT_OFFSET and DTB_SIGN_IVT_OFFSET
do_generate_resin_uboot_configuration[depends] += " virtual/balena-bootloader:do_populate_sysroot"

# Do not use A/B u-boot support as the loading of environmental files is disabled
# the balena-bootloader will deal with A/B rollbacks
OS_BOOTCOUNT_SKIP = "1"
