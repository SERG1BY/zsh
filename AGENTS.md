## Caveman Mode (Always-On Style Rules)
All agents and subagents adhere to `/caveman` style:
1. Answer first: Pattern `[thing] [action] [reason]. [next step].` No greetings, no preamble, no recaps, no conversational filler.
2. Payload verbatim: Code blocks, shell commands, file paths, numbers, and errors must remain 100% exact.
3. One idea per sentence: 20 words max per sentence, active voice, imperative instructions.
4. Preserve critical semantics: Never drop negations (`not`, `never`, `no`, `only`, `except`).
5. No performance: No "me think", no broken grammar theater. Plain terse technical prose wins.
6. Tool silence: No chatter between routine tool calls; report only material outcomes.

## ripwire — deterministic codebase maps (on PATH as `ripwire`)
Reach for it BEFORE blind grep + whole-file reads. First call ~1s cold; after that warm, ~0.1s.
- Orient on a task: `ripwire <dir> --for="<task in words>"` — ranked, quality-annotated signatures.
  Paste symbol/file names from the issue verbatim; named mentions get anchored.
- One task: `--pack-task="<task>" --legend=compact`; before parallel agents: `--plan-lanes=N --task="<goal>"`, then read `lanes[].execution`.
- Have a stack trace / build error: `ripwire <dir> --from-trace=FILE --legend=compact` (`-` = stdin) — paste the error, don't paraphrase it into a query.
- Who calls X: `--callers=SYM --legend=compact`. "Is it safe to change X?" needs the full blast radius:
  `--impact=SYM --legend=compact` (transitive) plus `--uses=SYM --legend=compact` (every read/write/import site).
- Apply a whole-symbol edit without a whole-file Read: `--replace-symbol-body=SYM` plus `--edit-payload=FILE|-` (or insert-before/after).
- Before writing a new fn/class/helper: `--exemplar="<what you're writing>" --legend=compact` — duplicates are born on small tasks.
- Before calling work done: `--quality-delta --legend=compact` (what you made worse), then `--test-gate --legend=compact`.
- Trust notes: counts marked counts_floor are floors, not totals; a zero means "none found", never "none exists".

Defaults to break:
- Do NOT open a file you have not located first: rank with `--for`/`--grep`, then read what it names.
- Do NOT read a whole file to understand one symbol: `--expand=SYM --legend=compact` gives the body + callee sigs.
- Do NOT fan reads across several files to learn one thing: `--pack-task="<task>" --legend=compact` is one call.

## bHived — shared agent lessons (`mcp_bhived_*` tools, network bhived.ai)
- Before specialized, unfamiliar, or risky work: `mcp_bhived_query` with discriminative terms — exact error text, package@version, goal; failed approaches go in `context` as keyword phrases. Treat hits as leads: match your stack/versions first; a weak or off-stack match counts as no answer.
- After a verified fix or a genuine user correction: write back one lesson (`bhived_write_instruction` / `bhived_write_mistake` / `bhived_write_update`) with the SAME key and the saved `query_id`. A personal key writes public lessons — secrets, credentials, and customer data stay out.
- Child MCPs and skill scripts run locally: audit with `bhived_list_active`, release with `bhived_stop_mcp`, report real outcomes with `bhived_report_outcome`.
- This machine: the server runs from the native `node` entry in config.yaml (`mcp_servers.bhived`); the plugin's own npx entry is broken by the filtered-env spawn. Install, config, troubleshooting: `setup-bhived.md`.

## EGM skills — artifact placement (no repo litter)
When running `egm-*` skills (`/egm-brainstorm`, `/egm-draft`, `/egm-review`, `/egm-resolve`, `/egm-review-loop`, `/egm-drift-report`, `egm-lite`), never scatter output across the repo root or `docs/`. All EGM artifacts live under the project's `egm/` directory:
- Concepts briefs: `egm/concepts/<feature-slug>.md` (never a root-level `concepts_brief.md`).
- Design docs: `egm/designs/<feature-slug>.md` (never `design_draft.md` in the repo root, never `docs/designs/`).
- Review reports: `egm/reviews/<cycle>/<lens>.md` (never `docs/research/reviews/`).
- Drift reports: `egm/drift/<YYYY-MM-DD>_DRIFT_REPORT.md` (never the working directory root).
- Scratch (review cycles, `.tmp` files): Hermes scratch dir, not the repo.
- Best-practices dossiers (verified against current official documentation): `docs/research/` — these are durable, cited references and stay in the repo.
The skills' SKILL.md files name root-level and `docs/` default paths — treat those as overridden by this rule. `egm/update.sh` re-syncs skills from upstream google/elephant-goldfish-model; run it after upstream changes, expect local path conventions to be re-applied if SKILL.md files are ever patched.

## Agent skills

### Issue tracker

Local markdown: issues live as files under `.scratch/<feature-slug>/` in this repo (no remote). See `docs/agents/issue-tracker.md`.

### Triage labels

Default five-role vocabulary, label string equals role name (`needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`). See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: root `GLOSSARY.md` + `docs/adr/`. See `docs/agents/domain.md`.
