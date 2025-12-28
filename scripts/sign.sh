#!/usr/bin/bash

echo "::group:: ===$(basename "$0")==="

set -eoux pipefail

dnf5 -y install sbsigntools openssl

KERNEL="$(rpm -q kernel --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}')"
SIGNING_KEY="/tmp/certs/signing_key.pem"
PUBLIC_CHAIN="/tmp/certs/public_key.crt"
PUBKEY_PATH="/tmp/certs/public_key.der"
PRIVKEY_PATH="/tmp/certs/private_key.priv"

# Verify certificates exist before proceeding
if [ ! -f "${SIGNING_KEY}" ] || [ ! -f "${PUBLIC_CHAIN}" ]; then
    echo "ERROR: Certificate files not found at ${SIGNING_KEY} or ${PUBLIC_CHAIN}"
    ls -la /tmp/certs || echo "Directory /tmp/certs does not exist"
    exit 1
fi

# Sign kernel
STRIP="false"
if [[ "${STRIP}" == "true" ]]; then
    EXISTING_SIGNATURES="$(sbverify --list /usr/lib/modules/$KERNEL/vmlinuz | grep '^signature \([0-9]\+\)$' | sed 's/^signature \([0-9]\+\)$/\1/')" || true
    if [[ -n $EXISTING_SIGNATURES ]]; then
        for SIGNUM in $EXISTING_SIGNATURES
        do
            echo "Found existing signature at signum $SIGNUM, removing..."
            sbattach --remove /usr/lib/modules/$KERNEL/vmlinuz
        done
    fi
fi

sbsign --cert $PUBLIC_CHAIN --key $PRIVKEY_PATH /usr/lib/modules/$KERNEL/vmlinuz --output /usr/lib/modules/$KERNEL/vmlinuz
sbverify --list /usr/lib/modules/$KERNEL/vmlinuz

# Sign kernel modules
for module in $(find /usr/lib/modules/"${KERNEL}"/extra/ -name "*.ko*"); do
    module_basename=${module:0:-3}
    module_suffix=${module: -3}
    if [[ "$module_suffix" == ".xz" ]]; then
        xz --decompress "$module"
        openssl cms -sign -signer "${SIGNING_KEY}" -binary -in "$module_basename" -outform DER -out "${module_basename}.cms" -nocerts -noattr -nosmimecap
        /usr/src/kernels/"${KERNEL}"/scripts/sign-file -s "${module_basename}.cms" sha256 "${PUBLIC_CHAIN}" "${module_basename}"
        /tmp/scripts/sign-check.sh "${KERNEL}" "${module_basename}" "${PUBLIC_CHAIN}"
        xz -C crc32 -f "${module_basename}"
        rm -f "${module_basename}.cms"
    elif [[ "$module_suffix" == ".gz" ]]; then
        gzip -d "$module"
        openssl cms -sign -signer "${SIGNING_KEY}" -binary -in "$module_basename" -outform DER -out "${module_basename}.cms" -nocerts -noattr -nosmimecap
        /usr/src/kernels/"${KERNEL}"/scripts/sign-file -s "${module_basename}.cms" sha256 "${PUBLIC_CHAIN}" "${module_basename}"
        /tmp/scripts/sign-check.sh "${KERNEL}" "${module_basename}" "${PUBLIC_CHAIN}"
        gzip -9f "${module_basename}"
        rm -f "${module_basename}.cms"
    else
        openssl cms -sign -signer "${SIGNING_KEY}" -binary -in "$module" -outform DER -out "${module}.cms" -nocerts -noattr -nosmimecap
        /usr/src/kernels/"${KERNEL}"/scripts/sign-file -s "${module}.cms" sha256 "${PUBLIC_CHAIN}" "${module}"
        /tmp/scripts/sign-check.sh "${KERNEL}" "${module}" "${PUBLIC_CHAIN}"
        rm -f "${module}.cms"
    fi
done

echo "::endgroup::"
