```
    █████ ████   ███  █   █ █   █ ████   ███  █   █
    █     █   █ █   █ █   █ ██  █ █   █ █   █  █ █
    ████  ████  █████ █ █ █ █ █ █ ████  █   █   █
        █ █     █   █ ██ ██ █  ██ █   █ █   █  █ █
    █████ █     █   █ █   █ █   █ ████   ███  █   █
```

**v2.1.2 — One command. A fully managed Minecraft server.**

---

SpawnBox is a setup script for Linux. Point it at a machine running Ubuntu,
Debian, or Raspberry Pi OS, and it installs [Crafty Controller](https://craftycontrol.com)
— a free, open-source Minecraft server manager — along with [Docker](https://docker.com),
which Crafty runs inside. Optionally it can harden your server's security and
install [Playit.gg](https://playit.gg) so players can reach you from anywhere
without touching your router.

These are all independent, actively maintained open-source projects. SpawnBox
doesn't own them — it just makes getting them installed and working together
considerably less work.

```bash
curl -sSL -O https://raw.githubusercontent.com/pauldavid1974/spawnbox/main/spawnbox.sh
sudo bash spawnbox.sh
```

---

## ██ What SpawnBox Installs

### [Crafty Controller](https://craftycontrol.com)
> *"A free and open-source Minecraft server manager. Start and administer
> Minecraft servers from a user-friendly interface."*

Crafty is what you'll actually use day-to-day. Once SpawnBox is done, Crafty
gives you a web dashboard for creating servers, managing players, editing
settings, scheduling backups, and more — all from your browser.

### [Docker](https://docker.com)
> *"A platform designed to help developers build, share, and run container
> applications. We handle the tedious setup, so you can focus on the code."*

SpawnBox runs Crafty inside a Docker container. This keeps Crafty isolated,
makes it easy to update, and avoids conflicts with anything else on your
machine.

---

## ██ Optional Extras

SpawnBox will ask about these during setup. All are optional.

### Memory

| Option | What It Does | Recommended If... |
|---|---|---|
| **Swap File** | Adds 8 GB of virtual memory | Your machine has less than 16 GB of RAM |

### Security

SpawnBox can harden your server's security in up to three independent steps.
Pick exactly the ones you want.

| Option | What It Does |
|---|---|
| **Move SSH to port 54321** | Makes your SSH port harder to stumble across |
| **[UFW](https://help.ubuntu.com/community/UFW) Firewall** | *"A user-friendly way to create an IPv4 or IPv6 host-based firewall."* Blocks all incoming traffic except the ports Crafty and Minecraft need |
| **[Fail2ban](https://github.com/fail2ban/fail2ban)** | *"Scans log files and bans IP addresses that commit multiple authentication errors."* Automatically blocks brute-force login attempts |

### External Access

| Option | What It Does |
|---|---|
| **[Playit.gg](https://playit.gg)** | *"Host game servers from your own computer and let friends join from anywhere. No port forwarding required."* |

---

## ██ Quick Start

### Download and run (recommended)

```bash
curl -sSL -O https://raw.githubusercontent.com/pauldavid1974/spawnbox/main/spawnbox.sh
sudo bash spawnbox.sh
```

### Or with wget

```bash
wget https://raw.githubusercontent.com/pauldavid1974/spawnbox/main/spawnbox.sh
sudo bash spawnbox.sh
```

SpawnBox walks you through a short setup wizard, then shows a progress bar
while it works. When it's done you'll see something like this:

```
════════════════════════════════════════════════════════
  SpawnBox setup complete!
════════════════════════════════════════════════════════

  Crafty Controller:  https://192.168.1.50:8443

  Login credentials:
    Username: admin
    Password: a1b2c3d4

  Change your password after the first login!

  Install log: /var/log/spawnbox-install.log
```

Open that URL in your browser, log in, and create your first Minecraft server
from Crafty's dashboard.

---

## ██ System Requirements

| | |
|---|---|
| **OS** | Ubuntu 22.04+, Debian 11+, or Raspberry Pi OS |
| **RAM** | 4 GB minimum (8 GB+ recommended) |
| **Disk** | 10 GB free minimum |
| **Network** | Internet connection for initial setup |

SpawnBox does **not** install the operating system. It requires Linux to
already be running on the machine.

---

## ██ Connecting to Your Server

**On your home network** — no extra setup needed. Anyone on your Wi-Fi can
connect using the server IP shown in Crafty Controller.

**From outside your home** — your router blocks incoming connections by default.
[Playit.gg](https://playit.gg) solves this without requiring router access or
port forwarding. If you installed it during setup, run this on your server
to finish configuring it:

```bash
playit setup
```

Then share the tunnel address with your friends.

---

## ██ The Browser Warning

When you first open Crafty Controller, your browser will show a security
warning. That's expected — Crafty uses a self-signed HTTPS certificate. Click
**Advanced** and proceed. The connection is encrypted and safe.

---

## ██ Uninstalling

```bash
sudo bash spawnbox.sh --uninstall
```

SpawnBox will ask before removing anything. Your worlds and backups are never
silently deleted. If you enabled security hardening, it will offer to restore
your original SSH configuration.

To also remove Docker afterwards:

```bash
sudo apt-get remove docker-ce docker-ce-cli containerd.io
```

---

## ██ All Commands

```bash
sudo bash spawnbox.sh             # Launch SpawnBox (install or remove — the menu will ask)
sudo bash spawnbox.sh --uninstall # Go straight to uninstall
bash spawnbox.sh --version        # Show version
bash spawnbox.sh --help           # Show help
```

---

## ██ Support

SpawnBox installs third-party software. For help with those products, go to
their own documentation:

| Product | Support |
|---|---|
| **Crafty Controller** | [docs.craftycontrol.com](https://docs.craftycontrol.com) |
| **Docker** | [docs.docker.com](https://docs.docker.com) |
| **Playit.gg** | [playit.gg](https://playit.gg) |
| **UFW** | [help.ubuntu.com/community/UFW](https://help.ubuntu.com/community/UFW) |
| **Fail2ban** | [github.com/fail2ban/fail2ban](https://github.com/fail2ban/fail2ban) |

For bugs or issues with SpawnBox itself, [open an issue on GitHub](https://github.com/pauldavid1974/spawnbox/issues).

---

## ██ Credits

Built by [pauldavid1974](https://github.com/pauldavid1974) with AI
collaboration from [Claude](https://claude.ai) (Anthropic).

**License:** MIT — see [LICENSE](LICENSE) for details.
