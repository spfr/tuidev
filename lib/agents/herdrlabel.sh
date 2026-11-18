# shellcheck shell=bash
# lib/agents/herdrlabel.sh — Herdr's labels say what runs where: a tab is
# named after what runs in it (`✳ API docs`, `❯ mactui_setup`) instead of
# "1 2 3", a workspace row in the sidebar carries a roll-up of its sessions
# by kind (`✳2 ❯1`, the `$tuidev_agents` token) and how many are blocked on you
# (`2 blocked`, `$tuidev_need`), an agent row says since when a state that waits on
# you began (`16:32`, `$tuidev_since`) and the session's own task title when its
# tab's name does not (`$tuidev_session`), and an agent row and pane border show the
# kind's mark (`✳ claude`, Herdr's display_agent). Every value changes only
# when what it says changes, so a sync with nothing new writes nothing.
#
# One read per sync (`herdr api snapshot`: workspaces, tabs and panes with
# their labels, tokens and display names), one jq that decides, and a
# `herdr` write only for what differs. A tab is renamed only while its label
# is Herdr's own (a number) or the one a sync set; once you (or another tool,
# through Herdr's tab.rename) rename it, it is yours for good (the run dir's
# herdr-labels.tsv remembers, keyed by tab id), until `agents herdr reset
# TAB_ID` hands it back.
# Nothing runs on a timer of its own: the tuidev.link plugin's [[events]]
# hooks start `agents herdr sync` when a tab, pane or agent comes or goes or
# an agent changes state, and the menu bar's refresh runs `--throttle` as a
# safety net. An agent's event adds --poke: the menu bar shows it too. Each machine syncs its own server; a saved machine's panes are
# that machine's to name.
#
# Owns: `agents herdr` (status, sync, reset), herdr-labels.tsv and its lock.
# Uses: config.sh (AGENTS_HERDR_NAMES, AGENTS_NO_HERDR, AGENTS_RUN_DIR),
#   snapshot.sh (_agents_herdr_refresh), bar.sh (_agents_bar_target,
#   agents_bar_poke),
#   glyph.sh (_agents_glyph_map), util.sh (locks, timeouts, atomic replace).
# Public: agents_herdr, agents_herdr_sync, agents_herdr_reset.

_AGENTS_HL_SOURCE="tuidev"   # our metadata's source: what a reset clears
_AGENTS_HL_TOKEN="tuidev_agents"    # the workspace token: "$tuidev_agents" in [ui.sidebar.spaces] rows
# Every token a sync reports, and only these: what a reset clears. Workspace:
# $tuidev_agents, $tuidev_need; agent pane: $tuidev_since, $tuidev_session.
# The prefix keeps another tool's tokens out of our way: Herdr does not say
# which source set a token.
_AGENTS_HL_TOKENS="tuidev_agents tuidev_need tuidev_since tuidev_session"
# The names 3.22.0 and its successors used before the prefix; a sync clears
# them once where it finds them (a name another tool set is cleared too, once
# per appearance: the collision the prefix ends).
_AGENTS_HL_LEGACY="agents need since session"
_AGENTS_HL_THROTTLE=30       # --throttle: seconds between syncs
_AGENTS_HL_PAUSE=1           # seconds a sync waits before going again for events that came in
_AGENTS_HL_ID_RE='^[A-Za-z0-9][A-Za-z0-9:._-]{0,63}$'
_AGENTS_HL_AGENT_RE='^[A-Za-z0-9][A-Za-z0-9._-]{0,39}$'

# _agents_hl_herdr ARGS... — the Herdr CLI: the one that started us when a
# plugin hook did (HERDR_BIN_PATH), else the one on PATH.
_agents_hl_herdr() {
    local h="${HERDR_BIN_PATH:-}"
    [[ -n "$h" && -x "$h" ]] || h=herdr
    "$h" "$@"
}

# _agents_hl_ready — can we talk to this machine's Herdr? Silent false when
# AGENTS_NO_HERDR is set, or Herdr, jq or its socket is missing.
_agents_hl_ready() {
    [[ -z "${AGENTS_NO_HERDR:-}" ]] || return 1
    command -v jq >/dev/null 2>&1 || return 1
    [[ -n "${HERDR_BIN_PATH:-}" && -x "${HERDR_BIN_PATH:-}" ]] || command -v herdr >/dev/null 2>&1 || return 1
    _agents_hl_socket
}
_agents_hl_socket() { [[ -S "${HERDR_SOCKET_PATH:-$HOME/.config/herdr/herdr.sock}" ]]; }

