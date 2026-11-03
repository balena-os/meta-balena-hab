inherit hab

python __anonymous () {
    # The image files are named imx-boot<variant>-<machine>-<config>.bin-<target>
    # by the imx-boot recipe. BOOT_CONFIG_MACHINE holds the first part only when
    # the BSP defines it, newer meta-imx releases do not and build the name
    # inside the compile loop, so compose it from the variables used there
    boot_config_machines = []
    boot_config_machine = d.getVar('BOOT_CONFIG_MACHINE', True)
    if boot_config_machine:
        boot_config_machines.append(boot_config_machine)
    else:
        boot_variant = d.getVar('BOOT_VARIANT', True) or ""
        machine = d.getVar('MACHINE', True)
        for uboot_config in (d.getVar('UBOOT_CONFIG', True) or "").split():
            boot_config_machines.append(f"imx-boot{boot_variant}-{machine}-{uboot_config}.bin")
    sign_artifact_names = []
    imxboot_targets = d.getVar('IMXBOOT_TARGETS', True)
    for boot_config_machine in boot_config_machines:
        for target in imxboot_targets.split():
            sign_artifact_names.append(f"{boot_config_machine}-{target}")
    d.setVar('SIGNING_ARTIFACTS', " ".join(sign_artifact_names))
}

# imx_signer finds every IVT in the image, the FIT FDT one included, and signs
# them in order, each CSF covering the ones before it
do_sign_hab() {
    if [ -z "${SIGNING_ARTIFACTS}" ]; then
        bbfatal "No artifacts to sign, check UBOOT_CONFIG, BOOT_VARIANT and IMXBOOT_TARGETS"
    fi

    for SIGNING_ARTIFACT in ${SIGNING_ARTIFACTS}; do
        hab_imx_signer ${S}/${SIGNING_ARTIFACT}
        mv ${HAB_SIGN_WORKDIR}/signed-$(basename ${SIGNING_ARTIFACT}) ${S}/${SIGNING_ARTIFACT}
    done
}

do_efuses() {
    SIGN_HAB_TYPE="${SIGN_HAB_TYPE}"

    if [ "x${SIGN_API}" = "x" ]; then
        bbnote "Signing API not defined"
        return 1
    fi

    if [ "x${SIGN_API_KEY}" = "x" ]; then
        bbfatal "Signing API key must be defined"
    fi

    if [ "${SIGN_HAB_TYPE}" = "hab" ]; then
        if [ "x${SIGN_HAB_PKI_ID}" = "x" ]; then
            bbfatal "HAB PKI ID must be defined"
        else
            SIGN_IMX_PKI_ID=${SIGN_HAB_PKI_ID}
        fi
    fi

    if [ "${SIGN_HAB_TYPE}" = "ahab" ]; then
        if [ "x${SIGN_AHAB_PKI_ID}" = "x" ]; then
            bbfatal "AHAB PKI ID must be defined"
        else
            SIGN_IMX_PKI_ID=${SIGN_AHAB_PKI_ID}
        fi
    fi

    if [ -z "${SIGN_IMX_PKI_ID}" ]; then
        bbfatal "PKI ID must be defined"
    fi

    REQUEST_FILE=$(mktemp)
    RESPONSE_FILE=$(mktemp)
    _timeout=60
    if CURL_CA_BUNDLE="${STAGING_DIR_NATIVE}/etc/ssl/certs/ca-certificates.crt" curl --retry 5 --silent --show-error --max-time ${_timeout} "${SIGN_API}/imx/efuses/${SIGN_IMX_PKI_ID}" -X GET -H "Content-Type: application/json" -H "X-API-Key: ${SIGN_API_KEY}" --output "${RESPONSE_FILE}"; then
        jq -r ".efuses" < "${RESPONSE_FILE}" | base64 -d > "${WORKDIR}/efuses.bin"
    else
        bbfatal "Failed to fetch efuses for ${SIGN_IMX_PKI_ID} with error $?"
    fi
    rm -f "${REQUEST_FILE}" "${RESPONSE_FILE}"

    if [ ! -s "${WORKDIR}/efuses.bin" ]; then
        bbfatal "Unspecified error - empty file"
    fi
    # Generate efuses programming script
    xxd -e -g 4 -c 4 -u "${WORKDIR}/efuses.bin" | awk '{print "0x" $2}' | awk 'BEGIN {BANK=5; ADDR=0;} { BANK+=(ADDR==0); $0="fuse prog "BANK" "ADDR" "$0; ADDR+=1 ; ADDR%=4;}1' > ${WORKDIR}/lock.scr
}

do_deploy:append() {
    install -m 0644 "${WORKDIR}/efuses.bin" "${DEPLOYDIR}/efuses.bin"
    install -m 0644 ${WORKDIR}/lock.scr "${DEPLOYDIR}/lock.scr"
}

do_efuses[depends] += " \
    coreutils-native:do_populate_sysroot \
    curl-native:do_populate_sysroot \
    jq-native:do_populate_sysroot \
    ca-certificates-native:do_populate_sysroot \
    xxd-native:do_populate_sysroot \
"
do_efuses[network] = "1"

do_efuses[vardeps] += " \
    SIGN_API \
    SIGN_HAB_PKI_ID \
    SIGN_AHAB_PKI_ID \
    SIGN_HAB_TYPE \
"
addtask sign after do_compile before do_install
addtask efuses after do_sign before do_deploy
