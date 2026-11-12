# iNiR Docker

Docker containers on your iNiR desktop. It is a port of
[devgtv/omarchy-docker](https://github.com/devgtv/omarchy-docker) to iNiR's
desktop-widget API.

## What it does

- Shows running and stopped containers in a desktop card.
- Each row shows state, CPU and memory.
- Click a container to select it.
- Start, stop or restart it with a confirmation step.
- Open the last 200 log lines, or follow logs, in your terminal.
- Filter by name, image, state or Compose project from the widget settings.
- A compact line on the iRiS Island shows `running/total`.

Resource-limit sliders from the Omarchy bar widget are not in this first
version. The collector and Docker command helpers already support them, so they
can be added next.

## Install locally

```bash
mkdir -p ~/.config/inir/widgets
cp -r /home/misomarchy/inir-docker ~/.config/inir/widgets/inir-docker
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
| `filter` | empty | Literal text matched against name, image, state and Compose labels |

## Permissions

`process` — the widget runs the Docker CLI (`docker ps`, `inspect`, `stats`,
`start`, `stop`, `restart`, `logs`) and opens a terminal for logs.

It does not request `network`, `files` or `inject`. A remote Docker context can
still make the Docker CLI use the network; that is Docker's own configuration.

The user needs access to the Docker daemon, usually by being in the `docker`
group or by using rootless Docker. Membership in the `docker` group is
effectively root-level access.

## Differences from the Omarchy widget

| Omarchy | iNiR |
|---|---|
| Bar icon + popup panel | Desktop card + iRiS Island line |
| Keyboard-first popup | Mouse-first card, same actions |
| RAM/CPU limit sliders | Read-only CPU/RAM in v0.1; sliders next |
| `omarchy plugin install` | Hub item / `~/.config/inir/widgets` |

## Credits

- [devgtv/omarchy-docker](https://github.com/devgtv/omarchy-docker) — original
  widget, Docker model/parser and command helpers. MIT.
- iNiR's widget SDK and Hub conventions.

## License

MIT. The original copyright notice is preserved in [LICENSE](LICENSE).
