DESCRIPTION = "NXP CSF parser tool"
HOMEPAGE = "https://www.nxp.com/webapp/Download?colCode=IMX_CST_TOOL"
LICENSE = "Proprietary"
LIC_FILES_CHKSUM = " \
    file://LICENSE.bsd3;md5=14aba05f9fa6c25527297c8aac95fcf6 \
    file://LICENSE.hidapi;md5=e0ea014f523f64f0adb13409055ee59e \
    file://LICENSE.openssl;md5=3441526b1df5cc01d812c7dfc218cea6 \
"
SRC_URI = "git://git@github.com/balena-os/cst.git;protocol=ssh;branch=master"
SRCREV = "b511d26d7f1f9323bc21485523b259ad9d437442"
S = "${WORKDIR}/git"

do_untar() {
    tar --strip-component=1 -C ${S} -xvf ${S}/cst-${PV}.tgz
}
addtask untar after do_unpack before do_populate_lic

EXTRA_OEMAKE = 'CC="${CC}" LD="${CC}" AR="${AR}" OBJCOPY="${OBJCOPY}"'

do_compile() {
    oe_runmake -C add-ons/hab_csf_parser COPTS="${CFLAGS} ${CPPFLAGS} ${LDFLAGS}"
}

do_install() {
    install -d ${D}${bindir}
    install -m 755 ${S}/add-ons/hab_csf_parser/csf_parser ${D}${bindir}
}

FILES:${PN} = "${bindir}"
BBCLASSEXTEND = "native nativesdk"
