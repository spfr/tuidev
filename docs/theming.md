# Theming

One palette file drives the whole terminal. Instead of hand-syncing the same
hex codes across `tmux.conf`, the Ghostty config, `starship.toml` and Herdr's
config, you edit (or pick) a palette and run one command. `agents` and its menu
follow on their own.

```bash
scripts/theme.sh list                       # what's available (* = active)
scripts/theme.sh show catppuccin-mocha      # inspect a palette, with swatches
scripts/theme.sh apply catppuccin-mocha     # write it into your configs
scripts/theme.sh apply tokyo-night --dry-run  # preview, mutate nothing
```

Applying `tokyo-night` on a stock install is a visual no-op: its values are
lifted verbatim from the configs this repo already ships.

## The palette contract

A theme is a directory under `configs/themes/` containing a single
`palette.toml`. Every theme must define all 26 color keys below — `apply`
refuses to render if any are missing, and names the ones it could not find.

| Key | Role |
|-----|------|
| `bg` | Primary background: terminal canvas, tmux status bar |
| `bg_dark` | Recessed background, one step darker than `bg` |
| `bg_highlight` | Raised background: active window tab, message bar, selection-ish UI |
| `fg` | Primary text |
| `fg_dim` | De-emphasized text (normal-white ANSI slot, secondary status text) |
| `accent` | The theme's signature color: session name, active tab, prompt highlights |
| `cursor` | Terminal cursor |
| `selection_bg` | Terminal selection background (selection text uses `fg`) |
| `border` | Inactive pane/split border |
| `border_active` | Focused pane/split border |
| `ansi_black` … `ansi_white` | ANSI slots 0–7, the normal set |
| `ansi_bright_black` … `ansi_bright_white` | ANSI slots 8–15, the bright set |

Most dark themes repeat their normal color in the bright slot (Tokyo Night and
Catppuccin both do); the two slots that genuinely differ are
`ansi_bright_black` (a visible gray, used for comments and dimmed text) and
`ansi_bright_white`.

### Format rules

There is no TOML parser in the dependency chain — the format is constrained so
a regex is a complete parser. Keep every color line in exactly this shape:

```toml
key = "#rrggbb"     # trailing comments are fine
```

- lowercase `snake_case` keys, six-digit **lowercase** hex, always double-quoted
- one key per line; no arrays, no multi-line values, no key repeated
- `[theme]` metadata (`name`, `description`) and `[colors]` are for humans;
  the parser ignores section headers entirely, so keys must be unique file-wide

Keys outside the contract are ignored with a warning, which keeps a typo from
silently becoming "the color that never applied".

## Adding a theme

Drop a directory in and you are done — `list` auto-discovers it:

```bash
mkdir -p configs/themes/gruvbox-dark
cp configs/themes/tokyo-night/palette.toml configs/themes/gruvbox-dark/palette.toml
$EDITOR configs/themes/gruvbox-dark/palette.toml   # edit [theme] name + the 26 colors
scripts/theme.sh show gruvbox-dark                 # eyeball the swatches
scripts/theme.sh apply gruvbox-dark --dry-run      # read the rendered snippets
```

Take the hex values from the theme's upstream repo rather than sampling a
screenshot, and record where you got them in a header comment — both shipped
palettes do this, which is what makes them auditable.

## How `apply` writes your configs

1. **Render to a staging directory.** All four snippets are generated into a
   temp dir and sanity-checked before anything in `$HOME` is touched, so a
   broken palette cannot leave you half-themed. (This is Omarchy's
   stage-then-swap idea, scaled down to four files.)
2. **Write managed blocks.** Each snippet is written as a fenced region, using
   the same writer as the rest of the installer
   (`scripts/lib/config_write.sh`):

   ```
   # >>> tuidev managed (tuidev-theme) >>>
   …generated theme…
   # <<< tuidev managed (tuidev-theme) <<<
   ```

   Anything outside the markers is yours and survives. Re-applying rewrites the
   block in place — it never appends a second copy.
3. **Keep the Ghostty and Starship blocks last** (see below).
4. **Record the active theme** in `~/.config/tuidev/theme`, which is what the
   `*` in `theme.sh list` reads.
5. **Reload live tmux.** If a tmux server is running, the whole `tmux.conf`
   is re-sourced, so open panes re-theme immediately.

