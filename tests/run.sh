#!/usr/bin/env bash
# omawayback behaviour tests: a fake home in a temp dir, a scope without
# @etc. pacman/systemctl/mise are the real, read-only ones. Never touches
# the real journal or config.
set -uo pipefail
here=$(cd "${0%/*}/.." && pwd)
pw=$here/omawayback
t=$(mktemp -d "${TMPDIR:-/tmp}/pw-test.XXXXXX")
trap 'chmod -R u+rwx "$t" 2>/dev/null; rm -rf "$t"' EXIT

export HOME=$t/home OMAWAYBACK_CONF=$t/home/.config/omawayback OMAWAYBACK_STATE=$t/state \
       OMAWAYBACK_TREE=$t/tree TMPDIR=$t
# never this machine's own record of the install (/var/lib/omawayback)
export OMAWAYBACK_FACTORY=$t/no-factory
mkdir -p "$HOME/.config/app" "$HOME/.config/omawayback" "$HOME/.config/other"
cfg=$HOME/.config/app
host=$(hostname -s)
printf 'host = %s\nmax_mb = 1\n' "$host" >"$OMAWAYBACK_CONF/config"
cat >"$OMAWAYBACK_CONF/scope" <<EOF
~/.config/app
$t/outside/x.conf
~/.config/missing
~/.rc
- ~/.config/app/noise/
- ~/.config/app/hidden.key
EOF
echo one >"$cfg/a.conf"
echo rc >"$HOME/.rc"
echo "spaces and [brackets]" >"$cfg/odd [name].txt"
echo secret >"$cfg/api_token.txt"
echo key >"$cfg/server.key"; chmod 600 "$cfg/server.key"
echo key >"$cfg/hidden.key"
mkdir -p "$cfg/noise"; echo x >"$cfg/noise/n"
mkdir -p "$t/outside"; echo out >"$t/outside/x.conf"

pass=0 fail=0
ok() { echo "PASS: $1"; pass=$((pass + 1)); }
no() { echo "FAIL: $1"; fail=$((fail + 1)); }
check() { local name=$1; shift; if "$@"; then ok "$name"; else no "$name"; fi; }
J() { "$pw" "$@" 2>&1 </dev/null; }   # no terminal: restore never asks
commits() { "$pw" git rev-list --count HEAD; }
intree() { "$pw" git ls-files --error-unmatch ":(top)files$1" >/dev/null 2>&1; }

out=$(J init)
check "init captures" grep -q 'captured' <<<"$out"
check "file captured" intree "$cfg/a.conf"
check "odd filename captured" intree "$cfg/odd [name].txt"
check "keys and tokens recorded, nothing left out by name" bash -c 'intree() { "$0" git ls-files --error-unmatch ":(top)files$1" >/dev/null 2>&1; }; intree "$1/api_token.txt" && intree "$1/server.key"' "$pw" "$cfg"
check "a key keeps its mode" grep -q "^-rw------- .* $cfg/server.key\$" "$OMAWAYBACK_TREE/metadata/files.txt"
check "the scope keeps a key out" bash -c '! "$0" git ls-files | grep -q hidden.key' "$pw"
check "scope exclude honoured" bash -c '! "$0" git ls-files | grep -q noise/' "$pw"
check "absent root recorded" grep -q 'absent ~/.config/missing' "$OMAWAYBACK_TREE/coverage.txt"
check "unscoped config dir listed" grep -q 'unscoped ~/.config/other' "$OMAWAYBACK_TREE/coverage.txt"
check "inventory written" test -s "$OMAWAYBACK_TREE/inventory/pacman.txt"
check "tool copied into policy" test -f "$OMAWAYBACK_TREE/policy/omawayback"

out=$(J)
check "unchanged capture makes no commit" grep -q 'no changes' <<<"$out"
check "one commit so far" test "$(commits)" = 1

touch -d '2001-01-01' "$cfg/a.conf"
out=$(J)
check "mtime-only change ignored" grep -q 'no changes' <<<"$out"

echo two >"$cfg/a.conf"
out=$(J -n)
check "dry run reports change" grep -q 'would commit' <<<"$out"
check "dry run commits nothing" test "$(commits)" = 1
J >/dev/null
check "content change committed" test "$(commits)" = 2
check "cat shows old version" test "$(J cat HEAD~1 "$cfg/a.conf")" = one
check "cat shows new version" test "$(J cat HEAD "$cfg/a.conf")" = two
check "cat at a time" test "$(J cat @now "$cfg/a.conf")" = two
check "time before first capture refused" grep -q 'no capture' <<<"$(J cat @2001-01-01 "$cfg/a.conf")"
check "log by path" test "$(J log "$cfg/a.conf" | wc -l)" = 2
check "log by relative path" test "$(cd "$cfg" && "$pw" log a.conf | wc -l)" = 2
check "diff names the file" grep -q 'a.conf' <<<"$(J diff HEAD)"

chmod 755 "$cfg/a.conf"; J >/dev/null
check "exec bit recorded" grep -q '^100755' <<<"$("$pw" git ls-files -s ":(top)files$cfg/a.conf")"
chmod 640 "$cfg/a.conf"; J >/dev/null
check "mode change in metadata" grep -q "^-rw-r----- .* $cfg/a.conf\$" "$OMAWAYBACK_TREE/metadata/files.txt"

ln -s a.conf "$cfg/link"; ln -s /nonexistent "$cfg/dangling"; J >/dev/null
check "dangling symlink captured" grep -q '^120000' <<<"$("$pw" git ls-files -s ":(top)files$cfg/dangling")"
check "symlink stored as link" grep -q '^120000' <<<"$("$pw" git ls-files -s ":(top)files$cfg/link")"

mkdir -p "$cfg/theme"; git -C "$cfg/theme" init -q
echo t >"$cfg/theme/colors.toml"
git -C "$cfg/theme" -c user.name=t -c user.email=t@t add . >/dev/null
git -C "$cfg/theme" -c user.name=t -c user.email=t@t commit -qm t
J >/dev/null
check "nested repo copied as files" intree "$cfg/theme/colors.toml"
check "no gitlink" bash -c '! "$0" git ls-files -s | grep -q ^160000' "$pw"
check "nested repo recorded" grep -q 'config/app/theme ' "$OMAWAYBACK_TREE/metadata/nested-repos.txt"

chmod 000 "$cfg/a.conf"
out=$(J)
check "unreadable file is not a deletion" intree "$cfg/a.conf"
check "unreadable file listed" grep -q "unreadable ~/.config/app/a.conf" "$OMAWAYBACK_TREE/coverage.txt"
chmod 640 "$cfg/a.conf"

