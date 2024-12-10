FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}:"

RDEPENDS:${PN} += "csf-parser"

SECUREBOOT_HOOKS = " \
    0-signed-update \
    95-secureboot/1-fwd_commit_revoke \
"
SECUREBOOT_HOOK_DIRS = " \
    95-secureboot \
"

HOSTAPP_HOOKS:append = "${SECUREBOOT_HOOKS}"
HOSTAPP_HOOKS_DIRS:append = "${SECUREBOOT_HOOK_DIRS}"
