inherit hab

FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}:"

SRC_URI:append = " \
    file://crypto-engine-fix-crypto_queue-backlog-handling.patch \
"

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
    d.setVar('SIGNING_ARTIFACTS', d.getVar('SIGNING_ARTIFACTS_BASE', True))
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
    set -x
    install -d "${SYSROOT_DESTDIR}/sysroot-only/"
    install "${STAGING_DIR_HOST}/hab_auth" "${SYSROOT_DESTDIR}/sysroot-only/"
}

BALENA_CONFIGS:append = " caam"
BALENA_CONFIGS[caam] = " \
    CONFIG_DAX=y \
    CONFIG_BLK_DEV_DM=y \
    CONFIG_BLK_DEV_MD=y \
    CONFIG_MD=y \
    CONFIG_ENCRYPTED_KEYS=y \
    CONFIG_DM_CRYPT=y \
    CONFIG_CRYPTO_USER_API=y \
    CONFIG_CRYPTO_USER_API_HASH=y \
    CONFIG_CRYPTO_USER_API_AEAD=y \
    CONFIG_CRYPTO_USER_API_SKCIPHER=y \
"

# The kernel is not an EFI artifact
deltask do_sign_efi
deltask do_sign_gpg