head -c 2000000 /dev/zero >"$cfg/big.bin"; J >/dev/null
check "oversized file skipped" bash -c '! "$0" git ls-files | grep -q big.bin' "$pw"
check "oversized file listed" grep -q 'too-large ~/.config/app/big.bin' "$OMAWAYBACK_TREE/coverage.txt"
rm "$cfg/big.bin"

rm "$cfg/odd [name].txt"; J >/dev/null
check "deletion recorded" bash -c '! "$0" git ls-files | grep -q "odd \["' "$pw"

sed -i '/^~\/.rc$/d' "$OMAWAYBACK_CONF/scope"; J >/dev/null
check "root dropped from scope leaves the journal" bash -c '! "$0" git ls-files | grep -q "/.rc$"' "$pw"

sed -i "s/^host = .*/host = elsewhere/" "$OMAWAYBACK_CONF/config"
out=$(J)
check "other host's journal refused" grep -q 'belongs to elsewhere' <<<"$out"
sed -i "s/^host = .*/host = $host/" "$OMAWAYBACK_CONF/config"

mkdir -p "$HOME/.config/app/sub"
mv "$cfg/a.conf" "$cfg/sub/a.conf"; out=$(J -v)
check "move counted as delete + add" grep -q 'files: 0 changed, 1 added, 1 deleted' <<<"$out"
mv "$OMAWAYBACK_TREE" "$t/moved-tree"; export OMAWAYBACK_TREE=$t/moved-tree
check "work tree can move without config change" grep -q 'no changes' <<<"$(J)"
check "plain git against the journal refuses" bash -c '! git --git-dir="$0/journal.git" add -A 2>/dev/null' "$OMAWAYBACK_STATE"
check "status reports last result" grep -qE ': (committed|unchanged),' <<<"$(J status)"

# --- named captures
before=$(commits)
out=$(J -m "before test")
check "label with no changes still commits" test "$(commits)" = $((before + 1))
check "label in subject" grep -q ': before test$' <<<"$("$pw" git log -1 --format=%s)"
check "label reported" grep -q 'marked "before test"' <<<"$out"

# --- hook and metrics
mkdir -p "$t/metrics"
printf 'hook = env | grep ^OMAWAYBACK_ > %s/hook.out\nmetrics = %s/metrics\n' "$t" "$t" >>"$OMAWAYBACK_CONF/config"
echo hooked >"$cfg/h.conf"; J >/dev/null
check "hook sees committed" grep -q '^OMAWAYBACK_RESULT=committed$' "$t/hook.out"
check "hook sees change count" grep -qE '^OMAWAYBACK_CHANGED=[1-9]' "$t/hook.out"
check "hook sees commit" grep -qE '^OMAWAYBACK_COMMIT=[0-9a-f]{7,}$' "$t/hook.out"
check "metrics written" grep -q '^omawayback_last_run_success 1$' "$t/metrics/omawayback.prom"
J >/dev/null
check "hook sees unchanged" grep -q '^OMAWAYBACK_RESULT=unchanged$' "$t/hook.out"
sed -i '/^hook = /d' "$OMAWAYBACK_CONF/config"; echo 'hook = exit 3' >>"$OMAWAYBACK_CONF/config"
echo again >"$cfg/h.conf"; out=$(J); rc=$?
check "failing hook warns" grep -q 'hook failed (exit 3)' <<<"$out"
check "failing hook does not fail capture" test "$rc" = 0
sed -i '/^hook = /d' "$OMAWAYBACK_CONF/config"

# --- 0.9: notes, files in changes, the skill
echo noted >"$cfg/n.conf"; J -m "a named one" >/dev/null
J note HEAD "because of the test" >/dev/null
check "note: shown in log" bash -c 'grep -A1 ": a named one$" <<<"$0" | grep -qx "  note: because of the test"' "$(J log)"
out=$(J changes HEAD~1)
check "changes: home files" grep -qx '  files: +~/.config/app/n.conf' <<<"$out"
check "changes: names and notes on the way" bash -c 'grep -q "^named or noted on the way:" <<<"$0" && grep -q "  a named one$" <<<"$0" && grep -qx "    note: because of the test" <<<"$0"' "$out"
check "changes: list carries notes" grep -qx '  note: because of the test' <<<"$(J changes)"
check "skill: no agents, nothing to link" grep -q 'no coding agents found' <<<"$(J skill install)"
mkdir -p "$HOME/.claude" "$HOME/.codex/skills/omawayback"
J skill install >/dev/null
check "skill: linked for an agent here" test "$(readlink -f "$HOME/.claude/skills/omawayback")" = "$here/skills/omawayback"
check "skill: your own left in place" test -d "$HOME/.codex/skills/omawayback" -a ! -L "$HOME/.codex/skills/omawayback"
check "skill: status" bash -c 'grep -q "^~/.claude/skills  linked$" <<<"$0" && grep -q "^~/.codex/skills  an omawayback skill of your own$" <<<"$0"' "$(J skill)"
J skill remove >/dev/null
check "skill: removed, yours kept" bash -c 'test ! -e "$0/.claude/skills/omawayback" && test -d "$0/.codex/skills/omawayback"' "$HOME"
check "skill: names itself" grep -qx 'name: omawayback' "$here/skills/omawayback/SKILL.md"

# --- push guard
check "push refused by default" grep -q 'refusing to push' <<<"$(J git push)"

