inherit hab

require linux-common.inc

# The device trees and the kernel bundle are signed as copies in these
# directories, which are emptied whenever the signing tasks run. The build
# output is left unsigned, so signing again always starts from it
HAB_SIGNED_DTB_DIR = "${WORKDIR}/hab-signed-dtb"
HAB_SIGNED_KERNEL_DIR = "${WORKDIR}/hab-signed-kernel"

# Sign copies of build outputs, given as (output, copy) pairs, for load_addr.
# A gzipped output is signed unpacked, as U-Boot authenticates it once it has
# unpacked it, and its copy is gzipped again after signing
def hab_sign_copies(d, copies, load_addr):
    import gzip, shutil
    packed = []
    for output, copy in copies:
        bb.utils.mkdirhier(os.path.dirname(copy))
        with open(output, 'rb') as f:
            is_gzip = f.read(2) == b'\x1f\x8b'
        with (gzip.open if is_gzip else open)(output, 'rb') as src, open(copy, 'wb') as dst:
            shutil.copyfileobj(src, dst)
        if is_gzip:
            packed.append(copy)
    d.setVar('SIGNING_ARTIFACTS', ' '.join(copy for _, copy in copies))
    d.setVar('HAB_LOAD_ADDR', load_addr)
    bb.build.exec_func('do_sign', d)
    for copy in packed:
        with open(copy, 'rb') as f:
            signed = f.read()
        with gzip.GzipFile(copy, 'wb', mtime=0) as f:
            f.write(signed)

python do_sign_dtb() {
    dtb_path = os.path.join(d.getVar('B'), "arch", d.getVar('ARCH'), "boot", "dts")
    signed_path = d.getVar('HAB_SIGNED_DTB_DIR')
    hab_auth_path = os.path.join(d.getVar('STAGING_DIR_HOST'), 'hab_auth')
    if os.path.exists(hab_auth_path):
        os.remove(hab_auth_path)
    hab_sign_copies(d, [(os.path.join(dtb_path, dtb), os.path.join(signed_path, dtb))
                        for dtb in d.getVar('KERNEL_DEVICETREE').split()],
                    d.getVar('HAB_DTB_LOAD_ADDR'))
}
do_sign_dtb[cleandirs] = "${HAB_SIGNED_DTB_DIR}"

python do_sign_kernel_bundle() {
    bundle = '.'.join([d.getVar('KERNEL_IMAGETYPE'), 'initramfs'])
    hab_sign_copies(d, [(os.path.join(d.getVar('B'), d.getVar('KERNEL_OUTPUT_DIR'), bundle),
                         os.path.join(d.getVar('HAB_SIGNED_KERNEL_DIR'), bundle))],
                    d.getVar('HAB_KERNEL_LOAD_ADDR'))
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
addtask sign_kernel_bundle before do_populate_sysroot do_deploy after do_bundle_initramfs

do_sign_dtb[network] = "1"
do_sign_kernel_bundle[network] = "1"

# Stage the kernel bundle IVT offset for u-boot to use in its environment
sysroot_stage_all:append:class-target () {
    install -d "${SYSROOT_DESTDIR}/sysroot-only/"
    install "${STAGING_DIR_HOST}/hab_auth" "${SYSROOT_DESTDIR}/sysroot-only/"
}

# This bootloader is not an EFI artifact
deltask do_sign_efi
