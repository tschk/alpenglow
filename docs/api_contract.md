# Alpenglow / Desktop Contract


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

- `alpenglow`: appliance runtime, kernel policy, service bridge, install image, local tools, and backend packaging