# --- restore
echo good >"$cfg/r.conf"; chmod 600 "$cfg/r.conf"
mkdir -p "$cfg/dir"; echo d1 >"$cfg/dir/keep"; echo d2 >"$cfg/dir/gone"
J >/dev/null; good=$("$pw" git rev-parse --short HEAD)
echo bad >"$cfg/r.conf"; chmod 644 "$cfg/r.conf"
echo changed >"$cfg/dir/keep"; rm "$cfg/dir/gone"; echo new >"$cfg/dir/new"
J >/dev/null; n0=$(commits)
out=$(J restore -n "$good" "$cfg/r.conf")
check "restore -n shows the diff" grep -q '^-bad' <<<"$out"
check "restore -n lists what changed later" grep -q '1 file(s) changed after .*' <<<"$out"
check "restore -n changes nothing" test "$(cat "$cfg/r.conf")" = bad
out=$(J restore "$good" "$cfg/r.conf"); rc=$?
check "changed later, no terminal: refused" bash -c 'test "$2" != 0 && grep -q "r.conf *last changed" <<<"$0" && grep -q "run it again with -y" <<<"$0" && grep -q "or with -s" <<<"$0" && test "$(cat "$1")" = bad' "$out" "$cfg/r.conf" "$rc"
out=$(J restore -s "$good" "$cfg/r.conf")
check "-s leaves it as it is" bash -c 'grep -q "left ~/.config/app/r.conf as it is" <<<"$0" && test "$(cat "$1")" = bad' "$out" "$cfg/r.conf"
check "-s with nothing else to do records nothing" test "$(commits)" = "$n0"
out=$(J restore -y "$good" "$cfg/r.conf")
check "file restored" test "$(cat "$cfg/r.conf")" = good
check "file mode restored" test "$(stat -c %a "$cfg/r.conf")" = 600
check "replaced version saved" bash -c 'grep -rqx bad "$0"/restored' "$OMAWAYBACK_STATE"
check "restore recorded as capture" grep -q 'restore ~/.config/app/r.conf' <<<"$("$pw" git log -1 --format=%s)"
out=$(J restore -s "$good" "$cfg/dir")
check "dir -s: files changed later left as they are" bash -c 'test "$(cat "$0/keep")" = changed && test ! -e "$0/gone"' "$cfg/dir"
out=$(J restore -y "$good" "$cfg/dir")
check "dir: deleted file back" test "$(cat "$cfg/dir/gone" 2>/dev/null)" = d2
check "dir: changed file reverted" test "$(cat "$cfg/dir/keep")" = d1
check "dir: newer file left in place" test -f "$cfg/dir/new"
check "dir: newer file reported" grep -q '1 paths there are newer' <<<"$out"
check "restore outside home refused" grep -q 'only inside your home' <<<"$(J restore "$good" "$t/outside/x.conf")"
check "restore of unknown path refused" grep -q 'is not in capture' <<<"$(J restore "$good" "$cfg/nope")"
echo agent >"$cfg/r.conf"
out=$(J restore HEAD "$cfg/r.conf"); rc=$?
check "no terminal, no -y: an agent's restore writes nothing" bash -c 'test "$2" != 0 && grep -q "needs the user.s yes" <<<"$0" && grep -q "show them: .*restore -n" <<<"$0" && test "$(cat "$1")" = agent' "$out" "$cfg/r.conf" "$rc"
check "restore at time works" grep -q 'restored' <<<"$(J restore -y @now "$cfg/r.conf")"
check "the latest capture asks nothing" bash -c '! grep -q "changed after" <<<"$0"' "$(J restore -y HEAD "$cfg/dir")"

# --- init from a template, in a second fake home
(
    export HOME=$t/home2 OMAWAYBACK_CONF=$t/home2/.config/omawayback OMAWAYBACK_STATE=$t/state2 OMAWAYBACK_TREE=$t/tree2
    mkdir -p "$HOME"
    o=$("$pw" init nosuch 2>&1)
    check "unknown template refused" grep -q 'no template "nosuch"' <<<"$o"
    o=$("$pw" init minimal 2>&1)
    check "init copies template" grep -q 'scope from template minimal' <<<"$o"
    check "template scope in place" grep -q '^@etc$' "$OMAWAYBACK_CONF/scope"
    echo "$pass $fail" >"$t/sub.count"
)
read -r pass fail <"$t/sub.count"

