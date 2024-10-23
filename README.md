# Balena's NXP i.MX High Assurance Boot (HAB) support layer

This document describes the device specific aspects of the balenaOS secure boot and disk encryption implementation for i.MX platforms.

Technically these are two distinct functionalities:
* Secure boot ensures only trusted operating system images can be booted on the device
* Disk encryption ensures data is stored on the disk encrypted, rather than in plain form

`balenaOS` ties these two together into a single feature in order to achieve operator-less unlocking of the encrypted data on trusted operating systems in a trusted state.

## Supported devices

* Compulab's IOT Gate i.MX8 board (`iot-gate-imx8` device type)

## Provisioning

The feature is opt-in, in order to enable it, the following section must be appended to your installer's `config.json`:
```json
"installer": {
  "secureboot": true
}
```
Be extra careful when opting in secure boot in installer images as the device will be automatically locked during the installation boot without further user intervention in an irreversible way. A locked device can only boot balena signed artifacts.

## Chain of trust

NXP's i.MX devices use High Assurance Boot (HAB) as the primary secure boot mechanism. This in turn makes use of the Cryptographic Acceleration and Assurance Module (CAAM) hardware for acceleration and security.

The boot ROM uses the following data:

* **Super Root Key (SRK) table**: A set of public keys used to verify the artifacts being booted. They are generated during the build process and programmed into the OTP.
* **Command Sequence File (CSF) description template**: Read by the boot ROM during the boot process, it determines how to validate artifacts by specifying the commands and parameters needed.

Multiple system components are involved in the validation of a "trusted operating system":
* The process starts in ROM, which we consider trusted by default ("root of trust")
* The ROM authenticates the signed bootloader 4096 bit length RSA key against a hash stored in the OTP and validates its signature
* The bootloader authenticates the signed balena bootloader and device trees 4096 bits length RSA keys against a hash stored in OTP and validates its signature
* The balena bootloader mounts and decrypts the root filesystem, loads the kernel with embedded initramfs and uses kexec authentication to launch it
* The Linux kernel then verifies the  kernel modules at loading time

The above is commonly referred to as the "chain of trust". For `balenaOS`, the trust ends at kernel level - neither the userspace applications nor user containers are verified. The userspace is read-only and user containers are only installed from authenticated balenaCloud access.

## One time programmable registers (OTP) and secure element keys

The following OTP registers are used in the secure boot and disk encryption mechanism:

* **SRK efuses**: Four public key hashes are stored in the device's One Time Programmable (OTP) memory when manufacturing. Only one slot is used at a time and up to three can be revoked.
* **Device specific private key**: A unique per device AES-CCM black key that is generated using the device's CAAM module and stored securely in hardware. The Linux kernel DM-crypt subsystem accesses the black key directly to encrypt/decrypt disks without exposing the key to user space.

## boot and imx partition split

On regular `balenaOS` devices there is a single `resin-boot` or `balena-boot` partition mounted under `/mnt/boot`. This holds both the files necessary to boot the device, as well as files necessary for setting up `balenaOS` (e.g. `config.json`, `system-connections`). With secure boot enabled the single boot partition is split in two:
* The `balena-imx` partition is the only one that stays unencrypted. It contains essential boot firmware files like U-Boot and the balena bootloader 2nd stage linux kernel.
* The `balena-boot` partition is encrypted and contains everything else, as these files may contain secrets such as passwords or API keys which the encryption should protect.

The partitions are mounted under `/mnt/imx` and `/mnt/boot` respectively.

## Device locking

Devices are locked at installation time. This involves:

* Programming and locking the SRK efuses table into OTP.

Please note that the installer will not automatically perform the following tasks that are required to completely secure a device. These should be part of the manufacturing process.

* Disabling JTAG debugging, or enabling secure JTAG mode.
* Disabling NXP reserve modes and/or external memory boot if applicable

Locking a device is irreversible. A locked device will only boot balena signed software.

## Re-programming of locked devices

Once a device is secure boot enabled and is locked down, re-programming can be done by USB booting balena signed flasher images.

## Debugging

It is important to understand that due to the nature of the feature, not all debugging procedures are available. Some of the more common ones are:
* A device in production mode will not accept any input or produce any output (screen/keyboard/serial) unless the user application sets it up. This makes it nearly impossible to debug early boot process failures (bootloader/kernel). A device in development mode will still start getty but only after the system gets all the way to userspace.
* It is not possible to tamper with bootloader configuration, which includes changing kernel parameters.
* Since the encryption keys can only be accessed on the device itself after authentication, it is neither possible to remove the storage media and mount/inspect it on a different device nor boot off a temporary boot media on the same device.
* Some features of the kernel are not available due to it being in lockdown mode. See `man 7 kernel_lockdown` for details.

## FAQ

* **Is it possible to load out-of-tree kernel modules?** All the kernel modules need to be signed with a trusted key. At this moments we only sign the module at build time so only the out-of-tree modules that we build and ship as a part of `balenaOS` are properly signed. Loading user-built kernel modules require building custom software and is an extra service available on demand.
* **Can I generate and use my own certificates and sign my own software?**: Publicly accessible balenaOS images are signed with shared balena certificates. Signing with custom certificates is possible but requires building custom software and is an extra service available on demand.