| App | File | Block contents |
|-----|------|----------------|
| tmux | `~/.config/tmux/theme.conf` (its own file) | status bar, window status, pane borders, message and copy-mode styles. `theme.sh` always renders this file, even without tmux installed — harmless, since nothing reads it until `~/.config/tmux/tmux.conf` sources it, which only happens once you install `--pack tmux` |
| Ghostty | `~/.config/ghostty/config` | `background`, `foreground`, cursor, selection, `palette = 0..15` |
| Starship | `~/.config/starship.toml` | a `[palettes.tuidev]` table |
| Herdr | `~/.config/herdr/config.toml` | a `[theme.custom]` table, [when the theme there isn't yours](#herdr-a-custom-table-never-your-theme) |

**Why tmux gets its own file:** the tail of `tmux.conf` belongs to TPM.
Plugins such as tmux-continuum hook `status-right` when TPM runs, and a theme
block after that line would reset it and silently stop continuum's autosave. So
the shipped `tmux.conf` sources `theme.conf` *above* its TPM block (with
`source-file -q`, so a missing file is fine). If `apply` finds an older managed
`tmux.conf` that doesn't source it yet, it warns you to run
`make update-configs`. It also removes a theme block left in `tmux.conf` by an
earlier release, and migration `202609222000_tmux_theme_file` does the same on
upgrade.

Ghostty needs a config reload (its reload keybind, or restarting the app);
Starship applies in new shells; Herdr reloads with `herdr server reload-config`.

## Fresh installs ship pre-themed

`./install.sh` applies `tokyo-night` for you at the end of a fresh,
non-dry-run install (the "Default theme" step, right before the profile
record is written) — as long as `~/.config/tuidev/theme` doesn't already exist.
A stock install is themed with no manual step and no
`Could not find color palette: tuidev` warning; `make theme NAME=...` is how
you *switch* themes afterward, not how you bootstrap the first one. An
already-themed machine (theme file present) is left alone, and `--dry-run`
never touches it.

That auto-apply works because it runs after `install.sh` has already written
the starship managed block and the top-level `palette = "tuidev"` selector —
the two things `apply` requires before it will touch `starship.toml` (see
below). If you hand-rolled or adopted a `starship.toml` that never went
through `install.sh`'s config-writing step, that prep hasn't happened, and the
refusal-gate below still applies until you run `./install.sh` (or add the line
yourself, as described below).

## The starship refusal-gate

For Ghostty and Starship, the theme block sits in the same file as the
installed config. Both formats are last-write-wins, and `install.sh` *appends*
its own blocks when they are missing, which makes block order load-bearing.

`apply` handles this for you, in two different ways because the two failure
modes are not equally bad:

- **Ghostty: repaired automatically.** If an install has landed its
  `tuidev-ghostty` block *below* the theme block, the shipped colors would
  silently win. `apply` notices its block is no longer last, removes it, and
  re-appends it at the end. The practical rule: **re-run `make theme` after an
  install or update** and the theme wins again.
- **Starship — refused, not repaired.** TOML has no way to close a table, so
  every key appended after `[palettes.tuidev]` lands *inside* it. Writing the
  table into a `starship.toml` that `install.sh` has not populated yet would
  swallow the entire prompt config on the next install. `apply` will not do
  that: it skips starship with an explanation and themes tmux and Ghostty
  anyway. Install, then re-apply.

`apply` also skips starship if `starship.toml` has no top-level
`palette = "tuidev"`. The shipped `configs/starship/starship.toml` carries that
line, so a normal install satisfies it — you only see this warning if you
adopted a pre-existing starship.toml, in which case add the line yourself,
above the first `[table]`:

```toml
palette = "tuidev"
```

The generated table deliberately **overrides Starship's standard color names**
(`green`, `cyan`, `purple`, `bright-black`, …), so every existing
`style = "bold green"` in your config re-themes itself with no further edits. It
also exports `tuidev_bg`, `tuidev_fg`, `tuidev_accent` and friends if you want
to reference palette roles directly.

## Herdr: a custom table, never your theme

Herdr's `[theme.custom]` overrides its color tokens on top of the theme `[theme]`
names, one by one, and `apply` sets all of them from the palette but `panel_bg`,
which stays `reset`: the panels keep the terminal's background, as Herdr's own docs
do it. `blocked` is Herdr's `red` and `working` its `yellow`, so a session blocked
in the sidebar is the same red as `▲` in `agents`.

| Herdr token | Palette key |
|-------------|-------------|
| `accent`, `text`, `subtext0` | `accent`, `fg`, `fg_dim` |
| `active_row_bg`, `selection_bg` | `bg_highlight`, `selection_bg` |
| `sidebar_bg` | `bg_dark` |
| `surface0`, `surface1`, `surface_dim` | `bg_highlight`, `border`, `bg_dark` |
| `overlay0`, `overlay1` | `ansi_bright_black`, `fg_dim` |
| `red`, `green`, `yellow`, `blue`, `teal`, `mauve`, `peach` | `ansi_red`, `ansi_green`, `ansi_yellow`, `ansi_blue`, `ansi_cyan`, `ansi_magenta`, `ansi_bright_yellow` |

TOML has no way to close a table, so the block goes at the end of the file, with a
comment asking you to add your own settings above it. Two refusals, both with a
printed line, while the other targets are themed anyway:

- **No `~/.config/herdr/config.toml` yet:** skipped. The herdr pack places that
  file only when it is absent, so writing one first would keep the shipped config
  out. Install the pack, then re-apply.
- **A theme of yours:** skipped. Anything of `[theme]` beyond the
  `name = "tokyo-night"` the shipped config has, or a `[theme.custom]` outside our
  block, however TOML spells it, is yours, and it stays. An earlier block of ours
  goes then, and `apply` says so: its tokens would override your theme. Remove your
  tables and re-apply to use the palette, or set `name = "terminal"` there, which
  follows the terminal's colors.

## `agents` and its menu

`agents` needs no step of its own: its colors are six tokens, read from the palette
you applied (`~/.config/tuidev/theme`) on each run.

| Token | Means | Palette key | Shape |
|-------|-------|-------------|-------|
| `need` | Blocked, or about to be stopped | `ansi_red` | `▲` |
| `done` | Finished, not yet reviewed | `ansi_blue` | `◆` |
| `run` | Working, healthy | `ansi_green` | `●` |
| `warn` | Worth a look: stuck, long, high swap | `ansi_yellow` | `!` |
| `dim` | Parked, labels, an empty gauge | SGR 2 | `○ ░` |
| `accent` | Headers, the time marker | `accent` | `│` |

The shapes carry the meaning, so `NO_COLOR` loses nothing, and a locale with no such
glyphs gets `^`, `*`, `o`, `.`, `?` (and `#`, `-`, `|` in a gauge). How many colors a token
can use follows the terminal: none with `TERM=dumb`, truecolor when `COLORTERM` says so (which also adds
the Needs-you row's tint), 256 when `TERM` does, else the terminal's own 16, which
in a themed Ghostty are the palette anyway. In `~/.config/agents.conf`:

```bash
AGENTS_THEME=auto            # the palette applied, else the 16 colors
                             # ansi: the 16 colors; none: no color; or a palette's name
AGENTS_COLOR_NEED=ansi_red   # any token: a palette key or #rrggbb
```

The palettes ship with the monitoring pack, beside the `agents` modules, so an
installed `agents` needs no repo. A palette you added to `configs/themes/` reaches
it with the next `./install.sh --pack monitoring`; until then it uses the 16 colors.

The menu tints its symbols with the same tokens, where they suit the menu's
appearance: a dark palette's pastels wash out on a light menu, so that keeps Apple's
system hues. SwiftBar colors symbols only: the text stays the system's.

## Neovim is not themed by this pipeline

Deliberately out of scope: LazyVim's colorscheme is plugin-managed, and
generating one from a 26-key palette would produce a worse result than the
hand-tuned upstream themes. Switch it yourself in
`configs/nvim/lua/plugins/` (or `~/.config/nvim/lua/plugins/`):

```lua
-- tokyo-night (the default)
{ "folke/tokyonight.nvim", opts = { style = "night" } },
{ "LazyVim/LazyVim", opts = { colorscheme = "tokyonight-night" } },

-- catppuccin-mocha
{ "catppuccin/nvim", name = "catppuccin", opts = { flavour = "mocha" } },
{ "LazyVim/LazyVim", opts = { colorscheme = "catppuccin" } },
```

## Future

Ideas that fit the same palette contract without changing it:

- **More render targets** — btop, bat/delta, lazygit and fzf all take colors
  and are currently unthemed; each is one more renderer function.
- **OSC live reload** — emit OSC 4/10/11/12 sequences on apply so already-open
  terminal panes recolor without a Ghostty restart.
- **Theme drift detection** — teach `update.sh --configs` about the
  `tuidev-theme` block so a re-install does not silently revert a chosen theme.
