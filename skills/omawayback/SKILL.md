---
name: omawayback
description: >
  Find what changed on this workstation, when, and whose change it was, from
  omawayback's hourly history of its configuration, and put it back. Use when
  something on the machine broke or behaves differently ("this worked
  yesterday", "since the update", "my keybinding stopped working"), when
  asked what changed, what an Omarchy update did, whether a config or /etc
  file is the user's or Omarchy's, or how to undo a config change. Triggers:
  what changed, since when, broke after update, regression, roll back a
  config, omawayback, journal of config.
---

# Finding what broke with omawayback

omawayback records the machine every hour, and after each Omarchy update,
theme and font change, in a private git journal: packages with versions,
services, `/etc`, the user's configs, and Omarchy's own settings. Each
capture can carry a name (`-m`) and notes. It also knows the machine as
Omarchy installed it, so it can say whose a change is: Omarchy's, a
package's, the system's, or the user's.

The first question in any breakage is "what changed since it last
worked?". omawayback answers it from records, so start there, before
guessing.

## Rules

- Read-only commands, freely: `status`, `show`, `changes`, `log`, `diff`,
  `cat`, `cat install`, `diff install`, `restore -n`, `merge` without `-w`.
- Anything that changes the machine needs the user's yes first, every
  time: `restore` (without `-n`), `merge -w`, `note`, any `sudo`, any
  package change. Propose the exact command; let the user run it or
  approve it.
- The journal is confidential, and holds keys and logins: ssh and gpg
  keys, tokens, `.env` files. Quote only the lines you need; never print
  a key, token or password, never copy one out of it, never push it
  anywhere (`omawayback git push` is refused on purpose).
- Never run Omarchy commands that change something (setters, even with no
  argument; the migrator; `omarchy-debug`, which uploads). Reading is fine.

## The procedure

1. **When did it last work?** Ask, or take it from the user's words
   ("yesterday evening" is `@'yesterday 18:00'`; "before the update" is
   the capture named `before omarchy-update`, see `omawayback log`).
2. **Is the history current?** `omawayback status`. If the last capture is
   old, say so: changes after it are not recorded.
3. **What changed since then?**

       omawayback changes @'yesterday 18:00'

   One report: Omarchy's level (version, migrations, theme, defaults
   Omarchy changed under the user's copy), packages added, removed and
   upgraded with versions, services turned on or off, `/etc` files, and
   the user's other config files. At the end, the names and notes given
   along the way, which often say why. `omawayback changes` alone lists the
   captures where something changed, newest first, each with its changes.
4. **Narrow it down.** For a suspect file:

       omawayback log ~/.config/hypr/bindings.lua      captures that touched it
       omawayback diff 4f2e9c1 ~/.config/hypr/bindings.lua
       omawayback cat @'yesterday 18:00' ~/.config/hypr/bindings.lua

   Whose is it? `omawayback show` sorts packages, services and `/etc` since
   the install into Omarchy's, a package's, the system's and the user's.
   For an `/etc` file: `omawayback diff install /etc/X` against the install.
5. **Match it with the logs.** The change that lines up in time with the
   first error is the suspect: `journalctl -b`, `journalctl --user -b`,
   `hyprctl configerrors`. For a crash, use the diagnose-crash skill.
6. **Rank the suspects and propose the smallest fix that can be undone**:

   - a config file in the home directory:
     `omawayback restore -n REV PATH` shows it, and lists any file there a
     later capture changed (a login refreshed since, a config edited
     since). Show the user that list and ask: `restore -y REV PATH` puts
     those back too, `restore -s REV PATH` leaves them (the right answer
     for logins and tokens unless the user says otherwise). Without `-y`
     or `-s` it stops and changes nothing. It keeps the replaced copy and
     records a capture;
   - a config Omarchy changed under the user's copy: `omawayback merge FILE`,
     then `omawayback merge -w FILE`;
   - an `/etc` file: restore does not write outside home; give the user
     `omawayback cat REV /etc/X | sudo tee /etc/X`;
   - a package upgrade: the old version is usually in
     `/var/cache/pacman/pkg/`; give the user `sudo pacman -U` with that
     file;
   - the whole system: the snapshot Omarchy took before the update, named
     with the version, from the boot menu.

7. **Afterwards**, suggest `omawayback -m "fixed: what and why"`, or
   `omawayback note REV "why"` on the capture that made the change, so the
   next look at the history has the reason.

## Commands

| Command | What |
|---|---|
| `omawayback status` | last run, last good capture |
| `omawayback show [REV]` | the machine against stock Omarchy and its install, with whose each change is |
| `omawayback changes [FROM [TO]]` | captures that changed the setup; or every change between two captures |
| `omawayback log [PATH]` | every capture (or those touching PATH), with names and notes |
| `omawayback diff [REV] [PATH]` | what a capture changed |
| `omawayback cat REV PATH` | a file as it was |
| `omawayback cat install /etc/X`, `diff install /etc/X` | an `/etc` file as installed, or against it |
| `omawayback restore [-n\|-y\|-s] REV PATH...` | put files back (home only; `-n` shows; files changed later: `-y` too, `-s` leave) |
| `omawayback merge [-w] [FILE]` | merge Omarchy's change into the user's copy |
| `omawayback note REV TEXT` | add the reason to a capture |
| `omawayback git ARGS` | any git command on the journal, e.g. `git log -p -- inventory/pacman.txt` |

REV is a hash from `log`, `HEAD~2`, or `@TIME`: `@yesterday`,
`@'2026-11-09 14:00'`, `@'3 hours ago'`.

## Reading `changes`

    setup changes from 7e28953 2026-11-10 09:49 to af48bd8 2026-11-10 09:51:
      omarchy version 4.5.0-3 -> 4.5.1-1
      omarchy changed defaults you customize: hypr/bindings.lua
      packages upgraded 3: hyprland 0.52.1-1 -> 0.53.0-1, ...
      services: +docker.socket, -cups.service, ~sshd.service (enabled -> masked)
      /etc: +ufw/user.rules, -caddy/Caddyfile, pacman.conf
      files: ~/.config/hypr/ (4), ~/.bashrc
    named or noted on the way:
      af48bd8 2026-11-10 09:51  after caddy cleanup

`+` added, `-` removed, no mark changed. *Omarchy changed defaults you
customize* means Omarchy improved a file the user has their own copy of
and kept theirs: a common cause of "the update broke it" when the old
copy no longer fits, and `omawayback merge` is the fix.
