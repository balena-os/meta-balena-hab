FILESEXTRAPATHS:prepend := "${THISDIR}/linux-compulab:"

SRC_URI:append = " \
    file://crypto-engine-fix-crypto_queue-backlog-handling.patch \
"

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
    CONFIG_CRYPTO_DEV_FSL_CAAM=y \
    CONFIG_CRYPTO_DEV_FSL_CAAM_COMMON=y \
    CONFIG_CRYPTO_DEV_FSL_CAAM_JR=y \
    CONFIG_CRYPTO_DEV_FSL_CAAM_INTC=y \
"
