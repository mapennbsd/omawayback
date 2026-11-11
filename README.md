# omawayback

A hands-off history of your Omarchy workstation: what Omarchy changed,
what your agents changed, what you changed, and how to get back.

Every hour omawayback records your machine three ways, in a private git
history on the machine itself:

- **as Omarchy sees it**: version, theme, font and defaults; the packages,
  themes, plugins, apps, toggles and hooks you added beyond stock Omarchy;
  which of Omarchy's configs you customized, with Omarchy's own version of
  each; migrations run; health.
- **against the install**: from the snapshot Omarchy's installer keeps of
  the fresh system (the one its factory reset goes back to), which
  packages, services and `/etc` files changed since, and whose change each
  one is: Omarchy's, a package's, the system's, or yours.
- **as files and inventories**: the configuration you care about (your
  configs, `/etc` changes, shell, agents, `~/bin`), all packages with
  versions, enabled services, mise and npm tools.

From that history it can show what an update did, merge Omarchy's new
defaults into your customized files, put any file back as it was, and
write a script that rebuilds the whole setup on a fresh Omarchy install.
It commits only when something changed and never writes to the live
system unless you ask.

The name is Omarchy's "oma" and the way back: the machine as it was, any
hour you ask about. omawayback is a community tool, not part of Omarchy.

## Why

An Omarchy workstation keeps changing, and you make only part of those
changes yourself:

- **Omarchy updates.** Each one brings packages, new defaults and
  migrations that rewrite config. When something breaks, the hard question
  is not "how do I roll back" but "what changed since it last worked?",
  and, when Omarchy improved a file you have your own copy of, "what did
  it change, and do I want it?"
- **Coding agents.** Claude Code, Codex and the rest edit dotfiles, hooks
  and settings as part of their work. Nobody remembers to commit those.
- **You.** A new theme on Monday, a tweak on Tuesday, a broken keybinding
  on Friday.

omawayback is not a dotfile manager. chezmoi or yadm describe what a machine
*should* look like and apply it; omawayback records what the machine *was*,
so there is no desired state to keep up, nothing to approve, and nothing
to reconcile after an update. Think of it as etckeeper for the whole
workstation, with Omarchy's view on top.

## Quick start

Requirements: Omarchy (or Arch, see "Without Omarchy"), bash, git, rsync,
jq, GNU coreutils and findutils.

    git clone https://github.com/mapennbsd/omawayback.git ~/src/omawayback
    ln -s ~/src/omawayback/omawayback ~/.local/bin/omawayback
    omawayback init                      # scope from the Omarchy template, first capture
    cp ~/src/omawayback/systemd/omawayback.service ~/src/omawayback/systemd/omawayback.timer \
       ~/.config/systemd/user/
    systemctl --user daemon-reload
    systemctl --user enable --now omawayback.timer
    omawayback hooks install             # a capture after each update, theme and font change
    omawayback menu install              # Wayback on the Omarchy menu
    omawayback skill install             # teach coding agents to use the history
    sudo ~/src/omawayback/omawayback-baseline    # once: the machine as installed

`init` copies a starting scope to `~/.config/omawayback/scope` and makes the
first capture. Review the scope and `coverage.txt` (see "Scope") after a
day. `omawayback-baseline` is the one step that needs root; read "Against
the install" first.

## Everyday use

There is none: the timer and the hooks capture on their own. When you
want to look, from a terminal or from **Wayback** on the Omarchy menu:

    omawayback status                         last run, last good capture
    omawayback show                           this machine against Omarchy and its install
    omawayback changes                        captures that changed the setup, newest first
    omawayback changes @'last week'           what changed in the setup since then
    omawayback merge                          configs Omarchy changed under your copy
    omawayback log                            every capture, newest first
    omawayback log ~/.config/hypr/bindings.lua    only captures that touched it
    omawayback diff                           what the last capture changed, file by file
    omawayback cat @yesterday ~/.bashrc       a file as it was then
    omawayback restore @yesterday ~/.config/hypr  put it back
    omawayback -m "before driver update"      capture now, with a name
    omawayback note 4f2e9c1 "masked localsearch: NFS crawl"   say why, after the fact

REV is a hash from `log`, anything git understands (`HEAD~3`), or `@TIME`
for the last capture at or before a time: `@yesterday`,
`@'2026-11-09 14:00'`, `@'3 hours ago'`. Paths can be `~/x`, absolute, or
relative to where you are. `omawayback git ...` runs any git command against
the journal, e.g. `omawayback git log -p -- inventory/pacman.txt`.

