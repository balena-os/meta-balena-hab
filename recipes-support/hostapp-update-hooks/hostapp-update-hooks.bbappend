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

do_install:append () {
    if [ "x${SIGN_API}" != "x" ]; then
        install -m 0755 1-bootfiles ${D}${sysconfdir}/hostapp-update-hooks.d/2-imxfiles
        sed -i -e 's:@BALENA_BOOT_FINGERPRINT@:${BALENA_BOOT_FINGERPRINT}:g;' \
          ${D}${sysconfdir}/hostapp-update-hooks.d/2-imxfiles
        sed -i -e 's:@BALENA_BOOTFILES_BLACKLIST@:${BALENA_BOOTFILES_BLACKLIST}:g;' \
          ${D}${sysconfdir}/hostapp-update-hooks.d/2-imxfiles
    fi
}
