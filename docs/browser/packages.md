# Packages

Oil is Alpenglow's package manager.

The full system uses Oil for APK-compatible package metadata, installation
state, and immutable-image package selection. Package state belongs under
`/state`, not inside the replaceable root image.

This browser shell includes a tiny local Oil catalog so commands work without
network access:
oil search fetch
oil info fastfetch
oil install fastfetch

`fastfetch` is installed by default.
