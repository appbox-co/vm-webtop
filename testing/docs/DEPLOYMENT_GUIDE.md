# Deployment guide: GNOME + RDP

## `appbox` password (cloud-init)

In production, create **`/tmp/user_pw`** containing the **plaintext** password for **`appbox`** (single line, no trailing newline required). On first boot, **`appbox-first-boot.service`** runs after **`cloud-config.service`** (the cloud-init stage that processes **`write_files`**), applies the password with **`chpasswd`**, stores the same value as GNOME Remote Desktop’s first-hop RDP secret, and deletes **`/tmp/user_pw`**.

Example in cloud-init **`runcmd`**:

```yaml
runcmd:
  - install -m 600 /dev/null /tmp/user_pw
  - echo -n 'YOUR_SECURE_PASSWORD' > /tmp/user_pw
```

If **`/tmp/user_pw`** is missing, first boot **does not** change the **`appbox`** password.

### Legacy **`HOME=/config`** in **`/etc/environment`**

Images migrated from the old Selkies/webtop installer may still have **`HOME=/config`** in **`/etc/environment`**. That breaks **`sudo grdctl --system`** and the **`gnome-remote-desktop`** daemon. The **`desktop`** installer removes that line when present. If you still see **`Init file credentials failed: Error creating directory /config`**, delete the line manually and **`sudo systemctl restart gnome-remote-desktop`**.

## Prerequisites

- Ubuntu **24.04 (noble)** or **26.04 (resolute)**.
- Root SSH or console access.
- Enough disk for **`ubuntu-desktop-minimal`** (order of **several GB**).
- Network for **`apt`** and **`snap`**.
- For cloud images: allow **`snap wait system seed`** to finish (the **`desktop`** installer waits when possible).

## Installation

```bash
git clone <your-fork-or-mirror>/vm_images.git
cd vm_images
sudo ./install.sh
```

Optional: **`sudo ./install.sh --skip-kernel-update`** if you do not want the **6.14** kernel path (see **`install.sh`** help).

## RDP port (`RDP_PORT`)

Production should expose the desired listen port as **`RDP_PORT`** before first boot. **`appbox-first-boot.service`** imports the environment from **`/etc/environment`** and **`/etc/default/appbox-first-boot`**, validates the port, and writes it to **`/etc/default/gnome-remote-desktop-appbox`** before **`appbox-configure-gnome-rdp.service`** runs.

Example (external mapped port **18691**):

```bash
sudo tee /etc/default/appbox-first-boot >/dev/null <<'EOF'
RDP_PORT=18691
EOF
sudo systemctl restart appbox-first-boot.service appbox-configure-gnome-rdp.service gnome-remote-desktop.service
```

For an image platform that writes **`RDP_PORT`** into **`/etc/environment`**, no extra file is needed.

## Appbox installed callback

Set **`APPBOX_INSTALLED_CALLBACK_URL`** before first boot to make **`appbox-first-boot.service`** send a one-time HTTP **POST** after local provisioning completes. The service also accepts **`APPBOX_CALLBACK_URL`** or **`APPBOX_API_CALLBACK_URL`** as aliases. If **`APPBOX_CALLBACK_TOKEN`** is set, it is sent as a bearer token.

If no callback URL is provided, the service skips the callback. Successful callbacks are stamped at **`/var/lib/appbox-first-boot/installed-callback.done`** so they are not repeated.

## RDP credentials (GDM / “Remote Login”)

1. **First factor (RDP)** — set with **`grdctl --system rdp set-credentials`** by the configure script:
   - Optional fixed values: **`GRD_RDP_USERNAME`** and **`GRD_RDP_PASSWORD`** in **`/etc/default/gnome-remote-desktop-appbox`**.
   - If **`/tmp/user_pw`** was present on first boot, this first-hop password is the same as the Linux **`appbox`** password.
   - Otherwise **`GRD_RDP_PASSWORD`** is used, or a random password is stored in **`/etc/gnome-remote-desktop/rdp-secret`** (read with **`sudo cat`**).
2. **Second factor (Linux)** — normal **GDM** login (e.g. user **`appbox`**).

**Important:** The **first** RDP username/password are **only** for GNOME Remote Desktop’s system handshake (whatever **`grdctl --system status --show-credentials`** prints as root). On provisioned templates, **`/tmp/user_pw`** keeps this first password aligned with the Linux **`appbox`** password. If **`/tmp/user_pw`** is not present, the first password may differ. Using the wrong first-hop password often fails with a generic client error such as **0x4**.

