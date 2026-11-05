# Espresso

A menu bar app that keeps your Mac awake. No account and no App Store: you build it yourself.

- Keep awake indefinitely, for 30 minutes to 8 hours, until an app quits, or until downloads finish.
- Keep the screen on, or let it sleep while the Mac stays awake.
- Optionally stay awake with the lid closed.
- Stop automatically at a battery level you pick, 5% to 50% (default 20%, on battery only).
  Click the battery tile to change the level or turn the stop off.
- Animated coffee cup in the menu bar, with the time left for timed sessions.

Left-click the cup for the panel. Right-click (or Control-click) to start or stop right away.

## Build and install

Needs macOS 14 or later and the Command Line Tools (`xcode-select --install`). Xcode isn't needed.

```bash
make install
```

This builds a release, assembles `build/Espresso.app`, signs it ad hoc, copies it to `~/Applications` and opens it.
Other targets: `make app` (build only), `make test`, `make previews`, `make clean`.

If macOS asks about Espresso when it first looks at your Downloads folder, allow it; "until downloads finish" needs it.

## How it stays awake

Espresso holds the same IOKit power assertions that `caffeinate` uses:

| Option | Hold |
|---|---|
| Session running | `PreventUserIdleSystemSleep` |
| Screen on | `PreventUserIdleDisplaySleep` |

macOS drops these holds the moment Espresso quits or crashes. Check them with `pmset -g assertions`.

`/usr/bin/caffeinate` stays where it is. It's part of the sealed system volume and does nothing unless something runs it.

## Lid closed mode

Power assertions don't stop a MacBook from sleeping when you close the lid. Only the system setting
`pmset -a disablesleep 1` does that, and changing it needs admin rights.
When a session starts with **Lid closed** on, Espresso asks for your admin password through the standard
macOS prompt.

To make sure this setting never stays on by accident:

1. A small watchdog process starts right after the setting changes. It runs in its own process group,
   so it outlives Espresso.
2. When Espresso stops the session, quits, crashes or is killed, the watchdog runs `pmset -a disablesleep 0`
   within 2 seconds.
3. If the setting is ever found on outside a session, the panel shows a **Restore** button.

Don't run a closed MacBook in a bag: it can overheat.

### Optional: no password prompt

If you'd rather not type your password each session, allow exactly these two commands without a password.
Run this yourself and replace `you` with your short user name (`whoami`):

```bash
sudo visudo -f /etc/sudoers.d/espresso
```

Add this line, then save:

```
you ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 1, /usr/bin/pmset -a disablesleep 0
```

Espresso detects the rule and stops asking. To undo it: `sudo rm /etc/sudoers.d/espresso`.

## Open at login

The **Open at login** switch registers Espresso with macOS. If macOS needs your approval, the panel says so;
allow it in System Settings › General › Login Items.

## Layout

```
Sources/EspressoKit/Power    power holds, lid-closed mode, watchdog
Sources/EspressoKit/System   shell, battery, downloads
Sources/EspressoKit/Model    sessions and panel state
Sources/EspressoKit/UI       cup drawing, panel, icon renderer
Sources/EspressoKit/App      app delegate, menu bar item
Sources/espresso-render      build tool: app icon and preview images
Tests/EspressoKitTests       unit tests, including the real watchdog loop
```
