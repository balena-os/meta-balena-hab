inherit hab

require linux-common.inc

# The device trees and the kernel bundle are signed as copies in these
# directories, which are emptied whenever the signing tasks run. The build
# output is left unsigned, so signing again always starts from it
HAB_SIGNED_DTB_DIR = "${WORKDIR}/hab-signed-dtb"
HAB_SIGNED_KERNEL_DIR = "${WORKDIR}/hab-signed-kernel"

python do_sign_dtb() {
    import shutil
    dtb_path = os.path.join(d.getVar('B', True), "arch", d.getVar('ARCH', True), "boot", "dts")
    signed_path = d.getVar('HAB_SIGNED_DTB_DIR')
    kernel_devicetrees = d.getVar('KERNEL_DEVICETREE', True)
    signing_artifacts = ""
    for dtb in kernel_devicetrees.split():
        signed_dtb = os.path.join(signed_path, dtb)
        bb.utils.mkdirhier(os.path.dirname(signed_dtb))
        shutil.copyfile(os.path.join(dtb_path, dtb), signed_dtb)
        signing_artifacts = signing_artifacts + " " + signed_dtb
    d.setVar('SIGNING_ARTIFACTS', signing_artifacts)
    hab_auth_path = os.path.join(d.getVar('STAGING_DIR_HOST'), 'hab_auth')
    if os.path.exists(hab_auth_path):
        os.remove(hab_auth_path)
    # Load address in memory
    d.setVar('HAB_LOAD_ADDR', d.getVar('HAB_DTB_LOAD_ADDR'))
    bb.build.exec_func('do_sign', d)
}
do_sign_dtb[cleandirs] = "${HAB_SIGNED_DTB_DIR}"

python do_sign_kernel_bundle() {
    import shutil
    bundle = '.'.join([d.getVar('KERNEL_IMAGETYPE', True), 'initramfs'])
    signing_artifacts = os.path.join(d.getVar('HAB_SIGNED_KERNEL_DIR'), bundle)
    shutil.copyfile(os.path.join(d.getVar('B', True), d.getVar('KERNEL_OUTPUT_DIR', True), bundle),
                    signing_artifacts)
    d.setVar('SIGNING_ARTIFACTS', signing_artifacts)
    # Load address in memory
    d.setVar('HAB_LOAD_ADDR', d.getVar('HAB_KERNEL_LOAD_ADDR'))
    bb.build.exec_func('do_sign', d)
}
do_sign_kernel_bundle[cleandirs] = "${HAB_SIGNED_KERNEL_DIR}"

# Install and deploy the signed copies instead of the unsigned build output,
# under the names kernel-devicetree and kernel use
do_install:append() {
    for dtbf in ${KERNEL_DEVICETREE}; do
        dtb=`normalize_dtb "$dtbf"`
        if "${@'false' if oe.types.boolean(d.getVar('KERNEL_DTBVENDORED')) else 'true'}"; then
            dtb=`basename $dtb`
        fi
        install -m 0644 ${HAB_SIGNED_DTB_DIR}/$dtbf ${D}/${KERNEL_DTBDEST}/$dtb
    done
}

do_deploy:append() {
    install -m 0644 ${HAB_SIGNED_KERNEL_DIR}/${KERNEL_IMAGETYPE}.initramfs \
        $deployDir/${KERNEL_IMAGETYPE}-${INITRAMFS_NAME}${KERNEL_IMAGE_BIN_EXT}
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
