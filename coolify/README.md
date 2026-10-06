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

`coolify/build.py` automates this preparation on `builder.grant.appboxes.co`
as `appbox`. Give it an archive made from the exact pushed Git commit and a
unique directory under `/home/appbox/builds/coolify-vps-*`:

```bash
python3 context/coolify/build.py --commit <full-commit-sha> \
  --archive context.tgz --work-dir <unique-build-directory>
```

It verifies the official cloud image's SHA-256 checksum, boots a fresh guest,
checks its SSH host key from its serial console, applies current Ubuntu updates,
installs the package and records all five upstream image digests. It removes build access, SSH host
keys and cloud-init identity before shutting down and converting the disk.
The output is a standalone compressed qcow2 and `artifacts/build.json`.
For package-only corrections, `coolify/rebuild.py` can use that checksum-verified,
uninitialized template and an exact pushed source archive. It requires
`guestfish`/`virt-customize`, verifies the copied package files, records the parent
template checksum and produces a new standalone image. OS or kernel updates
require a fresh full build; its receipt records installed OS package versions
and the kernel selected for the next boot. It must not use a customer VM or
initialized Coolify disk. The root mount omits synchronous
`discard`; the existing fstrim timer handles trimming.
It uses KVM when available and software emulation otherwise. The builder
and existing Appbox VMs are not used as template disks.

## Installation configuration

The new catalogue entry will need `type = vm`, `tcp_passthrough = true`,
`IsWebApp = 1`, domain support, an SSH port mapping and `expect_callback = 1`.
Keep it admin-only for validation on `grant` (Cylo 11350, formerly `tester2`). The admin-only test entry is defined in `appbox.yml` and
`catalogue/register-admin-test.sql`: 4 CPUs, 8 GB RAM and eight app slots.
The SQL script follows the existing importer contract with VM settings; the
Docker-only importer must not be used for this image. Execute the reviewed
script once through Postgres MCP, then verify the saved records. Registration
does not make the app public. The test entry uses the default catalogue icon;
a public launch still needs its official icon and marketing assets.

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
The Compose health check waits for the upstream `init-script` service, which runs
after migrations and seeding, as well as HTTP health. The HTTP endpoint alone
returns success before initialization finishes. The dashboard route is configured
after account setup. The upstream production seeder owns proxy startup; the
package does not issue a competing start. Strict HTTPS verification retries for
up to 180 seconds while that queued start and the dashboard route become ready.
The VM callback depends on this setup and successful HTTPS verification, so a provisioning failure
cannot report installation success.

Keep automatic Coolify updates disabled for this package. The upstream updater
replaces Compose configuration, which needs separate validation against this
package's private ports and provisioning helper. An Appbox VM image update must
not replace a running guest's disk to upgrade Coolify; back up its state and
use a separately validated application update procedure.

## Domains and certificates

The existing `NginxService.php` stream map forwards each assigned SNI hostname
to the VM's port 443. The guest's Traefik terminates TLS and accepts nginx's PROXY protocol header
from this VM's bridge gateway only. First boot resolves the gateway from the
normal Appbox network route. Libvirt supplies
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

The image keeps its 32 GiB OS disk layout and creates an XFS filesystem at
`/data` using the remaining space assigned to the VM. It needs at least 34 GiB
of total disk capacity. Docker and containerd storage use this data filesystem,
as do Coolify, its databases and deployed projects. The normal root growth is
disabled with `/etc/growroot-disabled`; no shared Appbox installer change is
required. This avoids the first-boot ext4 growth stall observed on grant's
18000 GiB allocation.

The storage service runs before Docker, its early socket, and containerd. It omits
the normal service dependency on basic.target to avoid a socket ordering cycle,
and retains explicit filesystem and shutdown ordering. It accepts only the
sealed image's partition layout and records unique partition and filesystem
identities before initialization. It refuses a foreign partition or filesystem.
Later boots mount the same data filesystem and preserve its contents. The
original cached images remain underneath the Docker bind mounts on the OS disk.
Changing the VM's disk allocation later needs a separately verified data-growth
procedure; this initializer does not resize an existing data filesystem.

