# Omarchy quickshell: Antigravity in the Agents panel

Status: DONE 2026-09-01. Installed and verified on omarchy 4.0.0-1.

## What this is

Omarchy 4's bar has an Agents widget (`omarchy.agents`): left-click opens a
usage panel (limits, tokens by day, tokens by model), middle-click switches
between providers, and the Setup > Default Agent menu picks which agent
launches. Stock omarchy ships usage collectors for Claude Code, Codex, and
Fireworks only, and its "Gemini" agent entry launches the old `gemini` CLI,
which Google retired for consumer accounts in favor of Antigravity (`agy`).

This adds Google Antigravity as a first-class provider:

- `bin/omarchy-agent-usage-antigravity` — usage collector. The panel is
  display-only and picks up any record written to
  `~/.local/state/omarchy/agents/usage/`, and `omarchy-agent-usage-update`
  globs `$OMARCHY_PATH/bin/omarchy-agent-usage-*`, so a new collector is all
  the panel needs to grow an Antigravity tab with meters and charts.
- `assets/antigravity.svg` (+ `-light` twin) — panel mark.
- `patches/` — adds an `antigravity` case to `omarchy-default-agent` and
  `omarchy-agent` so it can be set as default agent and launched
  (`agy --dangerously-skip-permissions`).
- `extensions/omarchy-menu-antigravity.jsonc` — replaces the Gemini row in
  Setup > Default Agent with Antigravity (merged into
  `~/.config/omarchy/extensions/omarchy-menu.jsonc`).

## How the collector works

Rate limits: `agy -p "/usage"` prints the quota table (Gemini and
Claude/GPT groups, 5-hour and weekly windows, remaining % and reset time).
agy does its own auth (system keyring entry `service=gemini
username=antigravity`, file fallback), so the collector never touches
OAuth. Output is tab-separated when piped. The probe is cached for 10
minutes (`~/.cache/omarchy/agent-usage/antigravity-limits.json`) because agy
startup is heavy; a failed probe keeps the last good meters and says so in
the panel status line. Calling the raw quota API directly
(`cloudcode-pa.googleapis.com/v1internal:retrieveUserQuotaSummary`) was
tried first and 403s (SUBSCRIPTION_REQUIRED) for consumer logins unless you
replicate agy's whole client identity, hence the CLI route.

Local token stats: the Antigravity CLI writes one SQLite db per
conversation under `~/.gemini/antigravity-cli/conversations/`. Each
`gen_metadata` row is a `GeneratorMetadata` protobuf; the collector ships a
tiny wire-format reader (field numbers cross-checked against tokscale's
reverse-engineered parser, see references). Per-turn timestamps are not
decodable on current agy builds, so turns are bucketed by the conversation's
created-at date from `trajectory_metadata_blob` (file mtime fallback);
conversations spanning midnight land on their starting day. "Prompts" in
the record are generations (model calls), not user prompts.

## Install / update

```
./install.sh
```

Collector and icons are additive files pacman does not own, so omarchy
package upgrades keep them. The two launcher scripts ARE pacman-owned
(symlinks in `$OMARCHY_PATH/bin` resolving to `/usr/bin`), so an omarchy
upgrade reverts those patches: re-run `./install.sh` after upgrading
(it detects already-patched files and skips them). If upstream omarchy ever
ships its own antigravity support, delete
`/usr/share/omarchy/bin/omarchy-agent-usage-antigravity`, the two svg
assets, and the menu extension row, and skip the patches.

Refresh manually: `omarchy agent usage-update antigravity` (or `--force`).
Panel IPC: `omarchy-shell omarchy.agents <open|refresh|next>`.

## References

- Agents plugin contract: `/usr/share/omarchy/shell/plugins/agents/README.md`
  ("Adding an agent ... ship a collector that prints the record contract")
- gen_metadata field map: junhoyeo/tokscale,
  `crates/tokscale-core/src/sessions/antigravity_cli.rs`
- Endpoints and auth landscape: steipete/CodexBar `docs/antigravity.md`,
  `docs/gemini.md`
- Antigravity CLI /usage docs: https://antigravity.google/docs/cli/commands/usage/

## Caveats

- `agy -p "/usage"` takes a few seconds and does not create conversation
  dbs or burn model quota (verified: db count unchanged, quota unchanged).
- Day bucketing is per conversation, not per turn (see above).
- The plan line (tierLabel) is blank by default; set it via
  `~/.config/omarchy/agents/antigravity.json` -> `{"tierLabel": "Pro"}`.
- The `gemini` agent entry still exists and untouched; only the menu row was
  repointed at antigravity.
