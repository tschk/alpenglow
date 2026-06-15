# Alpenglow Build-Out Plan
#
# Goal: Turn the current boot-to-shell prototype into a daily-driver-capable
# Linux appliance OS with GUI, sound, WiFi, power management, and installer.
#
# Four phases:

# ── Phase 1: Service Foundation ──────────────────────────────────────────────
# Done: dinit (PID1), mount-filesystems, shell-ttyS0, networking (udhcpc),
#        state-mount, getty login, Oil package manager
#
# ADD:  seatd         — device seat management (for Wayland)
# ADD:  elogind       — session tracking, logind API, power/suspend
# ADD:  greetd        — login greeter (for graphical sessions)
# ADD:  iwd           — modern WiFi daemon (replaces wpa_supplicant)
# ADD:  pipewire      — audio server (replaces PulseAudio)
# ADD:  wireplumber   — session/policy manager for PipeWire
# ADD:  TLP / power   — power management daemon (or elogind handles this)
# ADD:  velox         — Wayland compositor (Rust, wlroots-based)
# ADD:  foot          — Wayland terminal emulator
#
# Package deps for each service (static musl builds via Docker):
#   seatd:     seatd, libseat
#   elogind:   elogind, libelogind
#   greetd:    greetd, agreety (or cage + greeter)
#   iwd:       iwd, ell
#   pipewire:  pipewire, pipewire-pulse, libpipewire
#   wireplumber: wireplumber
#   TLP:       tlp, (or just elogind power management)
#   velox:     velox (Rust crate, needs wlroots)
#   foot:      foot (Wayland terminal)
#
# Service dependency graph:
#   dinit -> mount-filesystems -> state-mount
#   dinit -> elogind -> seatd
#   dinit -> iwd -> networking
#   dinit -> pipewire -> wireplumber
#   dinit -> greetd -> seatd
#   dinit -> velox -> seatd
#   dinit -> foot -> velox

# ── Phase 2: Graphical Session ───────────────────────────────────────────────
# Build and configure velox (Rust Wayland compositor):
#   - Read velox source from ../velox or build from git
#   - Configure as dinit service starting after seatd
#   - Bind graphical session as getty alternative
#   - Fall back to cage + agreety if velox unavailable
#
# Terminal emulator:
#   - foot as default terminal
#   - Alacritty as fallback (Rust, heavier)
#
# Wayland infrastructure:
#   - /dev/shm mount (256M) for Wayland buffers
#   - XDG_RUNTIME_DIR management in session init
#   - wlr-randr for display configuration
#   - kanshi for multi-monitor

# ── Phase 3: Full Desktop ────────────────────────────────────────────────────
# App launcher:   bemenu or fuzzel (Wayland-native)
# Status bar:     waybar or eww
# Notification:   mako or fnott
# Screenshot:     grim + slurp
# Clipboard:      wl-clipboard
# Wallpaper:      swaybg or mpvpaper
# File manager:   lf (terminal) or thunar (GUI)
# Browser:        Already handled by soliloquy (no RV8 in Alpenglow)
#
# Ployglot web app support via crepuscularity-lite (V8 embedded GPUI shell):
#   - Can run web apps as native windows
#   - Uses Capacitor-shaped plugin API
#   - Built from ../crepuscularity

# ── Phase 4: Installer + Deployment ──────────────────────────────────────────
# Interactive GUI installer built with crepuscularity:
#   - Disk partitioning (GPT + Limine)
#   - Filesystem setup (ext4 state, GlowFS root)
#   - User creation
#   - WiFi configuration
#   - Bootloader install
#
# Build from crepuscularity GPUI target:
#   crepus init gpui alpenglow-installer
#   Design UI in .crepus templates
#   Compile with view! macro for static binary
#   Embed in initramfs as /sbin/alpenglow-installer
#   Launch from dinit on install mode (kernel arg: alpenglow.install)
