# iNiR Docker

Docker containers on your iNiR desktop. A port of
[devgtv/omarchy-docker](https://github.com/devgtv/omarchy-docker) to iNiR's
desktop-widget API.

It has no Omarchy-specific dependencies or configuration. It runs on any iNiR
3.x install with Docker installed and accessible.

## What it does

- **Monitoring summary**: running/total containers, aggregate CPU, aggregate
  memory, a CPU history sparkline and a memory bar.
- **Per-container bars**: each row shows state, CPU bar/percentage and memory
  bar/usage.
- Click a container to select it.
- Start, stop or restart it with a confirmation step.
- Open the last 200 log lines, or follow logs, in your terminal.
- Filter by name, image, state or Compose project from the widget settings.
- A compact line on the iRiS Island shows `running/total`.

Resource-limit sliders from the original Omarchy bar widget are not in this
version. The collector and Docker command helpers already support them, so they
can be added next.

## Install

From a Hub source:

```bash
inir hub install inir-docker
```

Or from a checkout of this folder:

```bash
mkdir -p ~/.config/inir/widgets
cp -r inir-docker ~/.config/inir/widgets/inir-docker
```

Then open **Settings → Desktop Widgets**, enable **iNiR Docker**, or add it from
edit mode. The widget id is `inir-docker`.

To reload after editing:

```bash
inir restart
```

## Configuration

| Key | Default | Meaning |
|---|---|---|
| `refreshSeconds` | `3` | How often the card reads Docker while visible |
| `maxContainers` | `6` | Rows shown before the `+N more` line |
| `showStopped` | `true` | Include exited/created containers |
| `showSummary` | `true` | Show the running/CPU/memory summary strip |
| `showSparkline` | `true` | Show the CPU history line |
| `filter` | empty | Literal text matched against name, image, state and Compose labels |

## Sidebar support

The current iNiR family sidebars do not expose a plugin-widget slot. The
Material left sidebar loads a fixed widget list, the Material right sidebar
loads a fixed tab list, and the iRiS sidebars use a fixed section catalogue.
Adding a Hub widget to those sidebars needs a family-side change, not a change
to this widget.

The drawing is split into `DockerBackend.qml` and `DockerView.qml` so a family
sidebar host can reuse it once such a slot exists.

## Requirements

- Docker CLI and a reachable Docker daemon.
- Access to the daemon, usually by being in the `docker` group or using rootless
  Docker. Membership in the `docker` group is effectively root-level access.
- `xdg-terminal-exec` for the log buttons. iNiR ships it on supported desktops;
  if it is missing, the lifecycle/status parts still work.

## Permissions

`process` — the widget runs the Docker CLI (`docker ps`, `inspect`, `stats`,
`start`, `stop`, `restart`, `logs`) and opens a terminal for logs.

It does not request `network`, `files` or `inject`. A remote Docker context can
still make the Docker CLI use the network; that is Docker's own configuration.

## Official Hub compatibility

The item is shaped like an official iNiR Hub widget:

- `widget.json` / `hub.json` follow the Hub schema.
- `translations/en_US.json` covers every `Translation.tr(…)` string.
- The code imports only the base and the widget SDK, not a family's internals.
- It uses no Omarchy files, services, paths or launcher commands.

The only optional external helper is `xdg-terminal-exec` for logs.

## Credits

- [devgtv/omarchy-docker](https://github.com/devgtv/omarchy-docker) — original
  widget, Docker model/parser and command helpers. MIT.
- iNiR's widget SDK and Hub conventions.

## License

MIT. The original copyright notice is preserved in [LICENSE](LICENSE).
