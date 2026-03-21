# SpawnBox

**Turn any spare PC into a Minecraft server — one command, no expertise required.**

SpawnBox is a single bash script that takes a PC running Ubuntu (or Debian, or Raspberry Pi OS) and sets up everything you need to host Minecraft servers. You run one command. SpawnBox handles the rest.

```bash
curl -sSL -O https://raw.githubusercontent.com/pauldavid1974/spawnbox/main/spawnbox.sh
sudo bash spawnbox.sh
```

When it's done, you get [Crafty Controller](https://craftycontrol.com) — a browser-based panel where you can create, manage, and monitor Minecraft servers without touching a terminal again.

---

## What Gets Installed

SpawnBox installs two things:

| Component | What it does |
|---|---|
| [Docker](https://docker.com) | Runs Crafty in an isolated container |
| [Crafty Controller](https://craftycontrol.com) | Web panel for managing Minecraft servers |

That's it. SpawnBox is the installer — once setup is complete, Crafty manages its own updates and you manage your servers through Crafty's web interface.

## Optional Extras

During setup, SpawnBox will ask if you want any of these. All are optional — say no to everything and you still get a working Minecraft server manager.

| Feature | What it does | When to say yes |
|---|---|---|
| **Swap file** | Adds 8 GB of virtual memory | Your PC has less than 16 GB of RAM |
| **Security hardening** | Moves SSH to port 54321, enables firewall, installs brute-force protection | Your server is exposed to the internet |
| **Playit.gg tunnel** | Lets friends outside your home network connect without port forwarding | You want external players to join |

---

## System Requirements

- **OS:** Ubuntu 22.04+, Debian 11+, or Raspberry Pi OS
- **RAM:** 4 GB minimum (8+ GB recommended)
- **Disk:** 10 GB free minimum
- **Network:** Internet connection for initial setup

SpawnBox does **not** install the operating system. It assumes Linux is already running on the machine.

---

## Quick Start

### Option 1 — Download and run (recommended)

```bash
curl -sSL -O https://raw.githubusercontent.com/pauldavid1974/spawnbox/main/spawnbox.sh
sudo bash spawnbox.sh
```

### Option 2 — With wget

```bash
wget https://raw.githubusercontent.com/pauldavid1974/spawnbox/main/spawnbox.sh
sudo bash spawnbox.sh
```

SpawnBox walks you through a short setup wizard, then shows a progress bar while it works. When it's done you'll see something like this:

```
========================================================
  SpawnBox setup complete!
========================================================

  Crafty Controller:  https://192.168.1.50:8443

  Login credentials:
    Username: admin
    Password: a1b2c3d4

  Change your password after the first login!

  Install log: /var/log/spawnbox-install.log
```

Open that URL in your browser, log in, and create your first Minecraft server from Crafty's dashboard.

---

## Connecting to Your Server

### From your home network

No extra setup needed. Anyone on your Wi-Fi connects using the server's IP address shown by Crafty Controller. No port forwarding required.

### From outside your home network

Your router blocks incoming connections by default. The easiest way around this — no router access needed — is [Playit.gg](https://playit.gg), a free tunnel service built for exactly this situation.

If you chose to install Playit.gg during setup, run this on your server to configure it:

```bash
playit setup
```

Then share the tunnel address with your friends.

---

## Security Hardening

If you enable security hardening during setup, SpawnBox makes three changes:

1. **SSH moves to port 54321** — you'll need to connect with `ssh -p 54321 user@your-server` going forward
2. **UFW firewall** is enabled with a deny-by-default policy, allowing only the ports Crafty needs plus SSH
3. **Fail2ban** is installed to block repeated failed login attempts

A backup of your original SSH config is saved automatically. The uninstaller can restore it.

---

## Browser Security Warning

When you first open Crafty Controller, your browser will show a security warning. This is expected — Crafty uses a self-signed HTTPS certificate. Click "Advanced" and proceed. The connection is encrypted and safe.

---

## Uninstalling

```bash
sudo bash spawnbox.sh --uninstall
```

SpawnBox will ask whether to keep your Minecraft worlds and backups before removing anything. Your data is never silently deleted.

If you enabled security hardening, the uninstaller will offer to restore your original SSH configuration.

To also remove Docker afterward:

```bash
sudo apt-get remove docker-ce docker-ce-cli containerd.io
```

---

## Running the Script Again

Safe to do. SpawnBox checks for each component before installing and skips anything already present.

---

## Troubleshooting

**Crafty Controller isn't loading after install**

Give it a few minutes — Crafty sets up its internal database on first run. Check the log:

```bash
cat /var/log/spawnbox-install.log
```

**I enabled security hardening and can't SSH in**

SSH moved to port 54321. Connect with:

```bash
ssh -p 54321 user@your-server-ip
```

**Something went wrong during install**

The install log captures everything:

```bash
cat /var/log/spawnbox-install.log
```

If you're stuck, [open an issue on GitHub](https://github.com/pauldavid1974/spawnbox/issues) and include the relevant section of the log.

---

## Other Commands

```bash
sudo bash spawnbox.sh             # Install
sudo bash spawnbox.sh --uninstall # Uninstall
bash spawnbox.sh --version        # Show version
bash spawnbox.sh --help           # Show help
```

---

## What SpawnBox Does NOT Do

- Install the operating system
- Manage Minecraft server updates (Crafty does this)
- Run as a background service (it's a one-time installer)
- Configure your router or open ports (use Playit.gg instead)

---

## Credits

Built by [pauldavid1974](https://github.com/pauldavid1974) with AI collaboration from [Claude](https://claude.ai) (Anthropic).

Powered by [Docker](https://docker.com) and [Crafty Controller](https://craftycontrol.com).

## License

MIT — see [LICENSE](LICENSE) for details.