# --- the Omarchy profile, against a fake Omarchy (OMARCHY_PATH, stub getters)
(
    export HOME=$t/home3 OMAWAYBACK_CONF=$t/home3/.config/omawayback OMAWAYBACK_STATE=$t/state3 OMAWAYBACK_TREE=$t/tree3
    export OMARCHY_PATH=$t/omarchy PATH=$t/stubs:$PATH
    unset HYPRLAND_INSTANCE_SIGNATURE XDG_CURRENT_DESKTOP
    O=$OMARCHY_PATH oc=$HOME/.config/omarchy os=$HOME/.local/state/omarchy
    mkdir -p "$t/stubs" "$O"/{config/hypr,config/omarchy/hooks,applications,migrations,bin} \
             "$oc"/{themes/mine,plugins/p1,hooks/post-update.d,defaults} \
             "$os"/{current,migrations,toggles/hypr,defaults} \
             "$HOME/.local/share/applications" "$HOME/.config/hypr" "$OMAWAYBACK_CONF"
    stub() { printf '#!/bin/sh\n%s\n' "$2" >"$t/stubs/$1"; chmod +x "$t/stubs/$1"; }
    stub omarchy-version 'echo 1.0'
    stub omarchy-version-channel 'echo stable'
    stub omarchy-hw-platform 'echo x86'
    stub omarchy-font-current 'echo Test Mono'
    stub omarchy-cmd-default-browser 'echo chromium.desktop'
    stub xdg-terminal-exec 'echo com.mitchellh.ghostty.desktop:'
    # the stock set: bash (installed everywhere) and a name no host has
    stub omarchy-pkg-defaults 'printf "bash\nzz-not-a-package\n"'
    stub hyprctl 'case "$*" in *instances*) echo "[{\"instance\":\"t1\"}]" ;;
                               *configerrors*) echo "[\"line 3: bad\"]" ;; esac'
    added=$(pacman -Qqe | grep -vx bash | head -1)
    printf '#!/bin/bash\nomarchy-pkg-add %s\n' "$added" >"$O/bin/omarchy-install-thing"

    echo shipped >"$O/config/hypr/bindings.lua"; echo mine >"$HOME/.config/hypr/bindings.lua"
    echo same >"$O/config/hypr/same.lua"; cp "$O/config/hypr/same.lua" "$HOME/.config/hypr/"
    echo absent >"$O/config/hypr/absent.lua"
    echo sample >"$O/config/omarchy/hooks/x.sample"
    printf '[Desktop Entry]\nExec=omarchy-launch-webapp https://z\n' >"$O/applications/Zoom.desktop"
    cp "$O/applications/Zoom.desktop" "$HOME/.local/share/applications/"
    printf '[Desktop Entry]\nExec=omarchy-launch-webapp https://g\n' >"$O/applications/Gone.desktop"
    printf '[Desktop Entry]\nExec=omarchy-launch-webapp https://m\n' >"$HOME/.local/share/applications/My App.desktop"
    printf '[Desktop Entry]\nExec=xdg-terminal-exec --app-id=TUI.top -e top\n' >"$HOME/.local/share/applications/Top.desktop"
    echo tokyo-night >"$os/current/theme.name"
    echo 'accent = "#fff"' >"$oc/themes/mine/colors.toml"
    echo helix >"$os/defaults/editor"
    git init -q "$oc/themes/fromgit" && git -C "$oc/themes/fromgit" remote add origin https://example.com/t.git
    echo '{"id":"me.p1"}' >"$oc/plugins/p1/manifest.json"
    echo '{"bar":{"layout":{"right":[{"id":"me.p1"}]}}}' >"$oc/shell.json"
    touch "$os/toggles/suspend"; echo x >"$os/toggles/hypr/flags.lua"; echo x >"$os/toggles/hypr/bar-off.lua"
    echo x >"$oc/hooks/post-update.d/mine.hook"; echo x >"$oc/hooks/post-update.d/note.sample"
    printf 'echo "Do the first thing"\ntrue\n' >"$O/migrations/100.sh"
    printf 'echo "Do the second thing"\n' >"$O/migrations/200.sh"
    touch "$os/migrations/100.sh"
    printf 'host = %s\n' "$host" >"$OMAWAYBACK_CONF/config"
    printf '~/.config/hypr\n~/.config/omarchy\n' >"$OMAWAYBACK_CONF/scope"

    "$pw" init >/dev/null 2>&1
    p=$OMAWAYBACK_TREE/inventory/omarchy
    check "omarchy: settings" grep -qx 'version 1.0' "$p/settings.txt"
    check "omarchy: theme and editor" bash -c 'grep -qx "theme tokyo-night" "$0" && grep -qx "editor helix" "$0"' "$p/settings.txt"
    check "omarchy: terminal id" grep -qx 'terminal com.mitchellh.ghostty.desktop' "$p/settings.txt"
    check "omarchy: unset default reads -" grep -qx 'agent -' "$p/settings.txt"
    check "omarchy: stock package not added" bash -c '! grep -qx "added bash" "$0"' "$p/packages.txt"
    check "omarchy: missing default dropped" grep -qx 'dropped zz-not-a-package' "$p/packages.txt"
    check "omarchy: installer attribution" grep -qE "^added $added via (installer|.*omarchy-install-thing)" "$p/packages.txt"
    check "omarchy: local theme" grep -qx 'mine local' "$p/themes.txt"
    check "omarchy: git theme" grep -q '^fromgit git https://example.com/t.git' "$p/themes.txt"
    check "omarchy: plugin and placement" grep -qx 'me.p1 bar=right local' "$p/plugins.txt"
    check "omarchy: shipped web app" grep -qx 'webapp shipped Zoom' "$p/apps.txt"
    check "omarchy: own web app" grep -qx 'webapp yours My App' "$p/apps.txt"
    check "omarchy: tui" grep -qx 'tui yours Top' "$p/apps.txt"
    check "omarchy: removed shipped app" grep -qx 'removed shipped Gone' "$p/apps.txt"
    check "omarchy: toggles" bash -c 'grep -qx "flag suspend" "$0" && grep -qx "hypr bar-off" "$0" && ! grep -q flags "$0"' "$p/toggles.txt"
    check "omarchy: hooks without samples" bash -c 'grep -qx "post-update.d/mine.hook" "$0" && ! grep -q sample "$0"' "$p/hooks.txt"
    check "omarchy: customized config" grep -q '^custom [0-9a-f]* hypr/bindings.lua$' "$p/configs.txt"
    check "omarchy: unchanged and absent configs" bash -c 'grep -q "^same .* hypr/same.lua$" "$0" && grep -q "^absent .* hypr/absent.lua$" "$0"' "$p/configs.txt"
    check "omarchy: samples not configs" bash -c '! grep -q sample "$0"' "$p/configs.txt"
    check "omarchy: shipped base kept" test "$(cat "$p/shipped/hypr/bindings.lua")" = shipped
    check "omarchy: no base for same" test ! -e "$p/shipped/hypr/same.lua"
    check "omarchy: migration described" grep -qx '100 Do the first thing' "$p/migrations.txt"
    check "omarchy: pending migrations" grep -qx 'migrations-pending 1' "$p/health.txt"
    check "omarchy: hyprland errors" bash -c 'grep -qx "hyprland-config-errors 1" "$0" && grep -qx "hyprland-config-error line 3: bad" "$0"' "$p/health.txt"

    # an Omarchy update: new version, a default you customize changed, a
    # migration ran; and no Hyprland session to ask this time
    stub omarchy-version 'echo 1.1'
    echo shipped-v2 >"$O/config/hypr/bindings.lua"
    touch "$os/migrations/200.sh"
    rm "$t/stubs/hyprctl"
    "$pw" >/dev/null 2>&1
    msg=$("$pw" git log -1 --format=%b)
    check "omarchy: version change in message" grep -qx 'omarchy version 1.0 -> 1.1' <<<"$msg"
    check "omarchy: migration in message" grep -qx 'omarchy migration 200 Do the second thing' <<<"$msg"
    check "omarchy: changed default you customize" grep -qx 'omarchy changed defaults you customize: hypr/bindings.lua' <<<"$msg"
    check "omarchy: pending count change" grep -qx 'omarchy migrations pending: 0 (was 1)' <<<"$msg"
    check "omarchy: hyprland errors kept without a session" grep -qx 'hyprland-config-errors 1' "$p/health.txt"
    check "omarchy: old base in history" test "$("$pw" git show HEAD~1:inventory/omarchy/shipped/hypr/bindings.lua)" = shipped

    out=$("$pw" show 2>&1)
    check "omarchy show: header" grep -q 'Omarchy 1.1 (stable, x86)$' <<<"$out"
    check "omarchy show: look and defaults" bash -c 'grep -q "^look  *Tokyo Night, Test Mono" <<<"$0" && grep -q "terminal ghostty, editor helix, agent none" <<<"$0"' "$out"
    check "omarchy show: themes" grep -q 'from git: fromgit' <<<"$out"
    check "omarchy show: plugin in the bar" grep -q 'bar right: me.p1 (local)' <<<"$out"
    check "omarchy show: apps" bash -c 'grep -q "yours: My App (webapp), Top (tui)" <<<"$0" && grep -q "removed: Gone" <<<"$0"' "$out"
    check "omarchy show: toggles" grep -q '^toggles  *suspend, bar-off (hyprland)' <<<"$out"
    check "omarchy show: hooks" grep -q '^hooks  *post-update: mine.hook' <<<"$out"
    check "omarchy show: configs" grep -q '1 of 3 shipped configs customized: hypr/bindings.lua' <<<"$out"
    check "omarchy show: health" grep -q '0 migrations pending, 1 Hyprland config errors:' <<<"$out"
    check "omarchy show: older capture" grep -q 'Omarchy 1.0 ' <<<"$("$pw" show HEAD~1 2>&1)"
    out=$("$pw" changes HEAD~1 2>&1)
    check "changes: since a capture" grep -q '^  omarchy version 1.0 -> 1.1' <<<"$out"
    check "changes: range" grep -q 'changed defaults you customize: hypr/bindings.lua' <<<"$("$pw" changes HEAD~1 HEAD 2>&1)"
    check "changes: nothing between equals" grep -q '^no setup changes' <<<"$("$pw" changes HEAD HEAD 2>&1)"
    "$pw" -m "not omarchy" >/dev/null 2>&1
    stub omarchy-font-current 'echo Other Mono'
    "$pw" -m "font change" >/dev/null 2>&1
    out=$("$pw" changes 2>&1)
    check "omarchy log: newest first, with label" bash -c 'head -1 <<<"$0" | grep -q "^[0-9a-f]* [0-9-]* [0-9:]*  font change$"' "$out"
    check "omarchy log: font change" grep -q '^  omarchy font Test Mono -> Other Mono' <<<"$out"
    check "omarchy log: update listed" grep -q '^  omarchy version 1.0 -> 1.1' <<<"$out"
    check "omarchy log: first capture" bash -c 'tail -1 <<<"$0" | grep -qx "  first capture, Omarchy 1.0"' "$out"
    check "omarchy log: quiet captures left out" bash -c '! grep -q "not omarchy" <<<"$0"' "$out"
    check "omarchy log: one entry per change" test "$(grep -c '^[0-9a-f]' <<<"$out")" = 3

    # replay: the script, then run against stubs that log each Omarchy call
    echo extra >"$HOME/.config/hypr/extra.lua"; echo old >"$HOME/.config/hypr/bindings.lua.bak"
    printf '\n# shell\n~/.myrc\n~/.config/hypr/extra.lua\n' >>"$OMAWAYBACK_CONF/scope"; echo myrc >"$HOME/.myrc"
    "$pw" -m "additions" >/dev/null 2>&1
    "$pw" replay >"$t/replay.sh" 2>"$t/replay.err"
    r=$(<"$t/replay.sh")
    check "replay: valid bash" bash -n "$t/replay.sh"
    check "replay: pins the capture" grep -qx "rev=$("$pw" git rev-parse HEAD)" <<<"$r"
    check "replay: package or installer" grep -qE "^run (omarchy-install-thing|omarchy-pkg-add $added)" <<<"$r"
    check "replay: git theme cloned" grep -q 'run git clone -q -- https://example.com/t.git "$HOME"/.config/omarchy/themes/fromgit' <<<"$r"
    check "replay: local theme and plugin restored" bash -c 'grep -qx "    \"\$HOME\"/.config/omarchy/themes/mine" <<<"$0" && grep -qx "    \"\$HOME\"/.config/omarchy/plugins/p1" <<<"$0"' "$r"
    check "replay: plugin placed (no shell.json shipped)" grep -qx 'run omarchy-plugin-enable me.p1 --section right' <<<"$r"
    check "replay: toggles" bash -c 'grep -qx "run omarchy-toggle suspend on" <<<"$0" && grep -qx "run omarchy-hyprland-toggle bar-off on" <<<"$0"' "$r"
    check "replay: hook, not sample" bash -c 'grep -q "hooks/post-update.d/mine.hook" <<<"$0" && ! grep -q "note.sample" <<<"$0"' "$r"
    check "replay: customized config and its base" bash -c 'grep -qx "    \"\$HOME\"/.config/hypr/bindings.lua" <<<"$0" && grep -q "^    \"[0-9a-f]* hypr/bindings.lua\"$" <<<"$0"' "$r"
    check "replay: addition, not backup" bash -c 'grep -q "hypr/extra.lua" <<<"$0" && ! grep -q "bindings.lua.bak" <<<"$0"' "$r"
    check "replay: look and editor" bash -c 'grep -qx "run omarchy-font-set \"Other Mono\"" <<<"$0" && grep -qx "run omarchy-theme-set \"tokyo-night\"" <<<"$0" && grep -qx "run omarchy-default-editor helix" <<<"$0"' "$r"
    check "replay: removals commented" bash -c 'grep -qx "# run omarchy-pkg-drop zz-not-a-package .*" <<<"$0" && grep -q "^# rm -f \"\$HOME\"/.local/share/applications/Gone.desktop" <<<"$0"' "$r"
    check "replay: the rest of the scope, under its heading" bash -c 'grep -A1 -x "    # shell" <<<"$0" | grep -qx "    \"\$HOME\"/.myrc"' "$r"
    check "replay: Omarchy's directories not twice" test "$(grep -c 'hypr/extra.lua$' <<<"$r")" = 1
    check "replay: no record of the install, no services or /etc" bash -c 'grep -q "^# no record of the install, so yours cannot" <<<"$0" && ! grep -q "put_etc\|sudo systemctl" <<<"$0"' "$r"
    check "replay: keys by hand unless scoped" grep -q '^# By hand, unless the scope records them: ssh and gpg keys' <<<"$r"
    check "replay: no unguarded removal" bash -c '! grep -qE "^(run )?(omarchy-pkg-drop|rm |omarchy-remove)" <<<"$0"' "$r"
    for c in omarchy-install-thing omarchy-pkg-add omarchy-pkg-aur-add omarchy-plugin-add omarchy-plugin-enable \
             omarchy-toggle omarchy-hyprland-toggle omarchy-restart-shell omarchy-font-set omarchy-theme-set \
             omarchy-theme-bg-set omarchy-default-editor omarchy-default-browser omarchy-default-terminal \
             systemctl mise uv flatpak sudo; do
        printf '#!/bin/sh\necho "%s $*" >>"%s"\n' "$c" "$t/calls" >"$t/stubs/$c"; chmod +x "$t/stubs/$c"
    done
    ln -sf "$pw" "$t/stubs/omawayback"
    rm -rf "$oc/themes/mine" "$oc/hooks/post-update.d/mine.hook" "$HOME/.myrc"; echo drifted >"$HOME/.config/hypr/bindings.lua"
    echo shipped-v3 >"$O/config/hypr/bindings.lua"   # Omarchy moved on after the capture
    out=$(bash "$t/replay.sh" </dev/null 2>&1)
    check "replay ran every step" grep -qx 'every step ran' <<<"$out"
    check "replay: the rest of the scope back" test "$(cat "$HOME/.myrc" 2>/dev/null)" = myrc
    rm -f "$t/stubs/systemctl" "$t/stubs/mise" "$t/stubs/uv" "$t/stubs/flatpak" "$t/stubs/sudo"
    check "replay: theme, hook and config back" bash -c 'test -d "$0/themes/mine" && test -f "$0/hooks/post-update.d/mine.hook" && test "$(cat "$1")" = mine' "$oc" "$HOME/.config/hypr/bindings.lua"
    check "replay: Omarchy calls made" bash -c 'grep -qx "omarchy-toggle suspend on" "$0" && grep -qx "omarchy-theme-set tokyo-night" "$0" && grep -qx "omarchy-default-editor helix" "$0"' "$t/calls"
    check "replay: one capture for the restores" grep -q 'restore [0-9]* paths from' <<<"$("$pw" git log -1 --format=%s)"
    check "replay: merge suggested" grep -q '^Omarchy changed hypr/bindings.lua since the capture: omawayback merge hypr/bindings.lua' <<<"$out"

    # merge: Omarchy changes a default under your customization
    printf 'a\nb\nc\nd\ne\n' >"$O/config/hypr/bindings.lua"
    printf 'a\nB\nc\nd\ne\n' >"$HOME/.config/hypr/bindings.lua"
    "$pw" -m "base" >/dev/null 2>&1
    printf 'a\nb\nc\nd\nE\n' >"$O/config/hypr/bindings.lua"
    "$pw" >/dev/null 2>&1
    check "merge: listed" grep -q '^  hypr/bindings.lua  (your copy from' <<<"$("$pw" merge 2>&1)"
    out=$("$pw" merge ~/.config/hypr/bindings.lua 2>&1)
    check "merge: clean, shown" bash -c 'grep -q "^merges cleanly" <<<"$0" && grep -qx "  +E" <<<"$0"' "$out"
    check "merge: nothing written without -w" test "$(cat "$HOME/.config/hypr/bindings.lua")" = "$(printf 'a\nB\nc\nd\ne')"
    out=$("$pw" merge -w hypr/bindings.lua 2>&1 </dev/null); rc=$?
    check "merge -w, no terminal, no -y: nothing written" bash -c 'test "$2" != 0 && grep -q "merge -w -y hypr/bindings.lua" <<<"$0" && test "$(cat "$1")" = "$(printf "a\nB\nc\nd\ne")"' "$out" "$HOME/.config/hypr/bindings.lua" "$rc"
    "$pw" merge -w -y hypr/bindings.lua >/dev/null 2>&1 </dev/null
    check "merge -w: both changes" test "$(cat "$HOME/.config/hypr/bindings.lua")" = "$(printf 'a\nB\nc\nd\nE')"
    check "merge -w: recorded" grep -qx "capture $host .*: merge ~/.config/hypr/bindings.lua with Omarchy 1.1" <<<"$("$pw" git log -1 --format=%s)"
    check "merge: nothing left" grep -qx 'no customized config needs a merge' <<<"$("$pw" merge 2>&1)"
    printf 'a\nX\nc\nd\nE\n' >"$O/config/hypr/bindings.lua"
    out=$("$pw" merge -w -y hypr/bindings.lua 2>&1 </dev/null); rc=$?
    check "merge: conflict refused" bash -c 'grep -q "^1 conflicts" <<<"$0" && test "$1" != 0' "$out" "$rc"
    check "merge: conflict leaves the copy" test "$(cat "$HOME/.config/hypr/bindings.lua")" = "$(printf 'a\nB\nc\nd\nE')"
    echo same-v2 >"$O/config/hypr/same.lua"   # your copy is now Omarchy's old one
    check "merge: old copy takes the new default" grep -qx '  +same-v2' <<<"$("$pw" merge hypr/same.lua 2>&1)"
    check "merge: unshipped file refused" grep -q 'does not ship' <<<"$("$pw" merge hypr/extra.lua 2>&1)"
    # hooks: installed through (a stand-in for) omarchy-hook-install; the
    # look hook's unit is a plain background job here, never a real unit
    printf '#!/bin/sh\nmkdir -p "$HOME/.config/omarchy/hooks/$1.d" && cp "$2" "$HOME/.config/omarchy/hooks/$1.d/" && chmod 755 "$HOME/.config/omarchy/hooks/$1.d/${2##*/}"\n' >"$t/stubs/omarchy-hook-install"
    printf '#!/bin/bash\nwhile [[ $1 != -- ]]; do shift; done; shift\nsetsid -f "$@" </dev/null >/dev/null 2>&1\n' >"$t/stubs/systemd-run"
    chmod +x "$t/stubs/omarchy-hook-install" "$t/stubs/systemd-run"
    export XDG_RUNTIME_DIR=$t/run OMAWAYBACK_LOOK_DELAY=1; mkdir -p "$XDG_RUNTIME_DIR"
    hk=$oc/hooks
    check "hooks: none yet" test "$("$pw" hooks | grep -c 'not installed')" = 3
    echo 'omawayback -m "after omarchy-update to $(omarchy-version)"' >"$hk/post-update.d/omawayback.hook"
    check "hooks: your own noticed" grep -q '^post-update  an omawayback.hook of your own' <<<"$("$pw" hooks)"
    "$pw" hooks install >/dev/null 2>&1
    check "hooks: all installed" test "$("$pw" hooks | grep -cx '[a-z-]* *installed')" = 3
    check "hooks: yours replaced, executable" bash -c 'grep -qx "# omawayback hook (omawayback hooks)" "$0" && test -x "$0"' "$hk/post-update.d/omawayback.hook"
    n0=$("$pw" git rev-list --count HEAD)
    stub omarchy-font-current 'echo Third Mono'
    bash "$hk/theme-set.d/omawayback.hook" tokyo-night; bash "$hk/font-set.d/omawayback.hook" "Third Mono"
    for _ in $(seq 40); do (( $("$pw" git rev-list --count HEAD) > n0 )) && break; sleep 0.5; done
    sleep 2.5
    check "hooks: quick changes, one capture" test "$("$pw" git rev-list --count HEAD)" = $((n0 + 1))
    check "hooks: named after the look" grep -qx "capture $host .*: look: tokyo-night, Third Mono" <<<"$("$pw" git log -1 --format=%s)"
    bash "$hk/post-update.d/omawayback.hook" >/dev/null 2>&1
    check "hooks: after an update" grep -qx "capture $host .*: after omarchy-update to 1.1" <<<"$("$pw" git log -1 --format=%s)"
    ( flock 9; sleep 2 ) 9>"$OMAWAYBACK_STATE/lock" & sleep 0.5
    n0=$("$pw" git rev-list --count HEAD)
    out=$("$pw" 2>&1)
    check "lock: the timer's capture gives way" bash -c 'grep -q "another capture is running" <<<"$0" && test "$1" = "$2"' "$out" "$n0" "$("$pw" git rev-list --count HEAD)"
    "$pw" -m "waited" >/dev/null 2>&1
    check "lock: a named capture waits its turn" grep -qx "capture $host .*: waited" <<<"$("$pw" git log -1 --format=%s)"
    wait
    echo mine >"$hk/font-set.d/omawayback.hook"
    out=$("$pw" hooks remove 2>&1)
    check "hooks: removed" bash -c 'test ! -e "$0/post-update.d/omawayback.hook" && test ! -e "$0/theme-set.d/omawayback.hook"' "$hk"
    check "hooks: one not ours left" bash -c 'test "$(cat "$0/font-set.d/omawayback.hook")" = mine && grep -q "left in place, not written by omawayback: font-set" <<<"$1"' "$hk" "$out"
    rm -f "$hk/font-set.d/omawayback.hook"
    # menu rows: a marked block in the one user menu file, which keeps parsing
    mf=$oc/extensions/omarchy-menu.jsonc
    parses() { grep -vE '^[[:space:]]*//' "$1" | sed -z 's/,\([[:space:]]*[]}]\)/\1/g' | jq -e . >/dev/null 2>&1; }
    check "menu: not installed" grep -qx 'menu rows not installed' <<<"$("$pw" menu)"
    "$pw" menu install >/dev/null 2>&1
    check "menu: file made, parses" parses "$mf"
    check "menu: rows there" bash -c 'grep -vE "^[[:space:]]*//" "$0" | sed -z "s/,\([[:space:]]*[]}]\)/\1/g" | jq -e ".[\"omawayback.capture\"].action | test(\"omawayback -v\")" >/dev/null' "$mf"
    check "menu: installed" grep -q '^menu rows installed (' <<<"$("$pw" menu)"
    "$pw" menu remove >/dev/null 2>&1
    printf '{\n  // mine\n  "personal": {"icon":"x","label":"Personal"},\n  "personal.notes": {"label":"Notes","action":"true"}\n}\n' >"$mf"
    cp "$mf" "$t/menu.orig"
    "$pw" menu install >/dev/null 2>&1
    check "menu: beside your rows, which stay" bash -c 'grep -vE "^[[:space:]]*//" "$0" | sed -z "s/,\([[:space:]]*[]}]\)/\1/g" | jq -e ".personal and .[\"personal.notes\"] and .omawayback" >/dev/null' "$mf"
    cp "$mf" "$t/menu.once"
    check "menu: install again changes nothing" bash -c 'grep -q "already installed" <<<"$("$0" menu install 2>&1)" && cmp -s "$1" "$2"' "$pw" "$mf" "$t/menu.once"
    "$pw" menu remove >/dev/null 2>&1
    check "menu: remove gives back your file" cmp -s "$mf" "$t/menu.orig"
    printf '{\n  "broken": \n}\n' >"$mf"
    check "menu: a broken file is left alone" bash -c 'grep -q "does not parse" <<<"$("$0" menu install 2>&1)" && ! grep -q omawayback "$1"' "$pw" "$mf"
    rm -f "$mf"
    # the install: omawayback-baseline over a fake installed root, then this
    # machine's /etc and services (stubs) against it
    T=$t/inst; fr=$T/root; le=$T/etc
    mkdir -p "$fr"/etc/{closed,skel,ufw} "$fr"/var/lib/pacman/local "$fr"/usr/share/omarchy "$le"/ufw "$O"/etc-overrides "$O"/install
    echo 1.0 >"$fr/usr/share/omarchy/version"
    echo 'root:x:0:0' >"$fr/etc/passwd"; echo 'hosts: files' >"$fr/etc/nsswitch.conf"
    echo mine >"$fr/etc/mine.conf"; echo gone >"$fr/etc/gone.conf"; echo k >"$fr/etc/server.key"
    echo h >"$fr/etc/shadow"; chmod 600 "$fr/etc/shadow"; echo s >"$fr/etc/skel/.bashrc"; echo c >"$fr/etc/closed/inner"
    echo private >"$fr/etc/private.conf"; chmod 600 "$fr/etc/private.conf"; chmod 700 "$fr/etc/closed"
    ln -s passwd "$fr/etc/link"
    printf 'zz-old.service enabled enabled\nsshd.service disabled disabled\n' >"$T/units-factory"
    : >"$T/units-global"
    printf 'mine.service enabled enabled\non.service enabled disabled\nsshd.service enabled disabled\n' >"$T/units-system"
    printf 'u1.service enabled enabled\nmy.timer enabled enabled\n' >"$T/units-user"
    printf '#!/bin/sh\ncase "$*" in\n  *--global*) cat %s/units-global ;;\n  *--root=*) cat %s/units-factory | grep -v disabled ;;\n  *--user*) cat %s/units-user ;;\n  *) cat %s/units-system ;;\nesac\n' "$T" "$T" "$T" "$T" >"$t/stubs/systemctl"
    chmod +x "$t/stubs/systemctl"
    out=$("$here/omawayback-baseline" --from "$fr" --out "$T/factory" 2>&1)
    F=$T/factory
    check "baseline: recorded" bash -c 'grep -q "recorded Omarchy 1.0 as installed" <<<"$0" && grep -qx "omarchy-version 1.0" "$1/info.txt"' "$out" "$F"
    check "baseline: checksums, a link" bash -c 'grep -qP "^[0-9a-f]{64}\t/etc/passwd$" "$0" && grep -qP "^link:passwd\t/etc/link$" "$0"' "$F/etc.txt"
    check "baseline: skel left out" bash -c '! grep -q "/etc/skel/" "$0"' "$F/etc.txt"
    check "baseline: nothing left out by name, root's files by name only" bash -c 'grep -qP "^[0-9a-f]{64}\t/etc/server.key$" "$0" && grep -qP "^-\t/etc/shadow$" "$0" && test ! -e "$1/etc/shadow"' "$F/etc.txt" "$F"
    check "baseline: unreadable kept as a name, closed dirs not at all" bash -c 'grep -qP "^-\t/etc/private.conf$" "$0" && ! grep -q closed "$0"' "$F/etc.txt"
    check "baseline: unowned files kept whole, not private ones" bash -c 'test "$(cat "$0/etc/mine.conf")" = mine && test ! -e "$0/etc/private.conf"' "$F"
    check "baseline: services" grep -qx 'enabled zz-old.service' "$F/units-system.txt"
    check "baseline: needs root to mount" grep -q 'run as root' <<<"$("$here/omawayback-baseline" 2>&1)"
    check "baseline: same /etc rule as omawayback" bash -c 'diff <(sed -n "/^etc_skip()/,/^}/p" "$0") <(sed -n "/^etc_skip()/,/^}/p" "$1")' "$here/omawayback-baseline" "$pw"

    # since the install: passwd changed, nsswitch.conf now Omarchy's copy,
    # new files of several kinds, gone.conf removed
    cp -a "$fr/etc/." "$le/"; rm -rf "$le/closed" "$le/gone.conf"
    echo 'root:x:0:0:changed' >"$le/passwd"
    echo 'hosts: files myhostname' | tee "$O/etc-overrides/nsswitch.conf" >"$le/nsswitch.conf"
    echo rule >"$le/ufw/user.rules"; echo n >"$le/foo.conf.pacnew"; echo b >"$le/x.conf.bak"; echo o >"$le/omarchy-thing.conf"
    printf 'systemctl enable on.service\nsystemctl disable sshd.service 2>/dev/null || true\nfor unit in \\\n  u1.service; do\n  systemctl --user enable --now "$unit"\ndone\n' >"$O/install/units.sh"
    # 0.8.1: unit aliases, cups backups, a file Omarchy writes through a
    # variable, runtime links, a stock package's unit, packages Omarchy dropped
    mkdir -p "$le/systemd/system" "$le/chromium/policies/managed"
    ln -s /usr/lib/systemd/system/x.service "$le/systemd/system/dbus-org.x.service"
    echo o >"$le/printers.conf.O"; echo '{}' >"$le/chromium/policies/managed/color.json"
    printf 'dirs=(/etc/chromium/policies/managed)\n# write color.json\n' >"$O/install/policy.sh"
    printf 'rt.service enabled-runtime enabled\nbash.service enabled disabled\n' >>"$T/units-system"
    printf 'zz-gone-pkg\nzz-not-a-package\n' >"$F/pacman-explicit.txt"
    export OMAWAYBACK_FACTORY=$F OMAWAYBACK_ETC=$le
    "$pw" -m "with the install" >/dev/null 2>&1
    iu=$p/install-units.txt ie=$p/install-etc.txt
    check "install: record in the journal" "$pw" git cat-file -e HEAD:factory/info.txt
    check "install: Omarchy's unit" grep -qx 'on.service enabled off omarchy' "$iu"
    check "install: yours against Omarchy" grep -qx 'sshd.service enabled off yours-over' "$iu"
    check "install: yours, on and off" bash -c 'grep -qx "mine.service enabled off yours" "$0" && grep -qx "zz-old.service off enabled yours" "$0"' "$iu"
    check "install: user units" bash -c 'grep -qx "user/u1.service enabled off omarchy" "$0" && grep -qx "user/my.timer enabled off yours" "$0"' "$iu"
    check "install: /etc by whose" bash -c 'for l in "changed system /etc/passwd" "changed omarchy /etc/nsswitch.conf" "added yours /etc/ufw/user.rules" "added pacnew /etc/foo.conf.pacnew" "added leftover /etc/x.conf.bak" "added omarchy /etc/omarchy-thing.conf" "removed - /etc/gone.conf"; do grep -qxF "$l" "$0" || { echo "missing: $l"; exit 1; }; done' "$ie"
    check "install: unit aliases are services, not /etc" bash -c '! grep -q dbus-org "$0"' "$ie"
    check "install: cups backup a leftover" grep -qx 'added leftover /etc/printers.conf.O' "$ie"
    check "install: written by Omarchy through a variable" grep -qx 'added omarchy /etc/chromium/policies/managed/color.json' "$ie"
    check "install: runtime links left out" bash -c '! grep -q "^rt.service" "$0"' "$iu"
    check "install: a stock package's unit" grep -qx 'bash.service enabled off omarchy' "$iu"
    check "install: packages Omarchy dropped, and yours" bash -c 'grep -qx "removed zz-gone-pkg omarchy" "$0" && grep -qx "removed zz-not-a-package yours" "$0"' "$p/install-packages.txt"
    check "install: unchanged files counted, not listed" bash -c 'grep -q "^etc-same [1-9]" "$0" && ! grep -q mine.conf "$1"' "$p/install.txt" "$ie"
    out=$("$pw" show 2>&1)
    check "show: installed" grep -q '^installed  *Omarchy 1.0 (@factory)' <<<"$out"
    check "show: services" bash -c 'grep -q "^services  *7 changed since the install" <<<"$0" && grep -q "yours: mine, sshd (Omarchy turns it off), zz-old (off)" <<<"$0"' "$out"
    check "show: packages Omarchy dropped" grep -q "dropped or replaced by Omarchy: zz-gone-pkg" <<<"$out"
    check "show: /etc" bash -c 'grep -q "^/etc  *since the install: 2 changed, 6 added, 1 removed" <<<"$0" && grep -q "yours: ufw/user.rules" <<<"$0" && grep -q "removed: gone.conf" <<<"$0"' "$out"
    check "install: cat a file kept whole" test "$("$pw" cat install /etc/mine.conf 2>&1)" = mine
    out=$("$pw" diff install /etc/passwd 2>&1)
    check "install: diff against it" bash -c 'grep -qx -- "-root:x:0:0" <<<"$0" && grep -qx -- "+root:x:0:0:changed" <<<"$0"' "$out"
    check "install: same as installed" grep -q 'is as it was at the install' <<<"$("$pw" diff install /etc/mine.conf 2>&1)"
    check "install: not there then" grep -q 'was not there at the install' <<<"$("$pw" diff install /etc/ufw/user.rules 2>&1)"
    check "install: /etc only" grep -q 'holds /etc only' <<<"$("$pw" cat install ~/.bashrc 2>&1)"
    printf 'on.service enabled disabled\nnew.service masked masked\nsshd.service enabled disabled\nrt.service enabled-runtime enabled\nbash.service enabled disabled\n' >"$T/units-system"
    "$pw" -m "services changed" >/dev/null 2>&1
    check "changes: services" grep -qx '  services: +new.service (masked), -mine.service' <<<"$("$pw" changes HEAD~1 2>&1)"
    check "commit message: services" grep -qx 'services: +new.service (masked), -mine.service' <<<"$("$pw" git log -1 --format=%b)"
    r=$("$pw" replay 2>&1)
    check "replay: valid bash, with the install" bash -n <(printf '%s\n' "$r")
    check "replay: your user services" bash -c 'grep -qx "run systemctl --user enable my.timer" <<<"$0" && ! grep -q "enable u1.service" <<<"$0"' "$r"
    check "replay: your system services, asked first" bash -c 'grep -qx "    run sudo systemctl enable new.service" <<<"$0" || grep -qx "    run sudo systemctl mask new.service" <<<"$0"' "$r"
    check "replay: against Omarchy, said so" grep -qx '    run sudo systemctl enable sshd.service    # Omarchy sets it the other way' <<<"$r"
    check "replay: Omarchy's services left to Omarchy" bash -c '! grep -q "on.service" <<<"$0"' "$r"
    check "replay: /etc yours, not in the files" grep -qx '# /etc/ufw/user.rules: yours, but not in the capture'"'"'s files (the scope needs @etc)' <<<"$r"
    check "replay: the system part asks" grep -q '^read -rp "Put back 0 /etc files and [0-9]* system services with sudo' <<<"$r"
    check "replay: removed since the install, commented" grep -q '^# sudo rm /etc/gone.conf' <<<"$r"
    export OMAWAYBACK_FACTORY=$t/no-factory; unset OMAWAYBACK_ETC; rm -f "$t/stubs/systemctl"
    check "show: bad revision refused" grep -q 'no such capture: nosuch' <<<"$("$pw" show nosuch 2>&1)"
    echo "$pass $fail" >"$t/sub.count"
)
read -r pass fail <"$t/sub.count"
check "journal fsck clean" "$pw" git fsck --full --no-progress

echo "$pass passed, $fail failed"
(( fail == 0 ))
