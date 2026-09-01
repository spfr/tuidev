# Theming

One palette file drives the whole terminal. Instead of hand-syncing the same
hex codes across `tmux.conf`, the Ghostty config and `starship.toml`, you edit
(or pick) a palette and run one command.

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

1. **Render to a staging directory.** All three snippets are generated into a
   temp dir and sanity-checked before anything in `$HOME` is touched, so a
   broken palette cannot leave you half-themed. (This is omarchy's
   stage-then-swap idea, scaled down to three files.)
2. **Write managed blocks.** Each snippet goes into the installed config as a
   fenced region, using the same writer as the rest of the installer
   (`scripts/lib/config_write.sh`):

   ```
   # >>> tuidev managed (tuidev-theme) >>>
   …generated theme…
   # <<< tuidev managed (tuidev-theme) <<<
   ```

   Anything outside the markers is yours and survives. Re-applying rewrites the
   block in place — it never appends a second copy.
3. **Keep the theme block last** (see below).
4. **Record the active theme** in `~/.config/tuidev/theme`, which is what the
   `*` in `theme.sh list` reads.
5. **Reload live tmux.** If a tmux server is running, the freshly rendered
   snippet is `source-file`d into it, so open panes re-theme immediately.

| App | File | Block contents |
|-----|------|----------------|
| tmux | `~/.config/tmux/tmux.conf` | status bar, window status, pane borders, message and copy-mode styles |
| Ghostty | `~/.config/ghostty/config` | `background`, `foreground`, cursor, selection, `palette = 0..15` |
| Starship | `~/.config/starship.toml` | a `[palettes.tuidev]` table |

Ghostty needs a config reload (its reload keybind, or restarting the app);
Starship applies in new shells.

## Fresh installs ship pre-themed

`./install.sh` now applies `tokyo-night` for you at the end of a fresh,
non-dry-run install (the new "Default theme" step, right before the profile
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

The theme layers on top of the installed configs. Both target formats are
last-write-wins and `install.sh` *appends* its own blocks when they are
missing, which makes block order load-bearing.

`apply` handles this for you, in two different ways because the two failure
modes are not equally bad:

- **tmux and Ghostty — repaired automatically.** If an install has landed its
  `tuidev-tmux` / `tuidev-ghostty` block *below* the theme block, the shipped
  colors would silently win. `apply` notices its block is no longer last,
  removes it, and re-appends it at the end. The practical rule: **re-run
  `make theme` after an install or update** and the theme wins again.
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

## Neovim is not themed by this pipeline

Deliberately out of scope for v1: LazyVim's colorscheme is plugin-managed, and
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
- **Light themes** — nothing in the contract assumes dark, but no shipped
  palette exercises that yet; a `latte` or `tokyo-night-day` would prove it.
- **Theme drift detection** — teach `update.sh --configs` about the
  `tuidev-theme` block so a re-install does not silently revert a chosen theme.
