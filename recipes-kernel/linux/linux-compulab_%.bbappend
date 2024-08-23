inherit hab

FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}:"

SRC_URI:append = " \
    file://crypto-engine-fix-crypto_queue-backlog-handling.patch \
"

# kernel load address in memory i.e u-boot loadaddr
HAB_LOAD_ADDR ?= "0x40480000"

SIGNING_ARTIFACTS ?= "${SIGNING_ARTIFACTS_BASE}"
addtask sign before do_populate_sysroot after do_bundle_initramfs

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