The r5 validation image skips automatic trimming until the first Coolify setup
has succeeded. Its own `fstrim.service` condition checks the existing readiness
marker; later scheduled runs keep the OS trimming service and schedule. This
is an A/B check of the r4 startup stall, which occurred after storage preparation
completed and automatic trimming started. It does not establish the underlying
cause or prove that later trimming is safe. Test an actual trim on the initialized
VM, followed by a reboot, before declaring this image ready.

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
# Linux only, required before each image release:
python3 coolify/tests/verify_systemd.py --package coolify
```

The Linux ordering check reproduces the previous callback reboot cycle and the
Docker socket/storage cycle. It loads the socket through sockets.target and
requires the corrected graph to pass without cycle warnings. The image callback drop-in avoids holding `multi-user.target` while it
waits for `cloud-final.service`, and retains explicit basic/shutdown ordering.

The tests exercise environment parsing, persistence, certificate/key matching,
wildcard coverage, renewal, private-file permissions, both Compose files and
blocking readiness when certificate or HTTPS checks fail.
They do not require a running Docker daemon. Ownership calls in the persistence
test are mocked; actual UID ownership still requires a root Linux VM test.

Required checks before publication and catalogue launch:

- Prepare, seal and boot two disposable guest clones; confirm their application
  secrets, database credentials, SSH keys and machine identities differ.
- Install the image normally on `grant`; check callback state, administrator
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

The clone disks and a checksum-verified sealed-image copy use private local
scratch storage under `/var/tmp` on the builder. The virtiofs home share retains
logs and receipts; nested guest disk I/O there exceeded the storage timeout.
Scratch disks are retained for diagnosis and must be removed after the tests.

`coolify/validate_clones.py` performs the isolated clone preflight on the designated
builder by default. The explicitly selected `--accelerator kvm` preflight is
restricted to root on the verified grant host `cylo13.ata.ams3.nl.cylo.net`, with
a root-owned private staging directory under `/var/tmp`, local scratch storage
and at least 16 GiB available memory. It runs the same two sequential 4-CPU,
8-GiB guests using hardware virtualization, with SSH forwarded on loopback only.
The hardware fixture attaches a local NoCloud seed ISO using the installed
`cloud-localds`, as the normal Appbox installer does. Its generated ISO contains
only disposable fixture data and is removed with the access material.
Hardware SSH uses a currently free loopback port from the existing
12801–12809 temporary-service pool, selected from its end. Occupied listeners
are preserved; the fixture does not change the host firewall.
It does not register libvirt domains, change shared services or publish an image.
It accepts a verified sealed-image receipt and a synthetic test bcrypt
hash, boots two fresh 64 GiB scratch overlays sequentially with SSH exposed on
loopback only, and uses a private fixture CA. Concurrent software-emulated
guests exceeded startup limits during cache copying and container initialization;
sequential execution retains the image and every timeout. It checks cold setup, root ownership, administrator
role, disabled registration and automatic updates, actual trimming, and a
subsequent reboot with independent secrets and preserved account state. Only
comparison booleans enter its receipt. Localhost key persistence is checked
against Coolify's canonical database key, rather than the bootstrap key filename.
The fixture allows up to five minutes for each clean guest poweroff and still
requires QEMU to exit successfully. The earlier two-minute final poweroff limit
expired while systemd was waiting for PHP and s6 processes in an emulated guest.
The callback is a local fixture, so this
check does not prove the normal Appbox callback, public stream TLS, or trimming
on grant's 18000 GiB allocation. Never supply a customer credential as its
fixture hash or publish an initialized clone disk.

Any missing required check leaves release readiness unconfirmed. Do not reuse
the desktop template-conversion script unchanged: it expects Selkies services.

Upstream: https://github.com/coollabsio/coolify

Certificate integration: https://coolify.io/docs/core/networking/proxy/traefik/custom-ssl-certs
