# omawayback on Omarchy: design notes

Goal: record a machine the way Omarchy sees it ("Tokyo Night, JetBrains
Mono, these git themes, these packages beyond Omarchy's, Signal via its
installer"), not only as files, so that a rollback or a fresh install can
work at Omarchy's level: what to set again, not which bytes to copy.

Researched against Omarchy 4.5.0 (561 `omarchy-*` commands).

## Rules

- **Read-only.** Files, and commands whose only job is to print. Never a
  setter, not even a setter's no-argument form (`omarchy-default-editor`
  with no argument prints today, but its job is setting). Never the
  migrator (`omarchy-migrate --pending` is read-only, but an Omarchy that
  dropped the flag would run migrations), so pending migrations are
  counted from the files.
- **Never `omarchy-debug`**: it uploads logs unless given `--print`.
- **Use Omarchy's own tests, don't invent new ones**: `omarchy-pkg-defaults`
  for the stock set, the `.git` test from `omarchy-theme-extras`, the `Exec=`
  tests from `omarchy-webapp-remove-all` and `omarchy-tui-remove-all`.
- **Default `OMARCHY_PATH`** to `/usr/share/omarchy`: it is unset over ssh,
  and Omarchy commands that read it break without it.
- **Same answer from every context.** The timer, a terminal and ssh must
  record the same thing, or every switch is a commit. `XDG_CURRENT_DESKTOP`
  defaults to Hyprland; Hyprland is found through `hyprctl instances`; with
  no session the last health reading is kept, not replaced by "unknown".
- **Omarchy changes shape.** What cannot be found reads `-`, never an
  error. Each Omarchy release needs a test pass; a daily-driver Omarchy
  machine is the canary.

## 1. The profile (done, 0.3.0)

`inventory/omarchy/` in every capture:

| File | Source |
|---|---|
| `settings.txt` | `omarchy-version`, `-version-channel`, `-hw-platform`, `-font-current`, `-cmd-default-browser`; `xdg-terminal-exec --print-id`; `current/theme.name`, `current/background`; `defaults/editor` (state), `defaults/{agent,dictation}` (config); `preinstalls-removed` flag |
| `packages.txt` | explicit packages minus (`omarchy-pkg-defaults` + `install/omarchy-other.packages` + the `omarchy` package's dependencies); `pacman -T` over the defaults for what is missing (it resolves provides: nvim is neovim) |
| `themes.txt` | `~/.config/omarchy/themes/*`: git origin and commit, link target, or local |
| `plugins.txt` | `~/.config/omarchy/plugins/*/manifest.json` id; placement from `shell.json` `bar.layout`; source as for themes |
| `apps.txt` | `~/.local/share/applications/*.desktop` by `Exec=`; compared with `$OMARCHY_PATH/applications` |
| `toggles.txt` | flag files in `state/omarchy/toggles/`; `toggles/hypr/*.lua` except `flags.lua` |
| `hooks.txt` | `hooks/<name>` and `hooks/<name>.d/*`, without `*.sample` (omarchy-hook skips them) |
| `configs.txt`, `shipped/` | every file in `$OMARCHY_PATH/config` except samples: same, custom or absent, with the shipped hash; a copy of the shipped file for each custom one |
| `migrations.txt` | markers in `state/omarchy/migrations`, each with the first `echo` of its script |
| `health.txt` | pending migrations; `hyprctl -j configerrors` |

Package attribution, in order of trust:

1. **installer**: named on a `pacman -r /mnt -S` line in
   `/var/log/pacman.log`, i.e. the original install. A record, so it wins.
   Includes packages Omarchy no longer ships by default (kdenlive, obs).
2. **omarchy-install-X**: named after `omarchy-pkg-add` or
   `omarchy-pkg-aur-add` in the script, or listed in its
   `omarchy:args=<a|b|c>` when the script installs the one you pick
   (terminals).
3. **menu:ID**: the packages argument of an `omarchy-install-and-launch`,
   `-app` or `-font` action in `omarchy-menu.jsonc`.

Known gaps: browser and editor installers that pick their package at run
time are attributed only where the name is literal; menu actions that
compute the package (Ollama) are not attributed.

Why `shipped/`: comparing your file with today's shipped file cannot say
who changed what. With the shipped version in every capture, an update that
changes a default under your customization is visible
("omarchy changed defaults you customize"), and the history holds the base
for a three-way merge.

## 2. `omawayback show` and `changes` (done, 0.4.0, 0.4.1; flat names since 0.8)

- `omawayback show [REV]`: the profile, readable: what this machine is,
  beyond stock Omarchy. Packages grouped by what installed them; plugins
  by bar position, marked local or linked when a URL cannot bring them back.
- `omawayback changes FROM [TO]`: changes between two captures at
  Omarchy's level: the commit-message section for any range (endpoints
  compared, so every migration in between shows), plus packages beyond
  Omarchy's set. Default: the last capture against the one before.
