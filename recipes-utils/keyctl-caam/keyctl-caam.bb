LICENSE = "BSD-3-Clause"
LIC_FILES_CHKSUM = "file://LICENSE;md5=8636bd68fc00cc6a3809b7b58b45f982"

BRANCH= "lf-6.1.36_2.1.0"
SRC_URI = "git://github.com/nxp-imx/keyctl_caam.git;protocol=https;branch=${BRANCH}"
SRCREV = "8dba6d3cac24b5a6c8daaaf1eda70fa18d488139"

S = "${WORKDIR}/git"

EXTRA_OEMAKE:append = ' KEYBLOB_LOCATION=/tmp/keys/ '

do_configure () {
	:
}

do_compile () {
	oe_runmake
}

do_install () {
	oe_runmake install 'DESTDIR=${D}'
}

FILES:${PN} = " \
	/usr \
"

PACKAGE_ARCH = "${MACHINE_SOCARCH}"
INSANE_SKIP:${PN} += "ldflags"
DEPENDS += " openssl"
