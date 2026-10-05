# Coolify VPS image

This branch adds a server-only Coolify image to `vm_images`. It uses Ubuntu
26.04 amd64 and Coolify 4.3.23. It does not run the desktop installer.

The package includes Coolify, PostgreSQL 15, Redis 7, the upstream realtime
service and Traefik. Docker and all project workloads run inside the guest VM.
It uses the existing Appbox VM lifecycle, callback and domain routing.

## Prepare a template

Use a fresh Ubuntu 26.04 cloud-image VM on the designated image builder.
Check out the exact reviewed and pushed branch commit inside that VM, then run:

```bash
sudo bash coolify/install.sh
```

The installer installs Docker, caches the upstream amd64 images and installs
the first-boot services. It does not create a Coolify instance, administrator,
database, application encryption key or localhost SSH key in the template.
Do not run the existing root `install.sh` for this image: that installs a desktop.

Before converting the stopped guest to qcow2, use the existing image sealing
procedure to clean cloud-init identity, builder credentials, SSH host keys and
history. Confirm `/data/coolify/source/.env` and `.appbox-ready` do not exist.
Never seal an initialized Coolify VM: cloned encryption keys, database
credentials and localhost SSH keys would be shared between customers.

The upstream baseline is tag `v4.3.23`, commit
`e2e2d4010bcd590084b66d6f748f3eec8e2bbee9`. The Compose configuration follows
that release. Supporting images use upstream version tags; capture their exact
registry digests in the image build record before a release. Source preparation
alone does not verify those tags or publish a VM image.

`coolify/build.py` automates this preparation on `builder.tester2.appboxes.co`
as `appbox`. Give it an archive made from the exact pushed Git commit and a
unique directory under `/home/appbox/builds/coolify-vps-*`:

```bash
python3 context/coolify/build.py --commit <full-commit-sha> \
  --archive context.tgz --work-dir <unique-build-directory>
```

It verifies the official cloud image's SHA-256 checksum, boots a fresh guest,
checks its SSH host key from its serial console, installs the package and
records all five upstream image digests. It removes build access, SSH host
keys and cloud-init identity before shutting down and converting the disk.
The output is a standalone compressed qcow2 and `artifacts/build.json`.
It uses KVM when available and software emulation otherwise. The builder
and existing Appbox VMs are not used as template disks.

## Installation configuration

The new catalogue entry will need `type = vm`, `tcp_passthrough = true`,
`IsWebApp = 1`, domain support, an SSH port mapping and `expect_callback = 1`.
Keep it admin-only for validation on `tester2`. Registration and resource
settings are a separate rollout step; this branch does not change the catalogue.

The normal VM cloud-init path must supply these entries in `/etc/environment`:

| Entry | Purpose |
| --- | --- |
| `VIRTUAL_HOST` | One assigned dashboard hostname, without a scheme or port |
| `COOLIFY_ADMIN_EMAIL` | Initial administrator's login email address |
| `BASIC_AUTH` | Existing `appbox:` bcrypt hash generated from the installation `PASSWORD` |
| `INSTANCE_ID`, `CALLBACK_TOKEN` | Existing authenticated VM installed callback |

Use the existing sensitive, revealable installation `PASSWORD` field with
`showOnInstalled: true`. Do not add a plaintext Coolify password environment
entry. The administrator starts with the installation password; subsequent
password or email changes made in Coolify survive a reboot.

First boot creates independent application secrets and a localhost SSH key.
It starts the dashboard on VM loopback, creates the root administrator with
the installation bcrypt hash, checks its owner role and disables registration.
The dashboard route is configured after account setup. The VM callback depends
on this setup and successful HTTPS verification, so a provisioning failure
cannot report installation success.

Keep automatic Coolify updates disabled for this package. The upstream updater
replaces Compose configuration, which needs separate validation against this
package's private ports and provisioning helper. An Appbox VM image update must
not replace a running guest's disk to upgrade Coolify; back up its state and
use a separately validated application update procedure.

## Domains and certificates

The existing `NginxService.php` stream map forwards each assigned SNI hostname
to the VM's port 443. The guest's Traefik terminates TLS. Libvirt supplies
Appbox certificate directories at `/etc/ssl/domains/<domain>/`.

The package checks certificate expiry, hostname coverage and the matching
private key, then loads copies through Traefik's file provider. A guest timer
checks for renewals once a minute. Copies are restricted to the guest and kept
under `/data/coolify/proxy/certs`; protect these files in backups too.

Add a project's hostname to this VM in Appbox as well as configuring it in
Coolify. DNS alone does not add an outer stream route, and this package does
not automatically register project hostnames or enable wildcard routing.

Appbox's outer port 80 handling does not forward ACME HTTP challenges to
Coolify. The packaged proxy therefore uses TLS-ALPN challenges on port 443
for domains without supplied Appbox certificates. This route needs validation
on the actual installed VM before that certificate workflow is claimed.
The initial administrator email is also used for ACME registration.
HTTP/3 is disabled because the existing stream path carries TCP traffic.

Dashboard HTTP, realtime and terminal services stay private to the VM's Docker
network; the dashboard's direct port is bound to loopback. The normal Coolify
domain routes carry WebSockets through port 443. Public database or other
non-HTTP ports require separate Appbox mappings.

## Storage and recovery

Keep `/data/coolify`, its `.env` and the Docker volumes in the VM disk and include
them in backups. The `.env` encryption key is needed to restore stored secrets.
Restarting setup preserves generated secrets, existing accounts and edited
Compose configuration.

The package needs no Appbox shared user-file mount. Customer projects use the
VM's files and Docker volumes. Shared-storage workflows remain outside this
initial package.

`/moduser.sh` implements the existing administrator password recovery contract.
It sends the password to the Coolify helper through stdin and verifies the
saved hash. Use the authorized Appbox recovery flow; do not put passwords in
shell history, logs or review output.

## Validation

Run the source checks from this branch:

```bash
shellcheck coolify/install.sh coolify/moduser.sh
bash -n coolify/install.sh coolify/moduser.sh
php -l coolify/provision.php
python3 -m unittest discover -s coolify/tests -v
```

The tests exercise environment parsing, persistence, certificate/key matching,
wildcard coverage, renewal, private-file permissions, both Compose files and
blocking readiness when certificate or HTTPS checks fail.
They do not require a running Docker daemon. Ownership calls in the persistence
test are mocked; actual UID ownership still requires a root Linux VM test.

Required checks before publication and catalogue launch:

- Prepare, seal and boot two disposable guest clones; confirm their application
  secrets, database credentials, SSH keys and machine identities differ.
- Install the image normally on `tester2`; check callback state, administrator
  login, owner role, public registration blocking and password recovery.
- Check the installed password's owner Show/Hide controls without recording it.
- Deploy a disposable project on an assigned Appbox hostname and verify its
  content and certificate through the outer stream router.
- Verify dashboard realtime updates and the web terminal over WebSockets.
- Verify renewal, a newly attached custom-domain certificate and the actual
  TLS-ALPN challenge workflow. Check HTTP redirects and hostname routing.
- Reboot and verify project data, accounts, edited settings and configuration
  persist. Exercise the validated application upgrade with the same data.
- Run the ownership, shutdown and Docker service checks as root inside the VM.

Any missing required check leaves release readiness unconfirmed. Do not reuse
the desktop template-conversion script unchanged: it expects Selkies services.

Upstream: https://github.com/coollabsio/coolify

Certificate integration: https://coolify.io/docs/core/networking/proxy/traefik/custom-ssl-certs