The setup is packages, services, `/etc` and Omarchy's own settings: what
`show` describes and `changes` follows. The files are what `log` and
`diff` follow.

The menu's Wayback submenu has Status, Capture Now (asks for an optional
name), This Machine, Setup Changes and Merge Omarchy Changes, each in a
floating terminal.

## The machine: `omawayback show`

`omawayback show [REV]` is the summary: what this machine is, beyond stock
Omarchy and since its install.

    workstation, capture c570da3 2026-11-09 13:33: Omarchy 4.5.0-3 (stable, x86)
    look       Retro 82, JetBrainsMono Nerd Font, background dusk-guardian
    defaults   browser chromium, terminal ghostty, editor nvim (default),
               agent claude, dictation superwhisper
    installed  Omarchy 4.0.0-1, 2026-08-23 08:39 (@factory)
    packages   63 beyond Omarchy's set
               Omarchy installers: dictation-voxtype, hermes-cli,
               service-dropbox (5), service-signal, terminal (2)
               yours: age, ai-usagebar-bin, amdgpu_top, autofs, caddy, ...
               since the install: 74 added (22 with Omarchy's set, the rest above), 7 removed
               dropped or replaced by Omarchy: cups-browsed, cups-pdf, dua-cli,
               mise, power-profiles-daemon, quickshell-git, tensaku
    services   25 changed since the install
               Omarchy's: cups-browsed (off)
               yours: autofs, bluetooth (off; Omarchy turns it on), smartd,
               sshd (Omarchy turns it off), ...
               user, Omarchy's: bt-agent, omarchy-crash-watch, owed, pipewire-pulse, ...
               user, yours: aiusage-pull.timer, omawayback.timer
    /etc       since the install: 33 changed, 419 added, 2 removed; 300 as installed
               yours: autofs/ (7), caddy/Caddyfile, smartd.conf, ufw/user.rules, ...
               Omarchy's: chromium/policies/managed/color.json, mise/conf.d/omarchy.toml,
               mkinitcpio.conf.d/ (5), os-release, pacman.conf, ...
               the system's own: default/limine, fstab, group, passwd, ssh/ (4)
               leftovers: cups/printers.conf.O, pacman.conf.bak
               from packages, as shipped: 383 files
    themes     10 of your own
               from git: amberion, grimshaw, macchiato-core, ...
    plugins    9 of your own
               bar right: example.weather (local), ...
    configs    20 of 42 shipped configs customized: alacritty/alacritty.toml, ...
    health     0 migrations pending, no Hyprland config errors

It reads `inventory/omarchy/` in the capture:

| File | What |
|---|---|
| `settings.txt` | version, channel, theme, font, background; default browser, terminal, editor, agent, dictation |
| `packages.txt` | packages beyond Omarchy's set, each with what installed it (an `omarchy-install-*` script, a menu entry, or the original install); Omarchy defaults you don't have |
| `themes.txt`, `plugins.txt` | themes and plugins you added: git URL and commit, a link, or local; where each plugin sits in the bar |
| `apps.txt` | web apps and TUIs: Omarchy's, Omarchy's as you changed them, yours, and Omarchy's you removed |
| `toggles.txt`, `hooks.txt` | toggles that are on; hooks Omarchy will run |
| `configs.txt`, `shipped/` | every config Omarchy ships, and whether yours is the same, customized or absent; Omarchy's version of each one you customize |
| `migrations.txt` | migrations run here, with what each one did |
| `health.txt` | pending migrations; Hyprland config errors |
| `install.txt`, `install-*.txt` | against the install: packages added and removed; services on or off since, and whose; `/etc` files changed, added and removed, and whose |

Every commit message says what changed at Omarchy's level, not only which
files:

    omarchy version 4.5.0-3 -> 4.5.1-1
    omarchy migration 1793565796 Open OpenCode 2 with the Omarchy theme
    omarchy changed defaults you customize: hypr/bindings.lua
    hyprland config errors: 2 (was 0)
    omarchy theme tokyo-night -> retropc
    omarchy apps: +WhatsApp
    packages upgraded 3: hyprland 0.52.1-1 -> 0.53.0-1, mesa ..., ...
    services: +docker.socket, ~cups.service (enabled -> masked)

`omawayback changes FROM [TO]` gives those changes between any two captures
(TO defaults to the last one): Omarchy's level, packages with versions,
services, the `/etc` files and your other config files that changed, and
then the names and notes given along the way. `omawayback changes @yesterday`
covers a whole day at once. `omawayback changes` alone lists only the
captures where the setup changed, each with its changes and its name if
it has one. All of them only read the journal, so they work on a journal
copied to a new machine too.

## Against the install

Omarchy's installer keeps a read-only snapshot of the freshly installed
system, the Btrfs subvolume `@factory`, which
`omarchy-system-factory-reset` goes back to. That makes "what has changed
since the install" an exact question. `omawayback-baseline` reads the
snapshot once and writes what omawayback compares against: the packages,
the enabled services, and `/etc` as installed.

    sudo ~/src/omawayback/omawayback-baseline

It mounts `@factory` read-only, writes only `/var/lib/omawayback/factory`,
and the next capture copies that into the journal (it never changes, so it
is committed once). It is a short script on its own, the one part of
omawayback that runs as root, so you can read it before you run it. It
records only what anyone could read on the installed system: a file's
checksum or content only when the file is readable by all, under
directories all may enter.
A file it may not read is a name only; the content of those files no
package owns, or that differ from their package's copy, is kept whole, as
omawayback keeps the live ones.

From then on every capture sorts each difference by whose it most likely
is, from the files rather than from times:

- **Omarchy's**: the content is a file Omarchy ships; an Omarchy package
  (`omarchy-settings`) installed the file; Omarchy's scripts name the path,
  or the directory and the file's name; its install scripts and migrations
  turn the unit on or off; or the unit is named for a package in Omarchy's
  set (`superwhisper`, `pipewire-pulse`), whose setup Omarchy ran;
- **a package's**: pacman owns the file and it is as the package left it;
- **the system's own**: accounts, identity, locale and boot files;
- **yours**: everything else, including a service Omarchy turns off that
  you turned on (`sshd (Omarchy turns it off)`).

Packages work the same way: one added since the install that is in
Omarchy's set now came with Omarchy, and one removed that is no longer in
it Omarchy dropped or replaced. Leftover backups (`.bak`, `.O`, `~`, ...)
and `.pacnew` files waiting to be merged are listed on their own; the
links systemd makes at boot (`enabled-runtime`) and unit aliases are not
counted as changes. Only machines installed from Omarchy's
installer have `@factory`; on one upgraded from an older Omarchy,
`omawayback-baseline` says so and `show` goes without these lines.

For one `/etc` file, `omawayback diff install /etc/X` shows what changed
since the install and `omawayback cat install /etc/X` prints the installed
copy. Copies are kept of the files no package owned or that differed from
their package's copy; for the rest the record is a checksum, and omawayback
says so.

A factory reset swaps the whole root for a copy of `@factory` and removes
the accounts, so it also removes `/var/lib/omawayback` and your home with
the journal in it. Back the journal up off the machine first.

## After an Omarchy update

The post-update hook names a capture after the version. Name one before,
and the diff between the two is exactly what the update did:

    omawayback -m "before omarchy-update"
    omarchy-update                  # then: "after omarchy-update to 4.5.1-1"
    omawayback changes @'1 hour ago'

Omarchy names its pre-update snapshot with the version too, so the label
tells you which boot entry to pick if you need to roll the system back.

*Changed defaults you customize* is the line to read: Omarchy improved a
file you have your own version of, and kept yours. omawayback has Omarchy's
old version in the history, so it can merge the change in:

    omawayback merge                        which files need it
    omawayback merge hypr/bindings.lua      Omarchy's change, and the merge
    omawayback merge -w hypr/bindings.lua   write the merge

The merge is three-way: Omarchy's file as it was when your copy last
changed, your copy, and Omarchy's file now. Without `-w` it only shows the
result. With `-w` it writes only a clean merge, saves your copy under
`restored/` as restore does, and records a capture; on a conflict it shows
the markers and writes nothing, for you to merge by hand. (History from
before omawayback 0.3.0 has no copies of Omarchy's files, so the oldest base
it can use is the first capture with a profile.)

## Getting back to a steady state

**Find what changed since it last worked.** Start with the setup, then go
to the files:

    omawayback changes @'yesterday 18:00'
    omawayback changes
    omawayback log
    omawayback diff 4f2e9c1

Every commit message lists packages added, removed and upgraded (with
versions), services turned on or off, the Omarchy changes, and the
changed files. `omawayback show` tells you whose each change since the
install is. To compare two points file by
file: `omawayback git diff A B -- files/home/you/.config/hypr`.

**Put files back:**

    omawayback restore -n @yesterday ~/.config/hypr     # show what would change
    omawayback restore @yesterday ~/.config/hypr
    omawayback restore @yesterday ~/.config/hypr ~/.config/ghostty   # several, one capture
    omawayback restore -s @'3 days ago' ~/.claude        # but not what changed since

Going back past a later change is asked about first. Before writing
anything, restore lists each file it would replace that a capture after REV
changed, with when, and asks: put them back too, skip them (restore only
the rest), or stop. This is how an old login token or a config edited
since does not come back by accident; it goes by the history, not by file
names. `-y` answers yes and `-s` skip. Restoring the latest capture, or
onto a fresh install, finds nothing to ask about.

Without a terminal (a coding agent, a script), `restore` and `merge -w`
write nothing unless given `-y` (or `-s`): that flag is your yes, given
after you saw `restore -n` or `merge`. The replay script passes it for you,
since running it is the yes.

restore checks every path before writing anything, saves the version it
replaces under `~/.local/state/omawayback/restored/`, restores file modes as
they were, and records the result as a named capture, so history only
ever moves forward. In a directory, files newer than the capture are left
in place and reported (the journal never held excluded files, so deleting
would lose them). It writes only inside your home; for a system file it
prints the `omawayback cat REV PATH | sudo tee PATH` line to run yourself.

**Packages.** The inventory tells you which packages and versions you had
at any capture, but a list cannot reinstall old versions on a rolling
distro: to undo an upgrade, use the snapshot Omarchy takes before each
update, or the package cache. To get the *set* back, use replay (below).

**With agents.** `omawayback skill install` links the omawayback skill
(`skills/omawayback`) into the skills directory of each coding agent on the
machine (Claude Code, Codex, pi, Gemini, Hermes, and the shared
`~/.agents/skills`), the way Omarchy links its own; an omawayback skill of
your own is left alone, and `skill remove` takes out only the links. The
skill teaches the procedure: when did it last work, `changes` since then,
narrow down with `log`, `diff` and `show`, match against the logs, then
propose the smallest fix that can be undone. `status`, `show`, `changes`,
`log`, `diff`, `cat`, `restore -n` and `merge` without `-w` never change
anything; the skill has the agent ask before `restore`, `merge -w`,
`note` or anything with sudo, and the tool backs it up: run without a
terminal, as agents run commands, `restore` and `merge -w` write nothing
unless given `-y`, the user's yes. An agent that skips asking gets a
refusal telling it to show you the command and ask. That holds whatever
the agent's own permission settings are. An agent reading the journal sends what it
reads to its model's provider. The journal holds your configuration and
whatever keys and logins your scope records; the skill tells agents never
to print one.

**Say why.** A capture's time tells you when; its name or a note tells
you why. `omawayback note REV "text"` adds a note to any capture after the
fact (git notes, so the capture keeps its hash); `log` and `changes` show
it.

## Rebuild on a fresh Omarchy

`omawayback replay [REV]` prints a script, and never runs it, that
puts a capture's whole setup back on a fresh Omarchy:

1. your packages beyond Omarchy's set: through Omarchy's installers where
   one installed them (`omarchy-install-terminal ghostty`), else
   `omarchy-pkg-add` or `-aur-add`, one per line, so a renamed package
   stops only itself;
2. git themes and plugins from their URLs;
3. the toggles that were on;
4. one `omawayback restore` of your files: local themes and plugins, apps,
   hooks, customized configs and the files you added to the directories
   Omarchy configures (with `shell.json`, the bar layout), then the rest
   of your scope (shell, `~/bin`, ssh client, agents' settings, git and
   mise config, user units), each group under your scope's own heading;
5. your user services: the ones you turned on or masked since the
   install (Omarchy's come with Omarchy);
6. your tools: `mise install`, npm globals through mise's node, uv tools,
   flatpaks;
7. the system part, after one question: your `/etc` files since the
   install, with their mode and owner (each one it replaces is saved
   under `restored/`), and the system services you set, then
   `update-ca-trust` and `ufw reload` where they apply;
8. font, theme, background and defaults, last.

Removals (Omarchy defaults you dropped, preinstalls, shipped apps you
deleted) are there, commented out. Installers that ask questions, and the
agent and dictation setters, which open a terminal, are left as comments.
At the end the script lists what is left to do by hand, any step that
failed, and any config Omarchy has changed since the capture, with the
`omawayback merge FILE REV` to run for each.

Copy the journal to the new machine first (`~/.local/state/omawayback`; the
machine needs the same host name, as restore checks), read the script,
then run it on the desktop:

    omawayback replay > rebuild.sh
    less rebuild.sh
    bash rebuild.sh

The system part needs the record of the install (`omawayback-baseline`)
to tell your `/etc` files and services from Omarchy's and the packages';
without it the script says so and leaves them out. Answer no where
something else owns the system side, ansible for example. `/etc` files
you could not read were never captured, and the script lists them to do
by hand, with what your scope does not record. With the templates that
is only Wi-Fi and VPN secrets, which are root's: ssh and gpg keys,
keyrings, gh and agent logins come back with your files. Replaying an older capture on
the same machine is a rollback that adds and sets but never removes.

## Hooks and the menu

    omawayback hooks install      # or: hooks (which are installed), hooks remove
    omawayback menu install       # or: menu, menu remove

**Hooks.** Omarchy runs hooks after an update, a theme change and a font
change; omawayback installs one in each with Omarchy's own
`omarchy-hook-install`, and `remove` takes out only its own. After an
update the capture is named after the version. After a theme or font
change it waits until you stop switching (15 seconds), then records one
capture named after the look, `look: retro-82, JetBrainsMono Nerd Font`:
trying five themes in a row makes one capture, and `omawayback log` reads as
the history of your looks. That capture runs as its own user unit
(`systemd-run`) and never holds up the switch. A named capture waits up
to 30 seconds for one already running; the hourly one does not. Changing
only the background fires no Omarchy hook: the hourly capture records it.

**Menu.** The Omarchy menu reads one file of your own,
`~/.config/omarchy/extensions/omarchy-menu.jsonc`. omawayback puts its rows
in a marked block after the opening brace and leaves the rest of the file
alone. It checks the file parses the way the menu reads it before and
after, and changes nothing if it would not; `remove` takes the block out
and gives you back the file as it was.

## How omawayback treats Omarchy

omawayback reads Omarchy's files and only the commands that print
(`omarchy-version`, `omarchy-font-current`, `omarchy-pkg-defaults`, ...).
It never runs one that changes something, not even a setter's no-argument
form, never the migrator, and never `omarchy-debug`, which uploads. It
asks Omarchy's own questions rather than inventing its own: the stock
package set from `omarchy-pkg-defaults`, git themes the way
`omarchy-theme-extras` finds them, web apps and TUIs the way Omarchy's
remove-all commands do. The timer, a terminal and ssh record the same
thing. Hyprland errors come from the running session; with none (logged
out, or over ssh) the last reading stands. Omarchy moves things between
releases: what omawayback cannot find reads `-`, and the file history keeps
working whatever Omarchy changes. Design notes: `docs/omarchy.md`.

## Without Omarchy

On plain Arch (or another pacman system) omawayback is the file and
inventory history without the Omarchy view: `init` uses the `minimal`
template, and capture, `log`, `diff`, `cat`, `restore` and `changes`
work as above; `show`, `replay`, `merge`, `hooks` and `menu` say the
machine is not Omarchy. To get a package set
back there, repository packages first (pacman rejects the whole list if
one name is not in a repository), then the foreign ones:

    omawayback git show HEAD:inventory/pacman-explicit.txt > /tmp/explicit
    omawayback git show HEAD:inventory/pacman-foreign.txt > /tmp/foreign
    comm -23 /tmp/explicit /tmp/foreign | sudo pacman -S --needed -
    yay -S --needed - < /tmp/foreign

## Where it fits in a backup strategy

omawayback is one layer, not a backup on its own:

| Layer | Examples | Good at | Weak at |
|---|---|---|---|
| Snapshots | snapper, Btrfs, ZFS (Omarchy's pre-update snapshot) | Fast whole-system rollback, local | Short retention; no idea *what* changed |
| Filesystem backup | restic, borg, rsnapshot | Disaster recovery, your data | Coarse: restores trees, not meanings |
| **omawayback** | | What changed, hour by hour, at Omarchy's level and file by file, with long history; precise restore; a rebuild script | Not your data; no package rollback |

The whole journal is one directory, `~/.local/state/omawayback/journal.git`,
so your existing filesystem backup carries it with no extra setup. The
work tree in `~/.cache/omawayback` is rebuilt from it and need not be backed
up. For an off-site copy, encrypt the journal (age, gpg) before it leaves
the machine; never push it to a hosting service (see Security).

## Scope

`~/.config/omawayback/scope`, one entry per line:

    ~/.config/hypr            capture this file or directory (missing is fine)
    - ~/.config/app/cache/    never capture (rsync pattern; ~ or / anchors it)
    - **.bak                  unanchored patterns apply everywhere
    @etc                      every /etc file pacman says you modified, plus
                              every /etc file no package owns

The Omarchy template covers Omarchy's and Hyprland's config, Omarchy's
state (theme, background, toggles, defaults, migrations), terminals and
editors, the shell, ssh and gpg with their keys, keyrings, `~/bin`, user
services, git, gh and mise, and coding agents' settings and logins. New files inside a captured directory are picked
up automatically; adding an app is one line. After each capture,
`~/.cache/omawayback/tree/coverage.txt` lists what was *not* recorded: absent
paths, unreadable files, files over the size limit, and `~/.config`
directories nothing in the scope covers (new apps show up there).

Always left out, as noise: `.git` directories, sockets, logs, swap files,
`node_modules`, and generated `/etc` files (certificate bundles, font
links, `ld.so.cache`, the `*-` backups). Nothing is left out for being a
key, token or login: what the scope names is recorded (see Security). Git
checkouts inside the scope (themes, plugins) are stored
as plain files, with their origin and commit recorded in
`metadata/nested-repos.txt`.

## Security

**The journal is as sensitive as your scope.** omawayback is for getting
this machine back, after a bad change or onto a fresh install, so it
records what the scope names, keys and logins included: the templates
take `~/.ssh`, `~/.gnupg`, the keyrings, gh's login and the coding
agents'. Nothing is dropped for its name; a filename list would miss the
keys inside ordinary settings files anyway, and drop files you need. Know
what your scope covers (`coverage.txt` lists what it does not), and keep
anything out with a `- PATTERN` line, for example `- ~/.ssh/id_*` or
`- **.env`.

- The journal is created mode 700 and is meant to stay on the machine and
  in your own backups.
- `omawayback git push` refuses unless you set `allow_push = yes`. A private
  repository on a hosting service is not the same as an encrypted backup.
- Encryption is the disk's job: Omarchy installs with full-disk
  encryption, which covers the journal and its work tree. Encrypt any copy
  that leaves the machine (age, gpg).
- A login put back from an old capture is an old token, as it is from any
  snapshot or backup, and some services refuse a refresh token once it has
  been replaced. restore asks before putting back any file a later capture
  changed (see "Getting back to a steady state"), so answer skip for
  logins unless you mean it; a rebuild from the latest capture is fine.
- omawayback never runs as root and refuses to. `/etc` files it cannot read
  are listed in `coverage.txt`, not captured.
- `omawayback-baseline`, run once with sudo, is the exception: it mounts
  `@factory` read-only and writes only `/var/lib/omawayback/factory`, with
  nothing a user could not already read on the installed system.
- A replay script is generated from the journal and names your packages,
  themes and paths: read it before you run it, and treat it like the
  journal.

## Monitoring and the capture hook

`~/.config/omawayback/config`, `key = value`:

| Key | Meaning |
|---|---|
| `host` | the machine this journal belongs to (set by init; other hosts are refused) |
| `max_mb` | skip files larger than this (default 50); listed as too-large |
| `metrics` | directory for a Prometheus textfile (`omawayback.prom`) |
| `hook` | command run after every capture (via `sh -c`, 60 s timeout) |
| `allow_push` | `yes` to allow `omawayback git push` |

Metrics: `omawayback_last_run_timestamp_seconds`,
`omawayback_last_success_timestamp_seconds`, `omawayback_last_run_success`,
`omawayback_last_changed_paths`. Alert on the success timestamp being older
than a few hours.

The capture hook (not Omarchy's hooks above) gets the outcome in its
environment:

| Variable | Value |
|---|---|
| `OMAWAYBACK_RESULT` | `committed`, `unchanged`, `failed`, or `skipped` (pacman was running) |
| `OMAWAYBACK_MESSAGE` | one-line summary or failure reason |
| `OMAWAYBACK_CHANGED` | number of changed paths |
| `OMAWAYBACK_COMMIT` | short hash of the new capture, if any |
| `OMAWAYBACK_LAST_SUCCESS` | epoch seconds of the last good capture |
| `OMAWAYBACK_HOST`, `OMAWAYBACK_JOURNAL` | host name, journal path |

For example, a desktop notification when a capture fails:

    hook = [ "$OMAWAYBACK_RESULT" = failed ] && notify-send omawayback "$OMAWAYBACK_MESSAGE" || true

A failing hook prints a warning; it never fails the capture.

## How a capture works

1. Take a lock (a named capture waits up to 30 s for it; the hourly one
   gives way); skip if pacman is mid-transaction.
2. Copy the scope with rsync into the work tree. Unreadable or oversized
   files keep their last good copy instead of being recorded as deleted;
   real deletions inside a captured directory are recorded.
3. Write inventories: all packages with versions, explicit and foreign
   packages, enabled and masked systemd units (system and user), mise
   tools, global npm packages, uv tools, flatpaks, and on Omarchy the
   profile.
4. Record each path's live mode and owner (git keeps only the exec bit).
5. Retry if the Omarchy theme changed mid-capture.
6. Commit if anything changed. mtime-only changes are not changes.

A capture takes a few seconds. The timer samples once an hour and the
hooks add one after each update and each settled look; a change made and
undone between captures is not seen, which is what `-m` is for.

## Files

| Path | What |
|---|---|
| `~/.config/omawayback/scope`, `config` | what to capture, and settings |
| `~/.local/state/omawayback/journal.git` | the history: the one thing to back up |
| `~/.local/state/omawayback/status` | last run and result (outside git, so idle hours make no commits) |
| `~/.local/state/omawayback/restored/` | versions that `restore` and `merge -w` replaced |
| `~/.cache/omawayback/tree` | work tree of the last capture; rebuilt if deleted |
| `~/.config/omarchy/hooks/*.d/omawayback.hook` | the Omarchy hooks, if installed (`omawayback hooks`) |
| `~/.config/omarchy/extensions/omarchy-menu.jsonc` | the menu rows, a marked block, if installed (`omawayback menu`) |
| `/var/lib/omawayback/factory` | the machine as installed, from `omawayback-baseline` |
| `~/.claude/skills/omawayback`, ... | links to the omawayback skill, if installed (`omawayback skill`) |

Inside each capture: `files/` (copies at their real paths), `inventory/`
(with `inventory/omarchy/`), `metadata/`, `coverage.txt`, `factory/` (the
record of the install, if there is one), and `policy/` (the scope, config
and the tool itself, so a restored journal explains itself).

## Limits

- Omarchy, or Arch and other pacman systems without the Omarchy view.
- Records configuration, and the keys and logins the scope names; not your
  data. Keep a real backup.
- No package rollback: see "Packages" above.
- Hourly sampling plus the hooks; use `-m` around changes you care about.
- Readable files only; it will not run as root (`omawayback-baseline`, once,
  does).
- "Whose change" is read from the files and Omarchy's scripts, not known:
  an Omarchy script that writes a path omawayback cannot spot, or a change
  you made that matches Omarchy's copy, is counted the other way.
- Each Omarchy release can move things; what omawayback cannot find reads
  `-` until omawayback catches up.

## Repo files

| File | What |
|---|---|
| `omawayback` | the tool: capture, init, status, log, diff, cat, restore, show, changes, replay, merge, hooks, menu, note, skill, git |
| `omawayback-baseline` | the one root step: records Omarchy's `@factory` snapshot, the machine as installed |
| `skills/omawayback/SKILL.md` | the skill for coding agents: finding what broke, and putting it back |
| `templates/omarchy` | starting scope for an Omarchy desktop |
| `templates/minimal` | small starting scope for any pacman system |
| `systemd/omawayback.service` | user service that runs one capture |
| `systemd/omawayback.timer` | hourly timer; catches up after missed runs |
| `tests/run.sh` | behaviour tests against a fake home (and a fake Omarchy and install) in a temp dir |
| `docs/omarchy.md` | design notes: the Omarchy profile and what builds on it |
| `LICENSE` | MIT |

## Tests

    tests/run.sh

## License

MIT; see `LICENSE`. omawayback is a community tool for Omarchy, not part
of it.

