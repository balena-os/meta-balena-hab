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

do_compile:append() {
    for target in flash_evk print_fit_hab; do
        if [ ! -f "${BOOT_STAGING}/${UBOOT_DTB_NAME}" ]; then
            cp ${DEPLOY_DIR_IMAGE}/${BOOT_TOOLS}/${UBOOT_DTB_NAME} ${BOOT_STAGING}
        fi
        bbnote "building ${IMX_BOOT_SOC_TARGET} - ${target}"
        make SOC=${IMX_BOOT_SOC_TARGET} ${REV_OPTION} ${MKIMAGE_EXTRA_ARGS} dtbs=${UBOOT_DTB_NAME} ${target} 2>&1 | tee ${target}.log
        install "${B}/${target}.log" "${BOOT_STAGING}/"
    done
}

do_sign_hab() {
    if [ -z "${SIGNING_ARTIFACTS}" ]; then
        bbfatal "No artifacts to sign, check UBOOT_CONFIG, BOOT_VARIANT and IMXBOOT_TARGETS"
    fi
    if [ ! -f "${BOOT_STAGING}/flash_evk.log" ] || [ ! -f "${BOOT_STAGING}/print_fit_hab.log" ]; then
        bbfatal "mkimage output files not available in ${BOOT_STAGING} directory"
    fi

    _payload=%%BIN_PATH%%
    # Extract load address, offset and length from mkimage log file, the
    # fit-fdt lines are skipped as their names are not valid shell variables
    eval $(awk  -F":" '(/hab block/)&&($1 !~ /-/)&&(gsub(/ /,"_",$1))&&($0=$1"=\""$2"\"")' ${BOOT_STAGING}/flash_evk.log)
    # Append the image binary path
    _spl_hab_block="${_spl_hab_block} \"${_payload}\""
    _sld_hab_block="${_sld_hab_block} \"${_payload}\""

    bbnote "_spl_hab_block=${_spl_hab_block} _sld_hab_block=${_sld_hab_block}"

    # Extract load addresses, offsets and lengths from FIT log file
    blocks=$(awk -v payload=${_payload} '(/^0x/)&&($0=","$0" \""payload"\" \\\n")' ORS=" " ${BOOT_STAGING}/print_fit_hab.log)

    bbnote "blocks=${blocks}"

    prepare_sign_csf

    # Append blocks lines to template
    cat ${WORKDIR}/csf > ${WORKDIR}/csf_fit
    echo "$_sld_hab_block \ " >> ${WORKDIR}/csf_fit
    echo "${blocks}" >> ${WORKDIR}/csf_fit

    cat ${WORKDIR}/csf > ${WORKDIR}/csf_spl
    echo "$_spl_hab_block" >> ${WORKDIR}/csf_spl

    # Extract offsets from mkimage log file
    eval $(awk '(/csf_off|sld_csf_off/)&&($1 !~ /-/)&&($0=$1"="$2)' ${BOOT_STAGING}/flash_evk.log)
    bbnote "csf_off=${csf_off} sld_csf_off=${sld_csf_off}"
    if [ -z "${csf_off}" ] || [ -z "${sld_csf_off}" ]; then
        bbfatal "CSF offsets not found in ${BOOT_STAGING}/flash_evk.log"
    fi

    for SIGNING_ARTIFACT in ${SIGNING_ARTIFACTS}; do
        # Generate CSF binaries
        cst ${S}/${SIGNING_ARTIFACT} ${WORKDIR}/csf_fit
        cst ${S}/${SIGNING_ARTIFACT} ${WORKDIR}/csf_spl

        # Append signature to image offsets to generate signed FIT image
        dd if=${WORKDIR}/csf_spl.bin of=${S}/${SIGNING_ARTIFACT} seek=$(printf "%d" ${csf_off}) bs=1 conv=notrunc
        dd if=${WORKDIR}/csf_fit.bin of=${S}/${SIGNING_ARTIFACT} seek=$(printf "%d" ${sld_csf_off}) bs=1 conv=notrunc

        # Check that the CSFs are in the image, a CSF starts with the 0xd4 tag
        for _off in ${csf_off} ${sld_csf_off}; do
            if [ "$(xxd -p -l 1 -s $(printf "%d" ${_off}) ${S}/${SIGNING_ARTIFACT})" != "d4" ]; then
                bbfatal "No CSF found at offset ${_off} of ${SIGNING_ARTIFACT}"
            fi
        done
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
