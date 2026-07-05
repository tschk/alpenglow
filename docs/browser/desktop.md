# Desktop (demo vs production)

The **browser demo** runs **cage** and **foot** under dinit with software rendering so v86 can show a framebuffer.

**Production** (`BUILD_PROFILE=desktop`) uses greetd, seatd, PipeWire, and **[Alpenglowed](https://github.com/tschk/alpenglowed)** on the immutable RAM-root image—not cage as the product compositor.