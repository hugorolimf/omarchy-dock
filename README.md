# Dock

A macOS-style dock for the Omarchy shell: pinned and running apps, hover
magnification, auto-hide, and real Liquid Glass.

- **One dock per screen.** Each dock shows the apps and the Hyprland
  workspaces of its own monitor (mini icons of their windows; click or scroll
  to switch).
- **Pinned and running apps.** Right-click to pin, unpin, move a window to
  another workspace, or quit the app. Drag icons to reorder; dropping a
  running app among the pinned ones pins it.
- **Click like a taskbar.** Click opens the app, focuses it, cycles through its
  windows, or minimizes it when it is already focused. Minimized windows come
  back from their icon.
- **Apps running in the background** (window closed, process alive) keep a dot.
- **Auto-hide** with a reveal delay, and also while a maximized window fills the
  screen (when your window script reports it, see below).
- **Liquid Glass.** With the [Liquid Glass](https://github.com/fasi96/omarchy-liquid-glass)
  plugin installed, one switch puts refractive glass behind the dock.
- Size, compact mode, magnification, opacity and workspace badges are all set
  from the dock's bar panel.

## Install

```bash
omarchy plugin add https://github.com/hugorolimf/omarchy-dock --enable
omarchy-restart-shell
```

The dock is a `keepLoaded` panel, so the shell has to restart once after
installing or updating it. Then add the **Dock** widget to the bar (Omarchy
menu → bar settings) to reach its settings.

## Requirements

- Omarchy with the Quattro shell (Quickshell) and Hyprland's Lua config.
- Optional: [Liquid Glass](https://github.com/fasi96/omarchy-liquid-glass) for the
  glass effect. Without it the dock uses a translucent plate.

Nothing else is installed and no system file is touched.

## Files it writes

- `~/.local/state/omarchy/io.github.hugorolimf.dock/`: pinned apps, settings, and
  the height each dock covers on its monitor.
- `~/.local/state/omarchy/toggles/hypr/hugorolimf-dock-glass.lua`: only while
  Liquid Glass is switched on from the dock's panel. Omarchy loads files in this
  folder on every Hyprland reload; switching the glass off deletes it.

## Window scripts (optional)

On a stock Omarchy the dock reserves its height, so tiled windows stop above it,
and it uses plain Hyprland dispatchers to focus, minimize (to
`special:minimized`) and close windows.

If your Hyprland Lua config defines any of these global functions, the dock calls
them instead and stops reserving space (your script is then expected to keep
windows clear of the dock, reading `cover-<monitor>` in the state folder):

| Function | Called when |
|---|---|
| `windowing_raise(address)` | focusing a window |
| `windowing_minimize(address)` | minimizing from the dock |
| `windowing_quit(class)` | Quit from the right-click menu |
| `windowing_refit(monitor)` | the dock shows or hides |

A script may also write `address workspace monitor` lines to
`<state folder>/maximized`; the dock then hides while such a window fills its
monitor.

## Remove

```bash
omarchy plugin remove io.github.hugorolimf.dock
rm -rf ~/.local/state/omarchy/io.github.hugorolimf.dock
rm -f ~/.local/state/omarchy/toggles/hypr/hugorolimf-dock-glass.lua && hyprctl reload
omarchy-restart-shell
```

## License

[MIT](LICENSE) © Hugo Rolim Filho
