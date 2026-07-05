# Profiles

Alpenglow separates build profiles from kernel profiles.

Build profiles:
minimal - boot, shell, network, SSH, time, logs, DNS, OOM guard
standard - minimal plus compiler/tooling, network tools, filesystem tools
desktop - standard plus Wayland, audio, WiFi, greetd, Alpenglowed, foot

Kernel profiles:
fast - smallest headless diskless boot path
minimal - networked appliance kernel with cgroups, PSI, zram, seccomp, Landlock
desktop - minimal plus display, audio, USB, HID, WiFi, Bluetooth, firmware
