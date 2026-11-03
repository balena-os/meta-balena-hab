DEPENDS:append = " coreutils-native curl-native jq-native ca-certificates-native xxd-native nxp-cst-signer-native"

inherit deploy

BALENA_SIGN_SLOT_INDEX ?= "0"
BALENA_SIGN_CERTS_KEY_LENGTH ?= "4096"
SIGN_HAB_TYPE ?= "hab"
# From U-boot's hab.c CONFIG_PAD_SIZE, 0x2000
CONFIG_PAD_SIZE_D ?= "8192"

# This is the IVT_SIZE macro in U-boot, 0x20
IVT_SIZE_D = "32"

image_size() {
    echo "$(stat -L -c %s ${1})"
}


# +------------+  0x0 (DDR_UIMAGE_START) -
# |   Header   |                          |
# +------------+  0x40                    |
# |            |                          |
# |            |                          |
# |            |                          |
# |            |                          |
# | Image Data |                          |
# .            |                          |
# .            |                           > Stuff to be authenticated ----+
# .            |                          |                                |
# |            |                          |                                |
# |            |                          |                                |
# +------------+                          |                                |
# |            |                          |                                |
# | Fill Data  |                          |                                |
# |            |                          |                                |
# +------------+ Align to ALIGN_SIZE      |                                |
# |    IVT     |                          |                                |
# +------------+ + IVT_SIZE              -                                 |
# |            |                                                           |
# |  CSF DATA  | <---------------------------------------------------------+
# |            |
# +------------+
# |            |
# | Fill Data  |
# |            |
# +------------+ + CSF_PAD_SIZE

do_hab_ivt() {
    _signing_artifact="${1}"
    _load_addr="${2}"

    if [ -z "${_signing_artifact}" ] || [ -z "${_load_addr}" ]; then
        bbfatal "Both signing artifact and load address required"
    fi

    _image_size_d=$(image_size "${_signing_artifact}")
    _image_size=$(printf "0x%x" ${_image_size_d})
    # Align to the next multiple of 12288
    _align_size=12288
    # Equivalent to `raw_image_size + ALIGN_SIZE - 1) & ~(ALIGN_SIZE - 1)`
    # in U-Boot's hab.c authenticate_image()
    _padsize_d="$( expr \( $_image_size_d + $_align_size - 1 \) / $_align_size \* $_align_size)"
    _padsize=$(printf "0x%x" ${_padsize_d})
    _ivt_artifact="${_signing_artifact}.ivt"

    # Pad for IVT
    objcopy -I binary -O binary --pad-to ${_padsize_d} --gap-fill=0x00 "${_signing_artifact}" "${_ivt_artifact}"

    _ivt_off=$(printf 0x%x ${_padsize})
    echo "$(basename "${_signing_artifact}")_IVT_OFFSET=${_ivt_off}" >> "${STAGING_DIR_HOST}/hab_auth"
    _load_addr_d=$(printf "%d" ${_load_addr})
    _ivt_ptr=$(printf 0x%x $(expr ${_load_addr_d} + ${_padsize_d}))
    _csf_ptr=$(printf 0x%x $(expr ${_load_addr_d} + ${_padsize_d} + ${IVT_SIZE_D} ))

    bbnote "_load_addr ${_load_addr} _image_size ${_image_size} _padsize ${_padsize} _ivt_off ${_ivt_off} _ivt_ptr ${_ivt_ptr} _csf_ptr ${_csf_ptr}"
    # Generate and concatenate little endian IVT
    # Fields: IVT header, jump location, reserved (0), DCD pointer (null), boot data (null), self pointer, CSF pointer, reserved (0)
    _ivt_header="0x402000D1"
    # Avoid using the shell printf built-in
    PRINTF=$(which printf)
    {
        ${PRINTF} $(${PRINTF} "%08x" ${_ivt_header} | sed 's/.\{2\}/&\n/g' | tac | sed 's,^,\\x,g' | tr -d '\n') # W: Quote this to prevent word splitting.
        ${PRINTF} $(${PRINTF} "%08x" ${_load_addr} | sed 's/.\{2\}/&\n/g' | tac | sed 's,^,\\x,g' | tr -d '\n') # W: Quote this to prevent word splitting.
        ${PRINTF} $(${PRINTF} "%08x" 0 | sed 's/.\{2\}/&\n/g' | tac | sed 's,^,\\x,g' | tr -d '\n') # W: Quote this to prevent word splitting.
        ${PRINTF} $(${PRINTF} "%08x" 0 | sed 's/.\{2\}/&\n/g' | tac | sed 's,^,\\x,g' | tr -d '\n') # W: Quote this to prevent word splitting.
        ${PRINTF} $(${PRINTF} "%08x" 0 | sed 's/.\{2\}/&\n/g' | tac | sed 's,^,\\x,g' | tr -d '\n') # W: Quote this to prevent word splitting.
        ${PRINTF} $(${PRINTF} "%08x" ${_ivt_ptr} | sed 's/.\{2\}/&\n/g' | tac | sed 's,^,\\x,g' | tr -d '\n') # W: Quote this to prevent word splitting.
        ${PRINTF} $(${PRINTF} "%08x" ${_csf_ptr} | sed 's/.\{2\}/&\n/g' | tac | sed 's,^,\\x,g' | tr -d '\n') # W: Quote this to prevent word splitting.
        ${PRINTF} $(${PRINTF} "%08x" 0 | sed 's/.\{2\}/&\n/g' | tac | sed 's,^,\\x,g' | tr -d '\n') # W: Quote this to prevent word splitting.
    } >> "${_ivt_artifact}"

    echo "${_ivt_artifact}"
}

