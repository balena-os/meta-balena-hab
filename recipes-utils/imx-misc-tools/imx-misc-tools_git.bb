DESCRIPTION = "Miscellaneous boot-related tools for i.MX platforms"
HOMEPAGE = "https://github.com/madisongh/imx-misc-tools"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://LICENSE;md5=22c98979a7dd9812d2455ff5dbc88771"

DEPENDS = "systemd libzip keyutils"

SRC_URI = " \
    git://github.com/madisongh/imx-misc-tools;branch=main;protocol=https \
"
SRCREV = "401a93f3422012bbfada6fcc2a920ded2f73dc04"
S = "${WORKDIR}/git"

inherit cmake pkgconfig

EXTRA_OECMAKE = ""

do_install:append() {
    rm -rf "${D}/${libdir}/tmpfiles.d"
    rm -f "${D}/${bindir}/keystoretool"
    rm -f "${D}/${bindir}/imx-bootinfo"
}

PACKAGE_ARCH = "${MACHINE_ARCH}"
