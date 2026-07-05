# Packages (demo)

**Oil** is Alpenglow’s package manager. Recipes under `system/oil/recipes/` describe APK payloads Oil fetches and extracts; registry mirrors are used only as a package source, not as the OS.

```sh
oil search fastfetch
oil info fastfetch
oil install fastfetch
```

`fastfetch` is installed at image build time via `oil install-recipe`. On a full system, install state lives under `/state`, not in the immutable root image.