To see the active system RDP login (root only):

```bash
sudo grdctl --system status --show-credentials
```

## Microsoft Remote Desktop: disconnects **before** any login UI

If **Microsoft Remote Desktop** fails within a few seconds **with no credential window** (Windows **mstsc** or the **Mac / iOS / Android** app), it is usually **not** the Linux password yet. Typical causes:

### 0. **`use redirection server name:i:1` (Server Redirection / RDSTLS) — Windows *and* Mac**

GNOME **Remote Login** (system / headless RDP) uses **Server Redirection**: after the GDM hand-off, the client **disconnects and reconnects** with **one-time** credentials. Some Microsoft clients reused the **first** username/password instead of those one-time credentials, **failed authentication**, and closed the session in seconds — often **error 0x4** or “session ended” **before** any stable UI.

Microsoft documents that the RDP attribute **`use redirection server name`** is supported on **Mac** (and iOS/Android), not only on Windows: see [Remote Desktop URI scheme — Legacy `rdp` URI scheme](https://learn.microsoft.com/en-us/windows-server/remote/remote-desktop-services/remote-desktop-uri) (table includes **Mac** for `use redirection server name=i:<0 or 1>`).

**A. Windows (`mstsc.exe`)**

1. **Save As…** a **`.rdp`** file from **Remote Desktop Connection**.
2. Open it in **Notepad**, add: `use redirection server name:i:1`
3. For a custom port add e.g. `server port:i:18691`; **`full address:s:`** should be host or IP only (see example below).
4. Connect by **double-clicking** the **`.rdp`** file.

**B. macOS (“Windows App” / App Store “Microsoft Remote Desktop”)**

Microsoft’s **exported** `.rdp` files almost always contain **`use redirection server name:i:0`**. GNOME Remote Login **requires `1`**. If you leave **0**, you may see **GDM**, then a **black screen for ~10 seconds** and a disconnect — the same symptom as a failed post-redirect handshake ([GNOME #215](https://gitlab.gnome.org/GNOME/gnome-remote-desktop/-/issues/215), [Fedora thread](https://discussion.fedoraproject.org/t/remote-logins-from-window-cant-login-from-macos-gnome-rdp/114842)).

1. In the app, add your PC, then **export** the connection to a **`.rdp`** file (e.g. **⋯** menu → export / “Save as”).
2. Open that file in **TextEdit** or **VS Code** and **search for `redirection`**:
   - Change **`use redirection server name:i:0`** → **`use redirection server name:i:1`**
   - If **two** lines exist, **delete** the **`i:0`** line so only **`i:1`** remains.
3. **Delete** the old PC entry inside the app (so it cannot merge stale settings), then **Import from RDP file…** and connect using the **imported** PC — or connect by **double-clicking** the `.rdp` file in Finder.
4. Turn **off** any **“admin session”** / **“Connect to admin session”** style option if the client offers it (known to confuse some builds with GRD).
5. Optional sanity check: **`grep -i redirection your.rdp`** in Terminal should show **`i:1`** only.

See also [DEV — RDP 0x207 on Mac for Ubuntu](https://dev.to/emile1636/rdp-error-code-0x207-on-mac-for-ubuntu-24-d6d) (same **`i:0` → `i:1`** fix).

**Alternative on Mac — open an `rdp://` link** (attributes separated by **`&`**, URL-encoded spaces as **`%20`**). Example (replace host, port, user; encode `!` in passwords as `%21` if you embed a password, which is discouraged):

```
rdp://full%20address=s:YOUR.HOST.NAME&server%20port=i:18691&use%20redirection%20server%20name=i:1&username=s:appbox
```

Paste into **Safari** address bar or run `open 'rdp://…'` in Terminal to launch the client.

**Minimal `.rdp` snippet** (same file for Windows or Mac; align with **`sudo grdctl --system status --show-credentials`**):

```
full address:s:YOUR.HOST.NAME
server port:i:18691
use redirection server name:i:1
username:s:appbox
prompt for credentials:i:1
```

GNOME **46+** adds server-side **mstsc** detection; **Mac** is not identical — keep **`use redirection server name:i:1`** anyway. If the Mac client **connects but stays black** while Windows works, see upstream discussion (e.g. [Fedora Discussion — Remote logins from Windows, can’t login from macOS](https://discussion.fedoraproject.org/t/remote-logins-from-window-cant-login-from-macos-gnome-rdp/114842) and [GNOME/gnome-remote-desktop#215](https://gitlab.gnome.org/GNOME/gnome-remote-desktop/-/issues/215)).

**Reference (Windows client history + protocol):** [Headless remote sessions in GNOME, Part 3 — *Making Windows client work*](https://www.suse.com/c/headless-remote-sessions-in-gnome-part-3/).

### FreeRDP CLI (Linux / macOS) — try when GUI clients fail after GDM

[GNOME/gnome-remote-desktop#215](https://gitlab.gnome.org/GNOME/gnome-remote-desktop/-/issues/215) is largely about **non-`mstsc`** clients mishandling **server redirection** and **NLA** after the system daemon hands off to GDM / the user session. **FreeRDP 3.x** uses the same protocol family as **`gnome-remote-desktop`** and is a reasonable **next test** (still not a guarantee).

**Install**

- **macOS:** `brew install freerdp`, then run **`ls "$(brew --prefix freerdp)/bin" | grep -i freerdp`**. Use the **SDL** client (**`sdl-freerdp`**, **`sdl2-freerdp`**, or **`sdl3-freerdp`** — exact name depends on brew version): it works **without X11**. **`xfreerdp`** is **X11-only**; if you see **`failed to open display`** / **`$DISPLAY`**, either install and run [XQuartz](https://www.xquartz.org/) so **`$DISPLAY`** is set, or **switch to the SDL binary** (recommended on Mac).
- **Ubuntu / Debian (graphical desktop):** `sudo apt install freerdp3-x11`; use **`xfreerdp`** when logged into an X11 or XWayland session ([Ubuntu `xfreerdp` manpage](https://manpages.ubuntu.com/manpages/resolute/man1/xfreerdp3.1.html)).

**Credentials** — use whatever **`sudo grdctl --system status --show-credentials`** prints for the **first** hop (**`appbox`** + system RDP password by default), not necessarily the Linux **`appbox`** password (that is only at GDM unless you intentionally keep both passwords the same). Avoid **`/p:...` on the shell** if you care about process-list exposure; use **`/from-stdin`** (below) or **`FREERDP_ASKPASS`**.

**macOS example (SDL client — no XQuartz)** — same flags as **`xfreerdp`**; only the executable changes:

```bash
sdl-freerdp /v:YOUR.HOST.NAME:18691 \
  /u:appbox \
  /sec:nla \
  /cert:tofu \
  /server-name:YOUR.HOST.NAME \
  /size:1920x1080 \
  +clipboard \
  /from-stdin
# paste system RDP password at the prompt, then complete GDM in the window
```

If **`sdl-freerdp`** is not found, try **`sdl2-freerdp`** or **`sdl3-freerdp`** from the same **`brew --prefix freerdp/bin`** listing.

**Linux example (`xfreerdp`, from a local graphical session):**

```bash
xfreerdp /v:YOUR.HOST.NAME:18691 \
  /u:appbox \
  /sec:nla \
  /cert:tofu \
  /server-name:YOUR.HOST.NAME \
  /size:1920x1080 \
  +clipboard \
  /from-stdin
```

- **`/v:host:port`** — port can be here or **`/port:18691`** with **`/v:host`**.
- **`/sec:nla`** — system GRD expects **NLA** (CredSSP-style); do **not** force plain TLS-only.
- **`/cert:tofu`** or **`/cert:ignore`** — trust the server’s **self-signed** RDP cert (use **`tofu`** if you prefer pinning on first connect).
- **`/cert:tofu` and rotated server TLS** — If you **regenerated** the VM’s RDP certificate (**`RDP_TLS_REGEN=1`** or reinstall), FreeRDP keeps the **old** key under **`~/.config/freerdp/server/`** (e.g. **`HOSTNAME_PORT.pem`**) and may log **REMOTE HOST IDENTIFICATION HAS CHANGED** / **`Host key verification failed`**, then behave oddly. **Fix:** `rm -f ~/.config/freerdp/server/YOUR.HOST.NAME_18691.pem` (match your host and **`RDP_PORT`**), or use **`/cert:ignore`** only on throwaway labs. Then connect again with **`/cert:tofu`**.
- **`/server-name:`** — should match a name in the cert **CN/SAN** if you use **`tofu`** / name validation.
- **`/gfx`** — GNOME’s RDP server may **reject** clients that do not advertise the **graphics pipeline**; FreeRDP 3 enables compatible **GFX** caps by default — if you disabled codecs, re-enable **`/gfx`** (see manpage **`/gfx`**).

For flaky paths through **port forwards**, try disabling multitransport (UDP) if your build supports it (see **`/multitransport`** in the [same manpage](https://manpages.ubuntu.com/manpages/resolute/man1/xfreerdp3.1.html)).

**Client log: `ERRINFO_LOGOFF_BY_USER` ~30s after connect** — The message text says “user logged off” but **`gnome-remote-desktop`** often ends the RDP leg that way when the **system → session handover** fails or times out (same underlying situation as **`[DaemonSystem] Aborting handover`** + **`ERRINFO_CB_CONNECTION_CANCELLED`** on the server). **First** clear **stale FreeRDP TOFU certs** (previous bullet). If it still happens, the client still is not completing **redirection / RDSTLS** the way **`mstsc`** does — see [GNOME #215](https://gitlab.gnome.org/GNOME/gnome-remote-desktop/-/issues/215); use **`mstsc` from Windows** (or a **Windows VM** on the Mac) for a known-good path.

**If FreeRDP still fails** with **`MIC verification failed`** / **`Aborting handover`** in **`journalctl -u gnome-remote-desktop`**, the practical fix today remains **Windows `mstsc`** (or **`mstsc`** inside a small **Windows VM** on the Mac).

### A. **TLS name mismatch** (very common)

The RDP server presents a **self-signed** certificate. **Windows validates that the name or IP you typed under “Computer” appears in the certificate (CN/SAN).** If you connect to **`vm.example.com`** but the cert only contains **`ubuntugnome`**, the session is dropped **before** any prompt.

**Fix:** set **`RDP_TLS_CN`** and **`RDP_TLS_EXTRA_SAN`** in **`/etc/default/gnome-remote-desktop-appbox`** to include **every** DNS name and **public** IP clients use (comma-separated SAN fragment, same syntax as OpenSSL), then set **`RDP_TLS_REGEN=1`**, run:

```bash
sudo systemctl restart appbox-configure-gnome-rdp.service gnome-remote-desktop.service
```

Remove **`RDP_TLS_REGEN=1`** after one successful run so the key is not recreated every boot. The installer’s **`appbox-configure-gnome-rdp.sh`** (current tree) generates the cert with **OpenSSL** and SAN when **`openssl`** is installed.

### B. **Security negotiation** (NLA / “Hybrid”)

The system daemon expects **CredSSP-style** security. The built-in Windows client supports this; very old or odd clients may not. If you test from **Linux FreeRDP**, use **`/sec:nla`** (not plain **`/sec:tls`**).

### C. **UDP / network path** (especially through port forwards)

- **Windows client:** force **TCP-only** (see **§ “error code 0x4”** below: Group Policy / **`fClientDisableUDP`**).
- **Mac:** there is no identical registry switch; try **another network** (no VPN / hotspot), ensure the **port** field matches **`RDP_PORT`**, delete and **re-import** the PC after editing the **`.rdp`** file, and update **Microsoft Remote Desktop** / **Windows App** from the App Store. IPv6-only paths sometimes misbehave — prefer **IPv4** naming if you have both.

### D. **Black screen after login, then disconnect (~10 seconds)**

You reached **GDM** and authenticated, but the desktop never paints and the client drops.

1. **macOS and most non-Windows RDP clients (very common)** — After GDM, **system** GRD performs **server redirection** and expects the client to complete a second connection using **one-time** credentials (**RDSTLS** / redirection semantics). **Microsoft’s Mac “Windows App”** often breaks this (wrong **`.rdp`** defaults — **§0.B**). **Royal TSX**, **Devolutions Remote Desktop Manager**, and similar clients frequently show the **same black screen ~10s then disconnect** because they **do not implement that handover the way Windows `mstsc.exe` does** — switching between Mac RDP apps usually **does not** fix it. See [GNOME/gnome-remote-desktop#215](https://gitlab.gnome.org/GNOME/gnome-remote-desktop/-/issues/215), [Devolutions forum — wrong credentials on redirection to GRD](https://forum.devolutions.net/topics/42273/cant-connect-to-gnome-remote-desktop-session-on-windows-1011-client-se), and [SUSE — headless GNOME RDP, part 3](https://www.suse.com/c/headless-remote-sessions-in-gnome-part-3/) (why **mstsc** is the reference client).

   **What actually works today for “Remote Login” (system GRD):**

   - Connect with **Windows Remote Desktop Connection (`mstsc.exe`)** from a **real Windows** PC (or a **small Windows VM** on your Mac — e.g. Parallels / UTM / VMware — solely to run **mstsc**), using a **`.rdp`** that includes **`use redirection server name:i:1`** as in **§0**.
   - Treat **Mac-native RDP** to system GRD as **best-effort** until upstream clients ship full redirection parity.

   **Optional:** try a **current** [**FreeRDP**](https://www.freerdp.com/) **3.x** client on macOS (**Homebrew** `freerdp`, then **`sdl-freerdp`** / **`sdl3-freerdp`** — not **`xfreerdp`** unless XQuartz provides **`$DISPLAY`**) with **`/sec:nla`**, **`/cert:ignore`** or **`/cert:tofu`**, and your **`RDP_PORT`** on **`/v:host:port`** — see **§0 — FreeRDP CLI** above. Some builds handle GRD better than GUI clients, but this is **not guaranteed** (library and server evolve together).

2. **Ubuntu 26.04 (resolute) — do *not* disable Wayland for GDM** — Upstream removed the **GNOME-on-Xorg** session; **`WaylandEnable=false`** in **`/etc/gdm3/custom.conf`** can leave **no valid GNOME session** (only **`/usr/share/wayland-sessions/*.desktop`** exists for the default desktop). If you added that line while troubleshooting, **remove** **`WaylandEnable=false`** and run **`sudo systemctl restart gdm3`**. The **`desktop`** installer applies the GDM Xorg tweak **only on Ubuntu 24.04 (noble)**.

3. **Ubuntu 24.04 (noble) only** — If you still see a black screen after login on Wayland-only setups, **`WaylandEnable=false`** under **`[daemon]`** in **`/etc/gdm3/custom.conf`** may help (PipeWire / session quirks). Then **`sudo systemctl restart gdm3`**. See [Ask Ubuntu — Remote Login black screen](https://askubuntu.com/questions/1536073/ubuntu-24-04-remote-login-connects-to-black-screen).

4. **Windows `mstsc` quirks** — **TCP-only** (**§ 0x4**), turn off **persistent bitmap caching** (**mstsc → Show Options → Experience**).

5. **Logs** (one failed connection, from the server): **`journalctl -u gnome-remote-desktop -b --no-pager`**, **`journalctl -u gdm3 -b --no-pager`**, and **`journalctl _COMM=gnome-shell -b --no-pager`** (or **`journalctl --user -b`** as **`appbox`**). Look for **`ERRINFO_LOGOFF_BY_USER`**, **`routing token`**, or **PipeWire** errors.

6. **`[DaemonSystem] Aborting handover` + `ERRINFO_CB_CONNECTION_CANCELLED [0x00010409]`** — In Microsoft’s RDP error set, **`ERRINFO_CB_CONNECTION_CANCELLED`** is a **connection-broker–style** “cancelled” code; **FreeRDP** logs it when **`gnome-remote-desktop-daemon`** tears down the peer **after aborting the system → greeter/user handover**. So this pair usually means **“handover did not finish in time (or failed); the daemon closed the RDP session.”** It is **not** a precise root cause by itself — look **earlier** in the same second/minute for **`[DaemonHandover]`**, **`Failed to start handover`**, **`Error sending server Redirection`**, **`UnknownObject`**, **`org.freedesktop.secrets` timeouts**, or greeter **`gnome-shell` / `gsd-*` errors**. Real-world threads: [Ubuntu Discourse — GRD on 25.04](https://discourse.ubuntu.com/t/unable-to-connect-to-gnome-remote-desktop-on-ubuntu-25-04/66251) (Remmina / Connections, white screen ~30s, same log lines), [NixOS/nixpkgs#504490](https://github.com/NixOS/nixpkgs/issues/504490) (**handover daemon never starts** in GDM greeter — **~30s** then identical abort; points at **`gsd-remote-desktop`** / **gnome-settings-daemon** in the greeter session), [Ask Ubuntu — headless GRD on Raspberry Pi](https://askubuntu.com/questions/1536706/help-with-blank-screen-accessing-gnome-remote-desktop-headless-24-04-raspi) (same **`Aborting handover`** message). With **Mac / third-party clients**, the handover often never completes on the **client** side even when the server is healthy — compare **`mstsc` from Windows** in the same environment.

---

## Microsoft Remote Desktop: “session ended” / **error code 0x4**

This code is vague; most cases here boil down to **wrong first-hop credentials**, **wrong port**, **client UDP quirks**, or **TLS trust**.

### 1. Confirm first-hop credentials and port

- Run **`sudo grdctl --system status --show-credentials`** on the server and enter **that** username and password in the **first** RDP prompt (before GDM appears).
- **`sudo ss -tlnp`** on the server must show **`gnome-remote-desktop`** listening on the same **TCP** port your client uses (see **`RDP_PORT`** in **`/etc/default/gnome-remote-desktop-appbox`**). If you port-forward **18691** on the edge, **`RDP_PORT`** on the VM should be **18691** (then restart **`appbox-configure-gnome-rdp.service`** and **`gnome-remote-desktop`**).

### 2. Force **TCP-only** on the Windows RDP client (UDP issues)

Some Windows and Mac clients negotiate **UDP** for RDP; if only TCP is forwarded or UDP is flaky, you can get **0x4** immediately.

**Windows (client PC):**

- Group Policy: **Computer Configuration → Administrative Templates → Windows Components → Remote Desktop Services → Remote Desktop Connection Client → Turn off UDP on client** → **Enabled**
  **or**
- Registry: **`HKLM\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services\Client`**, DWORD **`fClientDisableUDP`** = **`1`**, then reboot the **client**.

**Mac (Microsoft Remote Desktop from the App Store):** update the app; try a **new PC profile** with the **port in the dedicated Port field** (not only in the PC name). If disconnects persist, try from a **Windows** client with UDP disabled as above to isolate the issue.

### 3. Self-signed TLS certificate

The server uses a **self-signed** RDP certificate. Accept any certificate warning if the client offers it. If the session drops with **0x4** before a prompt appears, rule out **wrong port** and **UDP** first.

### 4. Reset system RDP password (optional)

```bash
sudo grdctl --system rdp set-credentials appbox 'YourNewStrongPassword'
sudo systemctl restart gnome-remote-desktop
```

Then use **`appbox`** / **`YourNewStrongPassword`** at the **first** RDP prompt, and your Linux user (**`appbox`**) + Linux password at **GDM**.

## Useful commands

```bash
systemctl status gdm3 gnome-remote-desktop appbox-configure-gnome-rdp
grdctl --system status
journalctl -u gnome-remote-desktop -b --no-pager
sudo ss -tlnp | grep -E '3389|18691'
```

## Firewall

Open the **same TCP port** as **`RDP_PORT`** (e.g. **`ufw allow 3389/tcp`** or your cloud SG).

## Polkit / grdctl

If **`grdctl --system`** fails with **pkexec** errors, ensure **`polkitd`** and **`pkexec`** are installed (the **`desktop`** installer pulls them in).

## Wallpaper and dconf

Defaults live under **`/etc/dconf/db/local.d/`** and **`/etc/dconf/db/gdm.d/`**. After manual edits, run **`sudo dconf update`**.

## Migrating from older images

Older Selkies/webtop images used **`/config`** as the desktop user home. New **`desktop`** images use **`/home/appbox`**. The installer **does not** delete **`/config`** (it may still exist on migrated disks with unrelated data). It **does** strip **`HOME=/config`** from **`/etc/environment`** when present — that line breaks **`gnome-remote-desktop`**.

## GDM: login screen vs automatic login

**Default (recommended):** **`appbox`** signs in at the **GDM** screen after the **first** RDP hop (system **`grdctl`** credentials). You get a **second factor** (Unix password) and can add other local users later.

**Automatic login (`AutomaticLoginEnable` in `/etc/gdm3/custom.conf`):**

- **Does not fix** Mac / non-**`mstsc`** **Remote Login** handover issues ([GNOME #215](https://gitlab.gnome.org/GNOME/gnome-remote-desktop/-/issues/215)) — the fragile step is **system daemon → session**, not “typing at GDM”.
- **Weakens security:** anyone who learns the **system RDP** password can reach a **fully logged-in desktop** with **no** second password at the greeter (unless you rely on other controls).
- **Changes boot semantics:** a graphical **`appbox`** session may already be running at boot; **Remote Login** / **Desktop Sharing** behaviour vs a **cold greeter** can differ — test before relying on it in production.

Use **automatic login** only for **single-tenant throwaway labs** where you accept that trade-off; keep **GDM login** for anything shared or internet-exposed.

## Uninstall / rollback

There is no automated uninstall. Snapshot the VM before installing, or remove packages manually (**`ubuntu-desktop-minimal`**, **`gnome-remote-desktop`**, etc.) according to your policy.
