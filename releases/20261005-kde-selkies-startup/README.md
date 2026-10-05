# KDE Selkies startup image update

This release updates the existing Ubuntu VPS KDE variant (app 241, version
1221). Its version label, availability, default selection, ports, and resources
remain the same. Only its image reference and customer release notes change.

New image: `resolute-server-cloudimg-amd64v3-remote-desktop-kde-20261005.img`.
Seed server: `cylo13.ata.ams3.nl.cylo.net` (server 578).

## Source change

The Selkies startup script sets ownership on `/home/appbox`, `/config`, and
their Desktop directories without walking existing user files. Default files
are already copied with preserved ownership. Existing user data is retained.

## Release procedure

1. Commit and push this release to `ubuntu-26.04_kde`.
2. On the dedicated builder, fetch the commit into a clean detached worktree.
   Run `sudo bash releases/20261005-kde-selkies-startup/apply-to-builder.sh`.
   This accepts only the verified old or new startup script, backs up the old
   file, installs the committed script, and starts Selkies and KDE.
3. Verify the web desktop, backend listener, and a second service startup with
   the existing persistent home. Run the Selkies component checks.
4. Copy the original clean template to a unique builder staging directory.
   Its SHA-256 must be
   `16e62a26155e4650d2e848852d785e268e20ff9712cdc3fc4e53c575fa6f37b0`.
   Do not capture the builder's working disk or home directory.
5. With qemu-utils and libguestfs tools on the builder, run
   `sudo bash releases/20261005-kde-selkies-startup/build-image.sh BASE_IMAGE OUTPUT_DIRECTORY`.
   The script copies the template, installs only the committed startup script,
   verifies its hash, checks qcow2 integrity, and preserves the virtual size.
   Without KVM, use `LIBGUESTFS_BACKEND=direct LIBGUESTFS_BACKEND_SETTINGS=force_tcg`.
6. Transfer the finished image to a temporary filename on seed server 578.
   Verify its checksum and permissions before moving it to the new image name.
   Register it through the existing `cron syncImages` serverapi command and
   verify the central `server_images` record.
7. Apply `catalogue.sql` through the central PostgreSQL MCP. It locks the one
   version row, checks the complete baseline and seed registration, and updates
   only the image, release notes, and timestamp. Independently read back the row
   and verify that all other fields equal the baseline.
8. Validate a fresh KDE installation on tester2 using the new image. Existing
   customer VMs are not changed by this catalogue update.

The installed startup script SHA-256 is
`431782676de2c3562dcbc931ff53cdf5f7529d93ea70a2ab6adaeff43f4a9e85`.