# imx_signer configuration of the CSFs. imx_signer reads the keys in this
# order, keep them all and in the same order
prepare_imx_signer_cfg() {
    if [ "${BALENA_SIGN_SLOT_INDEX}" -lt "0" ] || [ "${BALENA_SIGN_SLOT_INDEX}" -gt "3" ]; then
        bbfatal "Invalid slot index ${BALENA_SIGN_SLOT_INDEX} - expected between 0 and 3"
    fi
    _slot_index_1=$(expr ${BALENA_SIGN_SLOT_INDEX} + 1)
    _cert_suffix="_1_sha256_${BALENA_SIGN_CERTS_KEY_LENGTH}_65537_v3_usr_crt.pem"
    cat << EOF > ${WORKDIR}/imx_signer.cfg
header_version=4.2
header_eng=CAAM
header_eng_config=0
srktable_file=../SRK_table.bin
srk_source_index=${BALENA_SIGN_SLOT_INDEX}
nocak_file=
csfk_file=CSF${_slot_index_1}${_cert_suffix}
unlock_engine=CAAM,OCOTP
unlock_features=MID,RNG,SRK REVOKE
unlock_uid=
img_verification_index=0
img_target_index=2
img_file=IMG${_slot_index_1}${_cert_suffix}
auth_verification_index=2
EOF
}

# Sign a HAB image with imx_signer, which finds the blocks to sign from the
# IVTs in it. It writes the CSFs and signed-<image> to the current directory,
# do_sign runs in HAB_SIGN_WORKDIR. Its cst has the server sign the CSFs
hab_imx_signer() {
    _input="${1}"

    if [ -z "${SIGN_API}" ] || [ -z "${SIGN_API_KEY}" ] || [ -z "${SIGN_HAB_PKI_ID}" ]; then
        bbfatal "SIGN_API, SIGN_API_KEY and SIGN_HAB_PKI_ID must be defined"
    fi

    prepare_imx_signer_cfg

    # SIG_DATA_PATH is only a prefix, the shim replaces it with the PKI tree
    # path on the server
    if ! SIG_TOOL_PATH="${STAGING_DATADIR_NATIVE}/balena-sign-cst" \
            SIG_DATA_PATH="${HAB_SIGN_WORKDIR}/pki" \
            SIGN_API="${SIGN_API}" SIGN_API_KEY="${SIGN_API_KEY}" \
            SIGN_IMX_PKI_ID="${SIGN_HAB_PKI_ID}" SIGN_HAB_TYPE="${SIGN_HAB_TYPE}" \
            CURL_CA_BUNDLE="${STAGING_DIR_NATIVE}/etc/ssl/certs/ca-certificates.crt" \
            imx_signer -d -i "${_input}" -c ${WORKDIR}/imx_signer.cfg; then
        bbfatal "imx_signer failed to sign ${_input}"
    fi
}