# The decisions, in jq. Input: `herdr api snapshot`. Arguments: mode (sync,
# reset, or tabs: hand the tabs in ids back), glyphs (_agents_glyph_map, ""
# when off), state (herdr-labels.tsv), ids (tabs: the tab ids, space-separated),
# names (tabs: AGENTS_HERDR_NAMES).
# Output, one record a line, fields split by US (\x1f; no value holds a
# control character):
#   R TAB LABEL STATE_OK STATE_KEPT   rename TAB; the state line on success,
#                                      and the one to keep when it fails
#   K TAB LABEL STATE                 tabs: TAB reads LABEL already; STATE
#                                      (may be "") is its state line
#   U TAB                             tabs: no such tab in this Herdr
#   W WORKSPACE NAME=VALUE...          set the workspace's tokens ($tuidev_agents,
#                                      $tuidev_need; "NAME=" clears one)
#   P PANE NAME=VALUE...               set the pane's tokens ($tuidev_since, $tuidev_session)
#   D PANE AGENT VALUE STATE_OK STATE_KEPT
#                                      set (or with "" clear) the display name
#   S STATE                            a state line to keep as it is
#   I KIND ID WHERE LABEL WANT WHOSE   for `status`: a tab or workspace
# A state line is "tab<TAB>ID<TAB>ours|user<TAB>ORIG<TAB>SET",
# "pane<TAB>ID<TAB>VALUE" or "seen<TAB>PANE<TAB>AGENT<TAB>STATE<TAB>SEQ<TAB>AT"
# (AT: the epoch a sync saw that state begin, "-" when it did not).
# shellcheck disable=SC2016  # jq's $variables, not the shell's
_AGENTS_HL_JQ='
def clean: tostring | gsub("[\\p{Cc}\\p{Cf}\\p{Zl}\\p{Zp}]"; "") | gsub("\\s+"; " ") | sub("^ "; "") | sub(" $"; "");
def cap(n): if length > n then .[0:n-1] + "…" else . end;
def kind: (. // "" | ascii_downcase) as $a
  | if $a == "" then "shell" elif $a == "cursor" then "cursor-agent"
    elif ($a == "antigravity" or $a == "antigravity-cli") then "agy"
    elif ($a == "claude code" or $a == "claude-code") then "claude" else $a end;
def id: tostring | gsub("[^A-Za-z0-9:._-]"; "");
def us: map(tostring | gsub("[\\r\\n\\x1f]"; "")) | join("\u001f");
($glyphs | split(" ") | map(select(contains("=")) | split("=") | {key: .[0], value: (.[1:] | join("="))}) | from_entries) as $g
| ($glyphs != "") as $on
| def mark(k): if $on then ($g[k] // (if k == "shell" then "" else ($g.agent // "") end)) else "" end;
  def tag(k): mark(k) as $m | if $m != "" then $m else k + ":" end;
  ($state | split("\n") | map(split("\t")) | map(select(length >= 3))) as $st
| ($st | map(select(.[0] == "tab") | {key: .[1], value: {mode: .[2], orig: (.[3] // ""), set: (.[4] // "")}}) | from_entries) as $tabs
| ($st | map(select(.[0] == "pane") | {key: .[1], value: (.[2] // "")}) | from_entries) as $panes
| ($st | map(select(.[0] == "seen" and length >= 6) | {key: (.[1] | id), value: {agent: (.[2] | id), status: (.[3] | id), seq: (.[4] | id),
    at: (.[5] | if test("^[0-9]{1,12}$") then . else "-" end)}}) | from_entries) as $seen
| (["claude", "codex", "grok", "agy", "cursor-agent"]) as $order
| .result.snapshot as $s
| ($s.agents // [] | map({key: (.pane_id // "" | id), value: (.state_change_seq // "" | tostring | id)}) | from_entries) as $seqs
| ($ids | split(" ") | map(select(. != ""))) as $pick
| ($s.panes // []) as $all
| ($s.workspaces // [] | map({key: .workspace_id, value: (.label // "" | clean)}) | from_entries) as $wsname
# What a pane is called: its task title, unless that is only the CLI name, a
# command line or a shell prompt; else its directory.
| def dir: (.cwd // "" | tostring) as $c
    | if $c == "" then "" elif $c == $home then "~" elif $c == "/" then "/" else ($c | sub("/+$"; "") | split("/") | last) end
    | clean | sub("^-+"; "");
  def title: (.agent | kind) as $k
    | ((.terminal_title_stripped // .terminal_title // "") | clean | sub("^[^\\p{L}\\p{N}]+"; "")) as $t
    | ($t | ascii_downcase) as $l
    | if ($l == "" or $l == $k or $l == ((.agent // "") | ascii_downcase) or $l == "claude code"
          or ($l | startswith($k + " -")) or ($t | test("^[^ ]+@[^ ]+:")) or ($t | test("^[~/]"))) then "" else $t end;
  def name: (if .agent then title else "" end) as $t | (if $t != "" then $t else dir end) | cap(20);
# A tab: its first agent pane (in pane order, so focus never flips it), else
# its first pane; "+N" for the other agents in it.
  def want($tid): ($all | map(select((.tab_id // "" | id) == $tid))) as $p
    | ($p | map(select(.agent))) as $ag
    | (if ($ag | length) > 0 then $ag[0] else $p[0] end) as $lead
    | if $lead == null then "" else
        ($lead | name) as $n | ($lead.agent | kind | mark(.)) as $m
        | if $n == "" then "" else
            (if $m != "" then $m + " " else "" end) + $n
            + (if ($ag | length) > 1 then " +" + (($ag | length) - 1 | tostring) else "" end)
          end
      end;
  def rollup($wid): ($all | map(select((.workspace_id // "" | id) == $wid)) | map(.agent | kind)) as $ks
    | ($ks | map(select(. != "shell")) | unique) as $kinds
    | ([$order[] | select(. as $o | $kinds | index($o))] + ($kinds - $order) + (if ($ks | index("shell")) then ["shell"] else [] end)) as $seq
    | [$seq[] | . as $k | {t: tag($k), n: ($ks | map(select(. == $k)) | length)}]
    | reduce .[] as $e ([]; if (map(.t) | index($e.t)) then map(if .t == $e.t then .n += $e.n else . end) else . + [$e] end)
    | map(.t + (.n | tostring)) | join(" ");
# $tuidev_need: how many agents in a workspace wait for you (blocked); "" for none.
  def need($wid): ($all | map(select((.workspace_id // "" | id) == $wid and .agent and .agent_status == "blocked")) | length)
    | if . == 0 then "" elif . == 1 then "blocked" else "\(.) blocked" end;
# What a tab will read after this sync: the same rules as the tabs below.
  def next: (.tab_id // "" | id) as $id | (.label // "" | clean) as $cur | $tabs[$id] as $old | want($id) as $w
    | if $old.mode == "user" then $cur
      elif $old.mode == "ours" then (if $cur == $old.set and $w != "" then $w else $cur end)
      elif ($cur | test("^[0-9]{1,4}$")) and $w != "" then $w
      else $cur end;
# $tuidev_since: when a state that waits on you began (blocked, done, idle; not
# working), as a clock time today (16:32), the weekday this week (Mon), the
# date before that (Nov 3). It changes only with the state, or once when the
# day turns.
  def clock: tonumber as $e
    | if ($e | strflocaltime("%Y-%m-%d")) == ($now | tonumber | strflocaltime("%Y-%m-%d")) then $e | strflocaltime("%H:%M")
      elif ($now | tonumber) - $e < 518400 then $e | strflocaltime("%a")
      else $e | strflocaltime("%b %e") | gsub(" +"; " ") end;
# The token patches for one pane or workspace: "NAME=VALUE" ("NAME=" clears)
# for each of ours whose value differs from what Herdr holds, and a clear for
# each legacy name in $old that Herdr still holds (once: then it is gone).
  def patch($tk; $old): map(select(.[1] != ($tk[.[0]] // "" | clean)) | .[0] + "=" + .[1])
    + ($old | map(select($tk[.] != null) | . + "="));
# Tabs.
  (($s.tabs // [])[] as $t | ($t.tab_id // "" | id) as $id
    | ([$s.tabs[] | select(.workspace_id == $t.workspace_id)] | map(.tab_id // "" | id) | index($id) + 1 | tostring) as $pos
    | ($t.label // "" | clean) as $cur | $tabs[$id] as $old
    | (if $mode == "sync" then want($id) else "" end) as $w
    | ($wsname[$t.workspace_id] // "") as $wn
    | if $mode == "tabs" then
        # Handed back: named as a sync would now, and ours (its number kept as
        # ORIG); with no name to give (or names off), its number, and Herdr
        # owns it again. Every other tab keeps its state line as it is.
        (if ($pick | index($id)) then
           (if $old then "tab\t\($id)\t\($old.mode)\t\($old.orig)\t\($old.set)" else "" end) as $was
           | (if $names == "0" then "" else want($id) end) as $nw
           | (if $nw != "" then $nw else $pos end) as $to
           | (if $nw != "" then "tab\t\($id)\tours\t\(if ($old.orig // "") != "" then $old.orig else $pos end)\t\($nw)" else "" end) as $line
           | if $to == $cur then ["K", $id, $cur, $line] | us else ["R", $id, $to, $line, $was] | us end
         elif $old then ["S", "tab\t\($id)\t\($old.mode)\t\($old.orig)\t\($old.set)"] | us
         else empty end)
      elif $mode == "reset" then
        (if $old.mode == "ours" and $cur == $old.set and $old.orig != "" then ["R", $id, $old.orig, "", ""] | us else empty end),
        (["I", "tab", $id, $wn, $cur, $old.orig // "", "reset"] | us)
      elif $old.mode == "user" then (["S", "tab\t\($id)\tuser\t\t"] | us), (["I", "tab", $id, $wn, $cur, "", "yours"] | us)
      elif $old.mode == "ours" and $cur == $old.set then
        (if $w != "" and $w != $cur then ["R", $id, $w, "tab\t\($id)\tours\t\($old.orig)\t\($w)", "tab\t\($id)\tours\t\($old.orig)\t\($old.set)"] | us
         else ["S", "tab\t\($id)\tours\t\($old.orig)\t\($old.set)"] | us end),
        (["I", "tab", $id, $wn, $cur, $w, "ours"] | us)
      elif $old.mode == "ours" then (["S", "tab\t\($id)\tuser\t\t"] | us), (["I", "tab", $id, $wn, $cur, "", "yours"] | us)
      elif ($cur | test("^[0-9]{1,4}$")) then
        (if $w != "" then ["R", $id, $w, "tab\t\($id)\tours\t\($cur)\t\($w)", ""] | us else empty end),
        (["I", "tab", $id, $wn, $cur, $w, "herdr"] | us)
      elif $on and $w != "" and $cur == $w then
        (["S", "tab\t\($id)\tours\t\($pos)\t\($w)"] | us), (["I", "tab", $id, $wn, $cur, $w, "ours"] | us)
      else (["I", "tab", $id, $wn, $cur, "", "yours"] | us) end),
# Workspaces: the $tuidev_agents and $tuidev_need tokens (tabs: left alone).
  (if $mode == "tabs" then empty else
   ($s.workspaces // [])[] | (.workspace_id // "" | id) as $id | (.tokens // {}) as $tk | ($tk[$tok] // "" | clean) as $cur
    | (if $mode == "reset" then "" else rollup($id) end) as $w
    | ([[$tok, $w], ["tuidev_need", (if $mode == "reset" then "" else need($id) end)]] | patch($tk; ["agents", "need"])) as $ops
    | (if ($ops | length) > 0 then ["W", $id] + $ops | us else empty end),
      (["I", "ws", $id, (.label // "" | clean), $cur, $w, ""] | us) end),
# Agent panes: the $tuidev_since and $tuidev_session tokens, and a "seen" state line for
# each (tabs: the lines kept as they are). When a state began is known only
# when a sync saw it change (the kind, the state or Herdr state_change_seq):
# "-" until then, and no $tuidev_since. $tuidev_session is the task title of the pane itself
# (a directory says nothing the row does not), only when the name of its tab
# does not say it: a tab you named, or one another session leads.
  (if $mode == "tabs" then ($all[] | (.pane_id // "" | id) as $id | $seen[$id] // empty
      | ["S", "seen\t\($id)\t\(.agent)\t\(.status)\t\(.seq)\t\(.at)"] | us)
   else
   (if $mode == "sync" then ($s.tabs // [] | map({key: (.tab_id // "" | id), value: next}) | from_entries) else {} end) as $after
   | $all[] | (.pane_id // "" | id) as $id | (.tokens // {}) as $tk
   | if $mode == "sync" and .agent then
       (.agent | id) as $ag | (.agent_status // "" | tostring | id) as $stt | ($seqs[$id] // "") as $sq | $seen[$id] as $o
       | (if $o == null then "-" elif $o.agent == $ag and $o.status == $stt and $o.seq == $sq then $o.at else $now end) as $at
       | (if ($stt | IN("blocked", "done", "idle")) and ($at | test("^[0-9]{1,12}$")) then ($at | clock) else "" end) as $since
       | ((.agent | kind | mark(.)) as $m | title | cap(20) | if . == "" then "" elif $m != "" then $m + " " + . else . end) as $own
       | ($after[.tab_id // "" | id] // "") as $lab
       | (if $own == "" or $lab == $own or ($lab | startswith($own + " +")) then "" else $own end) as $sess
       | (["S", "seen\t\($id)\t\($ag)\t\($stt)\t\($sq)\t\($at)"] | us),
         ([["tuidev_since", $since], ["tuidev_session", $sess]] | patch($tk; ["since", "session"]) | if length > 0 then ["P", $id] + . | us else empty end)
     else [["tuidev_since", ""], ["tuidev_session", ""]] | patch($tk; ["since", "session"]) | if length > 0 then ["P", $id] + . | us else empty end end
   end),
# Agent panes: the display name, and only ours: one another source set wins
# (tabs: left alone, their state lines kept).
  ($all[] | (.pane_id // "" | id) as $id | (.agent // "" | id) as $ag | (.display_agent // "" | clean) as $cur | ($panes[$id] // "") as $old
    | if $mode == "tabs" then (if $old != "" then ["S", "pane\t\($id)\t\($old)"] | us else empty end) else
      (if $mode == "reset" or (.agent | not) then "" else (.agent | kind | mark(.)) as $m | if $m != "" then $m + " " + $ag else "" end end) as $w
    | if $w == $cur then (if $w != "" then ["S", "pane\t\($id)\t\($w)"] | us else empty end)
      elif $w == "" then (if $cur != "" and ($cur == $old or ($mode == "reset" and $old != "")) then ["D", $id, $ag, "", "", "pane\t\($id)\t\($old)"] | us else empty end)
      elif $cur == "" or $cur == $old then ["D", $id, $ag, $w, "pane\t\($id)\t\($w)", (if $old != "" then "pane\t\($id)\t\($old)" else "" end)] | us
      else (if $old != "" then ["S", "pane\t\($id)\t\($old)"] | us else empty end) end end),
# Tabs asked for that this Herdr does not have.
  ($pick - [($s.tabs // [])[] | .tab_id // "" | id] | .[] | ["U", .] | us)
'

# _agents_hl_plan MODE [IDS] — the records for MODE (sync, reset, or tabs:
# the tab ids IDS, space-separated), from one snapshot; false when Herdr did
# not answer in 3 s.
_agents_hl_plan() {
    local snap state="" now
    snap="$(_agents_timeout 3 _agents_hl_herdr api snapshot 2>/dev/null)" || return 1
    [[ -r "$AGENTS_RUN_DIR/herdr-labels.tsv" ]] && state="$(cat "$AGENTS_RUN_DIR/herdr-labels.tsv" 2>/dev/null)"
    _agents_now now
    printf '%s\n' "$snap" | jq -r --arg mode "$1" --arg glyphs "$(_agents_glyph_map)" --arg state "$state" \
        --arg home "$HOME" --arg tok "$_AGENTS_HL_TOKEN" --arg ids "${2:-}" --arg names "${AGENTS_HERDR_NAMES:-1}" \
        --arg now "$now" "$_AGENTS_HL_JQ" 2>/dev/null
}

# _agents_hl_tokens KIND ID FIELD... — one report-metadata call for a
# workspace or pane (KIND): each FIELD "NAME=VALUE" sets one of our tokens,
# "NAME=" clears it; a name that is not ours or a value unfit for a label is
# dropped. Prints what it changed (AGENTS_DRY_RUN=true: what it would); false
# when nothing was left to send or Herdr refused.
_agents_hl_tokens() {
    local kind="$1" id="$2" f n v msg="" args=()
    shift 2
    for f in "$@"; do
        n="${f%%=*}" v="${f#*=}"
        [[ "$f" == *=* ]] || continue
        # Ours; or a legacy name, only to clear it.
        [[ " $_AGENTS_HL_TOKENS " == *" $n "* || ( -z "${f#*=}" && " $_AGENTS_HL_LEGACY " == *" $n "* ) ]] || continue
        if [[ -n "$v" ]]; then _agents_hl_text "$v" || continue; args+=(--token "$n=$v")
        else args+=(--clear-token "$n"); fi
        msg+="${msg:+, }\$$n ${v:-(cleared)}"
    done
    [[ ${#args[@]} -gt 0 ]] || return 1
    if [[ "${AGENTS_DRY_RUN:-false}" == true ]]; then echo "would set $kind $id: $msg"; return 0; fi
    _agents_timeout 3 _agents_hl_herdr "$kind" report-metadata "$id" --source "$_AGENTS_HL_SOURCE" "${args[@]}" >/dev/null 2>&1 || return 1
    echo "$kind $id: $msg"
}

# _agents_hl_text VALUE — is VALUE fit for a label: printable, 1 to 160 bytes,
# no leading dash? (jq cleaned it already; this is the shell's own check before
# anything reaches a herdr argument.)
_agents_hl_text() { [[ -n "$1" && ${#1} -le 160 && "$1" != *[[:cntrl:]]* && "$1" != -* ]]; }

# _agents_hl_apply MODE [IDS] — run MODE's plan: each write, then the state
# file. AGENTS_DRY_RUN=true prints the writes instead. Prints what it changed;
# 3 when a tab in IDS is not there (said on stderr), after the others.
_agents_hl_apply() {
    local plan line kind a b c d e state="" n=0 ok rc=0 ops
    plan="$(_agents_hl_plan "$1" "${2:-}")" || { echo "agents: Herdr did not answer" >&2; return 1; }
    while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        IFS=$'\x1f' read -r kind a b c d e <<<"$line"
        ok=false
        case "$kind" in
            S) state+="$a"$'\n'; continue ;;
            K) [[ -z "$c" ]] || state+="$c"$'\n'
               if [[ "${AGENTS_DRY_RUN:-false}" == true ]]; then echo "would keep tab $a: $b"; else echo "tab $a: $b"; fi ;;
            U) echo "agents: no tab $a in this Herdr (see: agents herdr status)" >&2; rc=3; continue ;;
            R) { [[ "$a" =~ $_AGENTS_HL_ID_RE ]] && _agents_hl_text "$b"; } || continue
               if [[ "${AGENTS_DRY_RUN:-false}" == true ]]; then echo "would rename tab $a: $b"
               elif _agents_timeout 3 _agents_hl_herdr tab rename "$a" "$b" >/dev/null 2>&1; then ok=true; echo "tab $a: $b"; fi
               if [[ "$ok" == true ]]; then [[ -z "$c" ]] || state+="$c"$'\n'; else [[ -z "$d" ]] || state+="$d"$'\n'; fi ;;
            W|P) [[ "$a" =~ $_AGENTS_HL_ID_RE ]] || continue
               IFS=$'\x1f' read -r -a ops <<<"$line"
               [[ "$kind" == W ]] && kind=workspace || kind=pane
               _agents_hl_tokens "$kind" "$a" "${ops[@]:2}" || continue ;;
            D) [[ "$a" =~ $_AGENTS_HL_ID_RE ]] || continue
               [[ -z "$c" ]] || { [[ "$b" =~ $_AGENTS_HL_AGENT_RE ]] && _agents_hl_text "$c"; } || continue
               if [[ "${AGENTS_DRY_RUN:-false}" == true ]]; then echo "would set pane $a: ${c:-(cleared)}"; continue; fi
               if [[ -n "$c" ]]; then
                   _agents_timeout 3 _agents_hl_herdr pane report-metadata "$a" --source "$_AGENTS_HL_SOURCE" --agent "$b" --display-agent "$c" >/dev/null 2>&1 && ok=true
               else
                   _agents_timeout 3 _agents_hl_herdr pane report-metadata "$a" --source "$_AGENTS_HL_SOURCE" --clear-display-agent >/dev/null 2>&1 && ok=true
               fi
               [[ "$ok" == false ]] || echo "pane $a: ${c:-(cleared)}"
               if [[ "$ok" == true ]]; then [[ -z "$d" ]] || state+="$d"$'\n'; else [[ -z "$e" ]] || state+="$e"$'\n'; fi ;;
            *) continue ;;
        esac
        n=$((n + 1))
    done <<<"$plan"
    [[ "${AGENTS_DRY_RUN:-false}" != true ]] || return "$rc"
    state="${state%$'\n'}"
    if [[ "$1" == reset || -z "$state" ]]; then
        rm -f "$AGENTS_RUN_DIR/herdr-labels.tsv"
    elif [[ "$state" != "$(cat "$AGENTS_RUN_DIR/herdr-labels.tsv" 2>/dev/null)" ]]; then
        _agents_replace "$AGENTS_RUN_DIR/herdr-labels.tsv" "$state" || true
    fi
    return "$rc"
}

# agents_herdr_sync [--throttle] [--poke] [-n] [-q] — name the tabs, set the roll-ups and
# display names, writing only what differs. One sync at a time: a sync that
# finds another running leaves a mark (herdr-labels.dirty) and exits, and the
# running one goes again (a second later, so a burst of Herdr events costs one
# more pass, not one each). --throttle: not when one ran in the last 30 s (the
# menu bar's refresh). -q: say nothing (the plugin's hooks). Nothing, and no
# Herdr call, when AGENTS_HERDR_NAMES=0 or there is no Herdr here. --poke (an
# agent's event: the same process, not a second one): first, where the menu
# bar would refresh, Herdr's agents are read again (the cache the menu reads
# could be up to 10 s old) and the menu bar is poked.
agents_herdr_sync() {
    local throttle=false quiet=false a lock="$AGENTS_RUN_DIR/herdr-labels.lock" dirty="$AGENTS_RUN_DIR/herdr-labels.dirty"
    local stamp="$AGENTS_RUN_DIR/herdr-labels.stamp" now age pass=0 round=0 out poke=false
    for a in "$@"; do
        case "$a" in
            --throttle)    throttle=true ;;
            --poke)        poke=true ;;
            -q|--quiet)    quiet=true ;;
            -n|--dry-run)  AGENTS_DRY_RUN=true ;;
            *) echo "usage: agents herdr sync [--throttle] [--poke] [-n] [-q]" >&2; return 2 ;;
        esac
    done
    if [[ "$poke" == true ]] && _agents_now now && _agents_bar_target "$now"; then
        if [[ -z "${AGENTS_NO_HERDR:-}" ]] && _agents_hl_socket && command -v jq >/dev/null 2>&1; then
            # The hook's Herdr, when herdr is not on its PATH.
            PATH="${HERDR_BIN_PATH:+${HERDR_BIN_PATH%/*}:}$PATH" _agents_herdr_refresh 1 || true
        fi
        agents_bar_poke
    fi
    # A Herdr server that runs for weeks on a headless box is what keeps the
    # daily release check going: builtins only until it is due.
    _agents_release || true
    [[ "${AGENTS_HERDR_NAMES:-1}" == 1 ]] || { [[ "$quiet" == true ]] || echo "agents: AGENTS_HERDR_NAMES=0: Herdr's labels are left alone"; return 0; }
    _agents_hl_ready || return 0
    mkdir -p "$AGENTS_RUN_DIR" 2>/dev/null || return 1
    if [[ "$throttle" == true ]]; then
        _agents_now now
        _agents_stamp_age age "$stamp" "$now"
        [[ $age -ge $_AGENTS_HL_THROTTLE ]] || return 0
    fi
    while [[ $round -lt 2 ]]; do
        round=$((round + 1)) pass=0
        if ! _agents_lock "$lock"; then : > "$dirty"; return 0; fi
        while [[ $pass -lt 5 ]]; do
            pass=$((pass + 1))
            rm -f "$dirty"
            out="$(_agents_hl_apply sync)" || true
            [[ "$quiet" == true || -z "$out" ]] || printf '%s\n' "$out"
            _agents_now now
            [[ "${AGENTS_DRY_RUN:-false}" == true ]] || _agents_replace "$stamp" "$now" || true
            [[ -e "$dirty" && "${AGENTS_DRY_RUN:-false}" != true ]] || break
            sleep "$_AGENTS_HL_PAUSE" 2>/dev/null || true
        done
        _agents_unlock "$lock"
        # A sync that came in between the last look and the unlock.
        [[ -e "$dirty" ]] || break
    done
    return 0
}

# agents_herdr_reset [-n] [TAB_ID...] — the way back: every tab a sync named
# gets its number again (the one it had, where it still shows what a sync
# set), and the roll-ups and display names a sync reported are cleared. Works
# with AGENTS_HERDR_NAMES=0 too; with it on, the next sync names them again.
# With TAB_IDs (`agents herdr status` lists them): those tabs only, handed
# back to auto-naming, a tab you renamed included: named now as a sync would,
# or given their number when a sync has no name for them (or names are off).
# Every other tab, the roll-ups and the display names stay as they are. An
# unknown or malformed id is said on stderr, and the exit is 1 after the rest.
agents_herdr_reset() {
    local a lock="$AGENTS_RUN_DIR/herdr-labels.lock" out ids="" bad=0 rc=0
    for a in "$@"; do
        case "$a" in
            -n|--dry-run) AGENTS_DRY_RUN=true ;;
            -*) echo "usage: agents herdr reset [-n] [TAB_ID...]" >&2; return 2 ;;
            *) if [[ "$a" =~ $_AGENTS_HL_ID_RE ]]; then [[ " $ids " == *" $a "* ]] || ids+="${ids:+ }$a"
               else echo "agents: not a tab id: $(printf '%q' "$a") (see: agents herdr status)" >&2; bad=1; fi ;;
        esac
    done
    [[ -n "$ids" || $bad -eq 0 ]] || return 1
    _agents_hl_ready || { echo "agents: no Herdr to reset here (AGENTS_NO_HERDR, or no herdr, jq or socket)" >&2; return 1; }
    mkdir -p "$AGENTS_RUN_DIR" 2>/dev/null || return 1
    _agents_lock "$lock" 30 0.2 || { echo "agents: a sync is running; try again" >&2; return 1; }
    if [[ -n "$ids" ]]; then
        out="$(_agents_hl_apply tabs "$ids")" || rc=$?
        _agents_unlock "$lock"
        [[ $rc -eq 0 || $rc -eq 3 ]] || return 1
        [[ -z "$out" ]] || printf '%s\n' "$out"
        [[ "${AGENTS_HERDR_NAMES:-1}" == 1 ]] \
            || echo "AGENTS_HERDR_NAMES=0: names are off, so a tab handed back keeps its number."
        [[ $rc -eq 0 && $bad -eq 0 ]] || return 1
        return 0
    fi
    out="$(_agents_hl_apply reset)" || { _agents_unlock "$lock"; return 1; }
    _agents_unlock "$lock"
    if [[ -n "$out" ]]; then printf '%s\n' "$out"; else echo "nothing to reset"; fi
    [[ "${AGENTS_HERDR_NAMES:-1}" != 1 || "${AGENTS_DRY_RUN:-false}" == true ]] \
        || echo "The next sync names them again: AGENTS_HERDR_NAMES=0 in agents.conf keeps them as they are."
}

# agents_herdr_status — each tab: its label, what a sync would make it and
# whose it is; each workspace's roll-up. Reads only.
agents_herdr_status() {
    local plan line kind what id ws cur want whose
    echo "Herdr labels: AGENTS_HERDR_NAMES=${AGENTS_HERDR_NAMES:-1}"
    _agents_hl_ready || { echo "  no Herdr here (AGENTS_NO_HERDR, or no herdr, jq or socket)"; return 0; }
    plan="$(_agents_hl_plan sync)" || { echo "agents: Herdr did not answer" >&2; return 1; }
    # Labels last: their width is what the terminal shows, not what printf counts.
    echo "Tabs (agents: a sync named it; Herdr: still its number; yours: left alone)"
    while IFS= read -r line; do
        IFS=$'\x1f' read -r kind what id ws cur want whose <<<"$line"
        [[ "$kind" == I && "$what" == tab ]] || continue
        case "$whose" in ours) whose=agents ;; herdr) whose=Herdr ;; *) whose=yours want="" ;; esac
        [[ -z "$want" || "$want" == "$cur" ]] && want="" || want=" -> $want"
        printf '  %-16s %-8s %-6s  %s%s\n' "$ws" "$id" "$whose" "$cur" "$want"
    done <<<"$plan"
    echo "Workspaces (the sidebar's \$$_AGENTS_HL_TOKEN)"
    while IFS= read -r line; do
        IFS=$'\x1f' read -r kind what id ws cur want whose <<<"$line"
        [[ "$kind" == I && "$what" == ws ]] || continue
        [[ "$cur" == "$want" ]] && cur="" || cur=" (shown now: ${cur:--})"
        printf '  %-16s %-8s %s%s\n' "$ws" "$id" "${want:--}" "$cur"
    done <<<"$plan"
}

# agents_herdr [status|sync|reset] [OPTS] — `agents herdr`.
agents_herdr() {
    local sub="${1:-status}"
    [[ $# -gt 0 ]] && shift
    case "$sub" in
        status) agents_herdr_status ;;
        sync)   agents_herdr_sync "$@" ;;
        reset)  agents_herdr_reset "$@" ;;
        *)      echo "usage: agents herdr [status | sync [--throttle] [--poke] [-n] [-q] | reset [-n] [TAB_ID...]]" >&2; return 2 ;;
    esac
}
