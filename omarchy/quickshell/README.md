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

It also relabels the plan on the stock Codex pane (see "Codex plan label"
below).

## Codex plan label (patches/omarchy-agent-usage-codex.patch)

The stock collector shows the raw `planType` from the Codex app-server as
the plan name, so a ChatGPT Pro account reads just "pro". OpenAI has sold
two Pro tiers since 2026-04-09: $100 (`prolite`) and $200 (`pro`). The patch
maps `planType` to a label with the price: `pro` -> "Pro 200", `prolite` ->
"Pro 100", `plus` -> "Plus", etc.; unknown plans fall back to their
title-cased raw value.

The patch also fixes an intermittent "Codex limits unavailable" with
`account/read` (or `initialize`) as the detail line (2026-10-22). The stock
`rpc_request` waits with `select()` on the pipe but reads with buffered
`readline()`. The app-server often writes two lines back to back (the
`initialize` reply plus a `remoteControl/status/changed` notification, or
`account/updated` plus the `account/read` reply, and the mise shim's banner
line before everything). When those land in one read, `readline()` pulls all
of them into Python's buffer and returns only the first. `select()` then waits
on a pipe that has nothing new, and the reply that is already buffered times
out. That is more likely when the machine is busy, which is why it came and
went. The patch reads the fd with `os.read` and splits lines from its own
buffer, carried over between requests. Reproduced by delaying each
`select()` by 0.5 s: stock failed 5 of 5 probes, patched passed 5 of 5.

History: this patch used to also change the probe's `-a untrusted` to
`-a never`, because codex 0.153.4 removed the `untrusted` value for
`--ask-for-approval` and the failed launch hid the whole pane. Omarchy 4.0.4
ships `-a on-request` itself, so that hunk is gone and only the label hunk
is left (rebuilt against 4.0.4 on 2026-10-12).

Notes on the RPC (codex 0.162.1): `account/read` returns `planType`.
`account/rateLimits/read` returns a top-level `primary`/`secondary` pair
(this account exposes only a weekly primary) plus a richer
`rateLimitsByLimitId` map where per-model limits like `codex_bengalfox`
carry both a 5-hour and weekly window; the collector reads only the
top-level pair, matching stock behavior.

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

Plan name (the "Pro" / "Ultra" line under the mark): agy exposes no plan
over the CLI or the cloudcode-pa REST API — its `SetUserTier` is empty for
consumer Google AI accounts, and `retrieveUserQuotaSummary` 403s
(SUBSCRIPTION_REQUIRED) without agy's full handshake. The plan lives only in
the local language server agy runs while a session or the remote-control
daemon is up: a Connect RPC, `GetUserStatus`, whose `userStatus.userTier`
carries the real Google One subscription (`id` like `g1-ultra-lite-tier`,
`name` "Google AI Ultra"). The `id` encodes the multiplier — `ultra-lite` is
5x, `ultra` is 20x, `pro` is the AI Pro baseline — so the collector builds a
Claude-style label ("Ultra 5x"). This differs from the internal
`planStatus.planInfo.planName`, which reads "Pro" for everyone and is only a
fallback. The collector finds that server by scanning
agy's own listening sockets (via `/proc`, skipping the HTTPS one), scrapes
the CSRF token from the server's index HTML (`__APP_CONFIG__.csrfToken`), and
POSTs `{}` to `/exa.language_server_pb.LanguageServerService/GetUserStatus`
with `x-codeium-csrf-token`. The result is cached to
`~/.cache/omarchy/agent-usage/antigravity-plan.json`, so the pane keeps
naming the plan after agy exits. Precedence: a manual `tierLabel` in
`~/.config/omarchy/agents/antigravity.json` wins, then the live plan, then
the cached plan. (Antigravity is built on Codeium/Windsurf tech, hence the
`exa.language_server_pb` service and `x-codeium-*` header.)

Local token stats: the Antigravity CLI writes one SQLite db per
conversation under `~/.gemini/antigravity-cli/conversations/`. Each
`gen_metadata` row is a `GeneratorMetadata` protobuf; the collector ships a
tiny wire-format reader (field numbers cross-checked against tokscale's
reverse-engineered parser, see references). Per-turn timestamps are not
decodable on current agy builds, so turns are bucketed by the conversation's
created-at date from `trajectory_metadata_blob` (file mtime fallback);
conversations spanning midnight land on their starting day. "Prompts" in
the record are generations (model calls), not user prompts.

## Multi-pane panel fork (eins0fx.agents)

The stock panel shows one provider at a time behind a chip switcher. The
fork in `plugin/eins0fx.agents/` shows every enabled provider side by side,
one column each, no clicking. It was made with the sanctioned
`omarchy plugin clone omarchy.agents` (which also swaps the bar layout entry
in `~/.config/omarchy/shell.json` to `eins0fx.agents`), then `Panel.qml` was
reworked: selection state and the chip row are gone, the per-provider
sections became a `ProviderPane` component instantiated in a Row, panes
split the panel viewport exactly (min width 300, else horizontal pan), the
bar icon alarms if ANY provider crosses 90%, middle-click refreshes instead
of cycling, and `h`/`l` pan horizontally. User plugins live in
`~/.config/omarchy/plugins/` and survive omarchy upgrades untouched; the
live copy IS the user config, this directory is the versioned backup
(restore with `cp -r plugin/eins0fx.agents ~/.config/omarchy/plugins/`).
Quickshell's hot reload does not rebuild already-instantiated bar widgets,
so after editing run `omarchy-restart-shell`.

## Install / update

```
./install.sh
```

Collector and icons are additive files pacman does not own, so omarchy
package upgrades keep them. The patched files in `patches/` ARE pacman-owned
(each named `<target-basename>.patch`; the bin entries are symlinks in
`$OMARCHY_PATH/bin` resolving to `/usr/bin`): `omarchy-agent`,
`omarchy-default-agent`, and `omarchy-agent-usage-codex`. An omarchy upgrade
reverts them, so re-run `./install.sh` afterwards (it reverse-dry-runs each
patch and skips ones already applied). If
upstream omarchy ever ships its own antigravity support, delete
`/usr/share/omarchy/bin/omarchy-agent-usage-antigravity`, the two svg
assets, and the menu extension row, and skip the antigravity patches.

Refresh manually: `omarchy agent usage-update <antigravity|codex>` (`--force`).
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
- The plan line (tierLabel) is auto-detected from the live language server
  and cached (see "Plan name" above). It reads blank only if the plan has
  never been fetched while agy was running; force a value with
  `~/.config/omarchy/agents/antigravity.json` -> `{"tierLabel": "Pro"}`,
  which overrides detection.
- The `gemini` agent entry still exists and untouched; only the menu row was
  repointed at antigravity.
