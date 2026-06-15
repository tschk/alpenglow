# Alpenglow Build-Out Plan
#
# Goal: Turn the current boot-to-shell prototype into a daily-driver-capable
# Linux appliance OS with GUI, sound, WiFi, power management, and installer.
#
# Four phases:

# ── Phase 1: Service Foundation ──────────────────────────────────────────────
# Done: dinit (PID1), mount-filesystems, shell-ttyS0, networking (udhcpc),
#        state-mount, getty login, Oil package manager
# Done: seatd — device seat management (for Wayland)
# Done: iwd  — modern WiFi daemon (replaces wpa_supplicant) [2MB static]
# Done: greetd — login greeter [2.1MB static]
# Done: cage — wlroots kiosk compositor [61K + lib deps]
# Done: foot — Wayland terminal emulator [553K + lib deps]
# Done: pipewire + wireplumber — audio [16K + 20K + lib deps]
# Done: alpenglow-power.sh — direct /sys power management (no elogind needed)
# Replaced: elogind → seatd + alpenglow-power.sh (elogind is overkill for single-user appliance)
# Replaced: velox → cage (simpler wlroots compositor, fullscreen kiosk mode)
#
# Service dependency graph:
#   dinit -> mount-filesystems -> state-mount
#   dinit -> seatd -> cage (Wayland compositor)
#   dinit -> iwd -> networking
#   dinit -> pipewire -> wireplumber
#   dinit -> greetd -> cage
#   dinit -> foot -> cage (terminal launches inside cage)
#   dinit -> alpenglow-power (direct /sys, no elogind)

# ── Phase 2: Graphical Session ───────────────────────────────────────────────
# Current: cage (wlroots kiosk) + foot (Wayland terminal)
#   - cage runs as fullscreen Wayland compositor
#   - foot starts inside cage as the default app
#   - session-init script manages XDG_RUNTIME_DIR and cage launch
#
# Future: Replace cage/foot with Crepuscularity/GPUI desktop shell
#   - GPUI provides GPU-accelerated rendering, input, fonts
#   - Crepuscularity provides template DSL (`.crepus` files) + hot reload
#   - Needs a Wayland compositor underneath (cage is fine as host)
#   - See plans/crepuscularity-de.md for full plan
#
# Wayland infrastructure:
#   - /dev/shm mount (256M) for Wayland buffers
#   - XDG_RUNTIME_DIR management in session-init
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
# Crepuscularity/GPUI-based desktop shell (Phase 2 output):
#   - Single Rust binary, ~10MB static, GPU-accelerated
#   - Built from ../crepuscularity
#   - Runs as Wayland client inside cage (or a custom minimal compositor)
#   - Provides: desktop background, status bar, app launcher, settings panel

# ── Phase 4: Installer + Deployment ──────────────────────────────────────────
# Interactive GUI installer built with crepuscularity:
#   - Disk partitioning (GPT + Limine)
#   - Filesystem setup (ext4 state, GlowFS root)
#   - User creation
#   - WiFi configuration
#   - Bootloader install
#
# Build from crepuscularity GPUI target (see plans/crepuscularity-de.md):
#   crepus init gpui alpenglow-installer
#   Design UI in .crepus templates
#   Compile with view! macro for static binary
#   Embed in initramfs or state partition
#   Launch from dinit on install mode (kernel arg: alpenglow.install)