- `omawayback changes`: only the captures where the profile changed in
  a way `diff` reports (not the background hash, attribution details or
  a carried-forward health reading), newest first, each with its changes
  and `-m` label; it ends at the first capture with a profile.

## 3. `omawayback replay [REV]` (done, 0.5.0)

Prints a script that rebuilds the setup on a fresh Omarchy, using
Omarchy's own commands. Never runs it.

Order: Omarchy installers for what one installed (with its choice when
it takes one: `omarchy-install-terminal ghostty`), then `omarchy-pkg-add`
/ `-aur-add` one package per line (a renamed package stops only itself);
git themes by `git clone` to the recorded name, because
`omarchy-theme-install` switches to each theme it installs;
`omarchy-plugin-add URL --yes`, with placement from the restored
`shell.json` (or `omarchy-plugin-enable --section` when shell.json is not
customized); toggles that were on; one `omawayback restore` (one capture)
of local themes and plugins, apps and their icons, hooks, customized
configs, files you added to directories Omarchy configures (the largest
directories that hold nothing Omarchy ships; backups and locks left out)
and `theme-backgrounds`; `omarchy-restart-shell`; then font, theme,
background, `omarchy-default-*` last.

Left as comments and listed at the end: installers that ask (gum or read)
or need a choice none of their packages names; `omarchy-default-agent` and
`-dictation`, which open a terminal to install or launch; linked themes
and plugins; every removal (`omarchy-pkg-drop`, `omarchy-remove-preinstalls`,
deleted shipped apps). The script keeps going past a failed step and lists
the failures, and names every customized config whose shipped version here
differs from the capture's, with the `omarchy merge FILE REV` to run.

`restore` takes several paths for this, checking them all first.

Rollback is `replay` of an older REV: it adds and sets, never removes. To
test end to end, rebuild a scratch Omarchy install.

## 4. `omawayback merge [-w] [FILE [REV]]` (done, 0.5.0)

Three-way merge (`git merge-file`) of Omarchy's file as it was when your
copy last changed, yours, and Omarchy's file now. The base is that
capture's `shipped/` copy, or your own copy when it was still the same as
Omarchy's (an update made it the old one); REV names the base capture
instead (replay gives it). History from before 0.3.0 has no shipped
copies: the first capture with a profile is the oldest base.

No FILE lists the configs that need it. FILE shows Omarchy's change and
the merged result. `-w` writes a clean merge only, saving your copy under
`restored/` and recording a capture; a conflict is shown, never written.

## 5. Integrations

- Hooks (done, 0.6.0): `omawayback hooks [install|remove]` puts
  `omawayback.hook` in `post-update.d`, `theme-set.d` and `font-set.d` with
  `omarchy-hook-install`, marked so `remove` takes only its own (Omarchy
  has no remover).
  - post-update: a capture named after the version, like
    `omarchy-snapshot`'s snapshot.
  - theme-set and font-set: debounced. Each change writes a token to
    `$XDG_RUNTIME_DIR/omawayback-look` and starts the hook again as its own
    unit (`systemd-run --user`, else `setsid`), which sleeps 15 s and
    records only if its token is still the latest: one capture per settled
    look, named from what is current, not from the hook's argument.
    Its own unit because Omarchy runs hooks synchronously, and the process
    that ran the theme command may not outlive it.
  - A named capture waits up to 30 s for the lock (a hook firing during
    the hourly capture is not lost); an unnamed one still gives way.
  - Background-only changes (`omarchy-theme-bg-set`, `-next`) fire no hook.
- Menu (done, 0.7.0): `omawayback menu [install|remove]`. The menu
  reads exactly two files, Omarchy's default and
  `~/.config/omarchy/extensions/omarchy-menu.jsonc` (Menu.qml), and there is
  no `.d/` for extensions, so the rows go into the user's file as a marked
  block after the line that opens the object. The menu's parser
  (MenuModel.js `stripJsonc`) drops whole `//` lines and trailing commas,
  then `JSON.parse`: every row ends with a comma, which makes the block
  valid wherever the file's own entries are (checked with node against
  MenuModel.js itself). The file is checked as the menu parses it before
  and after; a file that does not parse, or keeps rows under `items`, is
  refused. A submenu `omawayback` on the root menu: Status, Capture Now
  (optional name), This Machine, Setup Changes, Merge Omarchy Changes,
  each through `omarchy-launch-floating-terminal-with-presentation`, which
  waits for a key. No `when:` guards: the menu evaluates those on every
  open, and the merge list costs a git query per customized config.
- `init` points to both on Omarchy.

## 6. Against the install (done, 0.8.0)

Omarchy's installer (Quattro and later) takes `@factory`, a read-only
Btrfs snapshot of the installed system; `omarchy-system-factory-reset`
swaps `@` for a clone of it. It is the exact baseline the heuristics could only
approximate.

