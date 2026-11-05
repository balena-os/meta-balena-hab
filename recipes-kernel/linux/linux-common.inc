FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

# The crypto_queue backlog fix is in mainline since 6.4, and the patch does not
# apply to newer kernels
CRYPTO_ENGINE_BACKLOG_FIX = "${@'file://crypto-engine-fix-crypto_queue-backlog-handling.patch' if bb.utils.vercmp_string_op((d.getVar('LINUX_VERSION') or d.getVar('PV')).split('+')[0], '6.4', '<') else ''}"
SRC_URI:append = " ${CRYPTO_ENGINE_BACKLOG_FIX}"

BALENA_CONFIGS:append = " caam"
BALENA_CONFIGS[caam] = " \
    CONFIG_DAX=y \
    CONFIG_BLK_DEV_DM=y \
    CONFIG_BLK_DEV_MD=y \
    CONFIG_MD=y \
    CONFIG_TRUSTED_KEYS=y \
    CONFIG_ENCRYPTED_KEYS=y \
    CONFIG_DM_CRYPT=y \
    CONFIG_CRYPTO_USER_API=y \
    CONFIG_CRYPTO_USER_API_HASH=y \
    CONFIG_CRYPTO_USER_API_AEAD=y \
    CONFIG_CRYPTO_USER_API_SKCIPHER=y \
    CONFIG_CRYPTO_DEV_FSL_CAAM=y \
    CONFIG_CRYPTO_DEV_FSL_CAAM_COMMON=y \
    CONFIG_CRYPTO_DEV_FSL_CAAM_JR=y \
    CONFIG_CRYPTO_DEV_FSL_CAAM_INTC=y \
"