do_sign_hab() {
    _signing_artifact="${1}"
    _load_addr="${HAB_LOAD_ADDR}"

    if [ -z "${_signing_artifact}" ]; then
        bbfatal "Artifact name to sign is required"
    fi
    bbnote "Signing ${_signing_artifact}"
    if [ -z "${HAB_LOAD_ADDR}" ]; then
        bbfatal "Load address is required"
    fi

    _gzip_payload=0
    _filetype=$(file --mime-type -b "${_signing_artifact}")
    if [ "${_filetype}" = "application/gzip" ]; then
        _gzip_payload=1
        bbnote "Uncompressing compressed payload"
        mv "${_signing_artifact}" "${_signing_artifact}.gz"
        gunzip "${_signing_artifact}.gz"
    fi

    _ivt_artifact=$(do_hab_ivt ${_signing_artifact} ${HAB_LOAD_ADDR})

    hab_imx_signer ${_ivt_artifact}
    _signed="${HAB_SIGN_WORKDIR}/signed-$(basename ${_ivt_artifact})"

    # imx_signer signs the first IVT it finds. Check it is the one at the end,
    # with only its CSF appended, and not data in the image that looks like one
    _block=$(sed -n 's/.*Blocks = \(0x[0-9A-F]* 0x[0-9A-F]* 0x[0-9A-F]*\) .*/\1/p' ${HAB_SIGN_WORKDIR}/csf_image0.txt)
    _expected=$(printf "0x%08X 0x%08X 0x%08X" ${HAB_LOAD_ADDR} 0 $(image_size ${_ivt_artifact}))
    if [ "${_block}" != "${_expected}" ] || \
            ! cmp -s -n $(image_size ${_ivt_artifact}) ${_ivt_artifact} ${_signed}; then
        bbfatal "imx_signer signed ${_block}, expected only ${_expected} with its CSF appended"
    fi

    mv ${_signed} ${_signing_artifact}

    if [ "${_gzip_payload}" = "1" ]; then
        gzip "${_signing_artifact}"
        mv "${_signing_artifact}.gz" "${_signing_artifact}"
    fi
}

do_sign_ahab() {
    bbfatal "Unimplemented AHAB signing"
}

do_sign() {
    if [ -z "${SIGNING_ARTIFACTS}" ]; then
        bbfatal "No artifacts to sign"
    fi
    bbnote "Signing ${SIGNING_ARTIFACTS}"
    for SIGNING_ARTIFACT in ${SIGNING_ARTIFACTS}; do
        do_sign_${SIGN_HAB_TYPE} ${SIGNING_ARTIFACT}
    done
}

do_sign[depends] += " \
    coreutils-native:do_populate_sysroot \
    curl-native:do_populate_sysroot \
    jq-native:do_populate_sysroot \
    ca-certificates-native:do_populate_sysroot \
"
do_sign[network] = "1"
# imx_signer writes to the current directory
HAB_SIGN_WORKDIR = "${WORKDIR}/imx-signer"
do_sign[dirs] = "${HAB_SIGN_WORKDIR}"
do_sign[cleandirs] = "${HAB_SIGN_WORKDIR}"

do_sign[vardeps] += " \
    SIGN_API \
    SIGN_HAB_PKI_ID \
    SIGN_AHAB_PKI_ID \
    SIGN_HAB_TYPE \
"

do_deploy:append() {
    for SIGNING_ARTIFACT in ${SIGNING_ARTIFACTS}; do
        if [ -f "${SIGNING_ARTIFACT}.signed" ]; then
            install -m 0644 "${SIGNING_ARTIFACT}.signed" "${DEPLOYDIR}/$(basename ${SIGNING_ARTIFACT})"
        fi
    done
}