- `omawayback-baseline` (root, once): mounts `subvol=/@factory` read-only,
  writes `/var/lib/omawayback/factory`: `info.txt` (Omarchy's package
  version, the snapshot's creation time), `pacman*.txt`,
  `units-system.txt` (`systemctl --root`), `units-global.txt` (`--global`:
  what is on for every user), `etc.txt` (`SUM<tab>PATH` per file) and
  `etc/` (whole copies of unowned or modified files). The privilege rule:
  only what anyone could read there, so it hands no user anything new;
  `etc_skip` is the same function in both scripts (a test diffs them);
  `/etc/skel` is left out (8,000 of Omarchy's files, all churn). A
  separate script, so the root part is short enough to read.
- The capture copies it to `factory/` in the tree; `om_install` writes
  `install.txt`, `install-packages.txt` (explicit packages added; the
  install's explicit ones gone), `install-units.txt` (`UNIT NOW WAS WHO`)
  and `install-etc.txt` (`STATE WHO PATH`; enable links left to the units).
- Whose: Omarchy's by content (any file under `default/`,
  `etc-overrides/`, `config/`), by a path its scripts name, or by a unit
  its install scripts and migrations enable, disable or mask (`for unit
  in ...` lists followed); a package's when pacman owns it unmodified; the
  system's for a fixed list (accounts, identity, locale, boot); yours
  otherwise. `yours-over` is a unit you set against Omarchy's choice.
  Read from files, so it is a likelihood, not a fact.
- 0.8.1, from the first comparison on a real machine: files owned by an
  `omarchy*` package (`omarchy-settings` installs ~25 into /etc) are
  Omarchy's, not "a package's"; a file in a directory Omarchy's scripts
  name, whose name they also mention, is Omarchy's (`color.json`, written
  through a variable); a unit named for a package in Omarchy's set is
  Omarchy's (`superwhisper` via its setup-user, `pipewire-pulse`);
  `enabled-runtime` units and unit aliases (`dbus-org.bluez.service`) are
  not changes; `.O` (CUPS) is a leftover; packages split into Omarchy's
  (added and in its set, or removed and no longer in it) and yours.
- A factory reset deletes `@`, so `/var/lib/omawayback` and the home with
  the journal go too: back up the journal first.

The commands went flat in the same release: `show`, `changes [FROM
[TO]]` (was `omarchy log` and `omarchy diff`, now with packages and their
versions, services and `/etc` files), `replay`, `merge`, `hooks`, `menu`.
The `omarchy ...` spellings stay until the public release. The hook and
menu markers changed with them; the 0.7 markers are still recognised, so
`install` replaces the old block and `remove` takes it out.

## 7. For agents (done, 0.9.0)

- `changes` is the one report for "what changed since it worked": it now
  lists the other config files too (folded per app directory) and ends
  with the names and notes on the way. `changes` alone walks every capture.
- `cat install` and `diff install` read `factory/etc/` in the journal; a
  file kept only as a checksum says so instead of guessing.
- `note REV TEXT`: git notes under `refs/notes/omawayback`, shown in `log`
  and `changes`. Prompted by the localsearch masks: the journal had when,
  the user's memory wiki had why.
- `skills/omawayback/SKILL.md` and `skill [install|remove]`: linked like
  Omarchy's own skills (migration 1790702606 links into `~/.agents`,
  `~/.claude`, `~/.codex`, `~/.pi/agent`, `~/.gemini/config`, `~/.hermes`
  and Hermes profiles), but only for agents whose directory exists. The
  skill keeps the agent to read-only commands until the user approves a
  fix, and hands sudo steps to the user.

## Name (done)

The more this leaned on Omarchy, the more an `oma-` name fit. omawayback
was checked free on GitHub, in the AUR and in the Arch repos on 2026-11-11
(omarewind, a config time machine for Omarchy, and omatrail, a game, were
the near misses). The one overlap: Wayback is also the X11-on-Wayland
compatibility layer, packaged as `wayback`.

## 8. Replay, the whole workstation (done, 0.10.0)

`replay` now rebuilds more than Omarchy's level, in this order after the
Omarchy files: the rest of the scope's home paths in the same single
restore (grouped by the scope's headings: a comment after a blank line;
not the directories Omarchy configures, which go file by file, nor
Omarchy's state); user services from `install-units.txt` that are yours;
tools (`mise install`; npm globals through `mise exec node@VERSION`,
leaving out modules pacman owns; uv tools; flatpaks); then the system part
behind one `read -rp` question: `/etc` files of yours from
`install-etc.txt` with mode and owner from `metadata/files.txt`
(`put_etc` saves the replaced file under `restored/` and installs with
sudo), system services of yours (`yours-over` marked), `update-ca-trust`
and `ufw reload` when those files are among them. Files the user cannot
read were never captured: listed by hand, from `coverage.txt`. Without an
install record there is no way to tell yours from the rest, so services
and `/etc` are left out with a note.

Checked against a real machine's journal: 351 lines, valid bash, 19 /etc
files and 9 system services in the system part.
