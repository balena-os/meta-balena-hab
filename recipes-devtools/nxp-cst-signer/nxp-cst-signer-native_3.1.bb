SUMMARY = "NXP i.MX image signer"
DESCRIPTION = "Finds the blocks to authenticate in an i.MX boot image and signs \
them with CST. A CST replacement that signs on the balena signing server is \
installed with it."
HOMEPAGE = "https://github.com/nxp-imx-support/nxp-imx-signer"
LICENSE = "GPL-2.0-only"
LIC_FILES_CHKSUM = "file://LICENSE.txt;md5=1f6f1c0be32491a0c8d2915607a28f36"

SRC_URI = " \
    git://github.com/nxp-imx-support/nxp-imx-signer.git;protocol=https;branch=master;destsuffix=${BP} \
    file://balena-sign-cst \
"
SRCREV = "48f3108627201c9b31c27faa97ced912e9d1e313"


inherit native

EXTRA_OEMAKE = "-C src CC='${CC}' CFLAGS='${CFLAGS}' LDFLAGS='${LDFLAGS}'"

do_install() {
    install -D -m 0755 ${S}/src/imx_signer ${D}${bindir}/imx_signer
    # imx_signer runs ${SIG_TOOL_PATH}/linux64/bin/cst
    install -D -m 0755 ${UNPACKDIR}/balena-sign-cst ${D}${datadir}/balena-sign-cst/linux64/bin/cst
}
