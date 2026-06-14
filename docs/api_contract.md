# Alpenglow / Desktop Contract

This repo treats this repository as the desktop environment and [RV8](https://github.com/tschk/rv8) as the browser-engine boundary. Alpenglow owns the appliance OS, service bridge, kernel policy, and installable runtime image.

## Services

- `LifecycleService`
  - `create_session()`
  - `open_tab(session, initial_url)`
  - `close_tab(tab)`
- `NavigationService`
  - `navigate(tab, url)`
  - `reload(tab)`
- `DomService`
  - `get_dom_snapshot(tab)`
  - `click(tab, node_id)`
- `DiagnosticsService`
  - `engine_state()`

## Capability / handle types

- `SessionHandle`
- `TabHandle`
- `WindowHandle`
- `CapabilityToken`

## Ownership

- `rv8`: engine loop, scheduler, tab/session model, service contracts, optional FFI
- `alpenglow`: desktop browser shell, modes, compositor/input integration, RV8 integration, control plane
- `alpenglow`: appliance runtime, kernel policy, service bridge, install image, local tools, and backend packaging
