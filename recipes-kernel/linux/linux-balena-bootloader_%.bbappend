inherit hab

require linux-compulab-common.inc

python do_sign_dtb() {
    dtb_path = os.path.join(d.getVar('B', True), "arch", d.getVar('ARCH', True), "boot", "dts")
    kernel_devicetrees = d.getVar('KERNEL_DEVICETREE', True)
    signing_artifacts = ""
    for dtb in kernel_devicetrees.split():
        signing_artifacts = signing_artifacts + " " + os.path.join(dtb_path, dtb)
    d.setVar('SIGNING_ARTIFACTS', signing_artifacts)
    hab_auth_path = os.path.join(d.getVar('STAGING_DIR_HOST'), 'hab_auth')
    if os.path.exists(hab_auth_path):
        os.remove(hab_auth_path)
    # Load address in memory
    d.setVar('HAB_LOAD_ADDR', "0x48480000")
    bb.build.exec_func('do_sign', d)
}

python do_sign_kernel_bundle() {
    signing_artifacts = os.path.join(d.getVar('B', True),
                                     d.getVar('KERNEL_OUTPUT_DIR', True),
                                     '.'.join([d.getVar('KERNEL_IMAGETYPE', True),
                                               'initramfs']))
    d.setVar('SIGNING_ARTIFACTS', signing_artifacts)
    # Load address in memory
    d.setVar('HAB_LOAD_ADDR', "0x40480000")
    bb.build.exec_func('do_sign', d)
}

addtask sign_dtb before do_install after do_compile
addtask sign_kernel_bundle before do_populate_sysroot after do_bundle_initramfs

do_sign_dtb[network] = "1"
do_sign_kernel_bundle[network] = "1"

# Stage the kernel bundle IVT offset for u-boot to use in its environment
sysroot_stage_all:append:class-target () {
    install -d "${SYSROOT_DESTDIR}/sysroot-only/"
    install "${STAGING_DIR_HOST}/hab_auth" "${SYSROOT_DESTDIR}/sysroot-only/"
}

# This bootloader is not an EFI artifact
deltask do_sign_efi
