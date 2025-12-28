#!/bin/bash

# URL of the GitHub repository ZIP
DOWNLOAD_URL="https://github.com/johnfanv2/LenovoLegionLinux/archive/refs/heads/main.zip"
curl --retry 3 -Lo /tmp/LenovoLegionLinux-main.zip "$DOWNLOAD_URL"
unzip /tmp/LenovoLegionLinux-main.zip -d /tmp/

KERNEL_SUFFIX=""
KERNELVERSION="$(rpm -qa | grep -P 'kernel-(|'"$KERNEL_SUFFIX"'-)(\d+\.\d+\.\d+)' | sed -E 's/kernel-(|'"$KERNEL_SUFFIX"'-)//')"

# Now set KVER to the same value as KERNELVERSION
KVER=$KERNELVERSION

# Export the KERNELVERSION for use in the Makefile
export KERNELVERSION
export KVER

# Run make with the correct KERNELVERSION
echo "Compiling and installing kernel modules..."
make -C /tmp/LenovoLegionLinux-main/kernel_module KERNELVERSION=$KERNELVERSION KVER=$KVER
make -C /tmp/LenovoLegionLinux-main/kernel_module install KERNELVERSION=$KERNELVERSION KVER=$KVER

KERNEL="$(rpm -q kernel --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}')"
SIGNING_KEY="/tmp/certs/signing_key.pem"
PUBLIC_CHAIN="/tmp/certs/public_key.crt"

# Verify certificates exist before proceeding
if [ ! -f "${SIGNING_KEY}" ] || [ ! -f "${PUBLIC_CHAIN}" ]; then
    echo "ERROR: Certificate files not found at ${SIGNING_KEY} or ${PUBLIC_CHAIN}"
    ls -la /tmp/certs || echo "Directory /tmp/certs does not exist"
    exit 1
fi

for module in $(find /lib/modules/"${KERNEL}"/kernel/drivers/platform/x86/ -name "legion-laptop.ko"); do
    openssl cms -sign -signer "${SIGNING_KEY}" -binary -in "$module" -outform DER -out "${module}.cms" -nocerts -noattr -nosmimecap
    /usr/src/kernels/"${KERNEL}"/scripts/sign-file -s "${module}.cms" sha256 "${PUBLIC_CHAIN}" "${module}"
    /tmp/scripts/sign-check.sh "${KERNEL}" "${module}" "${PUBLIC_CHAIN}"
    xz -C crc32 -f "${module}"
    rm -f "${module}.cms"
done

echo "Process completed!"