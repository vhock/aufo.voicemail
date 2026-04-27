# Copilot instructions — aufo.voicemail

Concise, project-specific guidance so an AI agent can be productive immediately. Keep edits aligned with the conventions below.

## What this project is

- **Single static page** ([index.html](../index.html)) for recruiting/instructing participants in an audio-forensics voicemail study.
- **No build step, no bundler, no framework.** Vanilla HTML + inline `<style>` + inline `<script>`.
- Hosting: open the file directly (works with `file://`) or drop it on any static host (GitHub Pages, Netlify, Cloudflare Pages, …).

## Architecture (the whole picture)

```
Browser (index.html)
   │   POST JSON  (REST + RPC calls)
   ▼
Supabase REST  https://tbfnxnfnsabajfkkkxvg.supabase.co
   │   anon RLS policy: INSERT only on public.feedback;
   │   anon EXECUTE on RPCs register_or_get_participant, request_participant_deletion
   ▼
Postgres tables  public.feedback, public.participants   (managed via supabase/migrations/*.sql)
```

- The page formerly had a Node.js backend (`server.js`, `package.json`, `feedback-submissions.jsonl`). **It has been removed.** Do not reintroduce a local server unless explicitly asked. If you see references to `/api/feedback`, `localhost:3000`, `feedback-submissions.jsonl`, or `npm start` — they're stale.
- Project ref: `tbfnxnfnsabajfkkkxvg`. Publishable (anon) key is embedded in [index.html](../index.html) and is safe to commit (RLS enforces what `anon` can do).
- DB schema is owned by the repo: source of truth is [supabase/migrations](../supabase/migrations). Apply with `supabase db push`.
- **Two write paths** the browser uses today:
  - `POST /rest/v1/feedback` → direct table insert into `public.feedback`.
  - `POST /rest/v1/rpc/<name>` → `security definer` RPCs for everything that needs to read/update existing rows (registration, deletion request). Prefer the RPC pattern when the operation needs more than a plain insert; it lets us keep `select`/`update` off the anon role.

## Frontend conventions

- **i18n**: every user-visible string has a `data-i18n="key"` (or `data-i18n-placeholder="key"`) attribute and an entry under both `en` and `de` in the `translations` dict at the bottom of [index.html](../index.html). When adding UI, **always add both languages** and the `data-i18n*` attribute. `applyLanguage(lang)` walks the DOM and swaps text/placeholders. Default lang is `en`; toggle buttons live in the header.
- **Inline HTML in translations**: i18n values may contain markup (`<strong>`, `<a href="#…">`) — `applyLanguage` uses `el.innerHTML`. When rendering a translation from JS, use `innerHTML` (not `textContent`) if the string is allowed to contain markup, and use `.replace('{id}', value)` for placeholders (see the deletion handler).
- **`data-i18n-locked`**: when JS replaces a `[data-i18n]` element's content with a *dynamic* string (e.g. an error message that includes a backend detail), set `el.setAttribute('data-i18n-locked', '1')` so `applyLanguage` skips it on the next language switch. Clear with `removeAttribute('data-i18n-locked')` when re-entering a clean state. Used by `#msg` and `#feedbackMsg`.
- **Phone-input loading guard**: `intl-tel-input` is loaded synchronously in `<head>` (do **not** add `defer` — the inline body script reads `window.intlTelInput` at parse time and would race with a deferred load). The `ITI_LOADED` flag + `FALLBACK_DE_PHONE_RE` (`/^\+?49[1-9]\d{6,12}$/`) keep all forms working if the CDN is blocked.
- **`readPhone(inputEl, itiInstance, errorEl, dict)` helper**: returns the validated E.164 phone string or `null` (and renders the appropriate error). Use it from any new form that asks for a German phone number — don't re-implement validation.
- **Single-file rule**: keep CSS in the `<style>` block and JS in the `<script>` block at the bottom. The user previously deleted a separate `style.css` — do not re-extract assets unless asked.
- **Form payload → snake_case**: the `feedbackForm` submit handler maps camelCase form fields to the snake_case columns Supabase expects (`participant_id`, `voicemail_language`, `ease_rating`, `feedback_text`, `ui_language`, `submitted_at`). `received_at` is filled by Postgres `default now()`. Don't change column casing.
- **Phone input**: uses `intl-tel-input@25` (loaded via CDN) with `intlTelInputWithUtils` for libphonenumber validation. The site is German-only (`onlyCountries: ['de']`, `allowDropdown: false`). Each phone field needs its own `intlTelInput` instance — see `iti` (registration) and `deletionIti` (deletion request) for the canonical setup.
- **Error UX**: surfaces the backend error message in parentheses after the localized base error (e.g. `feedbackError`, `registerError`, `deletionError`). Successful submit shows the corresponding `*Success` key. All message keys must exist in **both** `en` and `de` dicts.
- **Anchor links between sections**: when an FAQ entry or instruction needs to point to another section of the same page, give the target `<div>` an `id` and link via `<a href="#that-id">…</a>` inside the translation string. Existing example: FAQ "How is my data handled?" → `#deletionSection`.

## Database conventions

- All schema changes go through a **new migration file** under [supabase/migrations](../supabase/migrations) using the timestamp prefix `YYYYMMDDHHMMSS_description.sql`. Never edit historical migrations.
- Use **idempotent DDL**: `drop constraint if exists … ; add constraint …`, `add column if not exists …`, `create or replace function …` so re-runs are safe. See [supabase/migrations/20260422000000_feedback_constraints.sql](../supabase/migrations/20260422000000_feedback_constraints.sql) for the constraint pattern.
- **RPC pattern** (see [20260422190000_participants_register_rpc.sql](../supabase/migrations/20260422190000_participants_register_rpc.sql), [20260423000000_participants_phone_model.sql](../supabase/migrations/20260423000000_participants_phone_model.sql), [20260427000000_participants_deletion_request.sql](../supabase/migrations/20260427000000_participants_deletion_request.sql)):
  - Declare with `language plpgsql security definer` so the function runs as `postgres` and can `select`/`update` without exposing those grants to anon.
  - Always `grant execute on function public.<name>(<arg-types>) to anon;` — without this, the browser gets a 404/permission error from PostgREST.
  - When you change the **signature** of an existing RPC, drop the old signature explicitly (`drop function if exists public.<name>(<old types>);`) so PostgREST doesn't see two overloads. The participants RPC migrations show this in action.
  - Return JSON via `json_build_object(...)` with a `status` discriminator. Current statuses across RPCs: `'created' | 'existing'` (registration), `'flagged' | 'already' | 'not_found' | 'invalid_input' | 'rate_limited'` (deletion). The frontend switches on that and looks up a matching translation key.
- **Soft-delete + scheduled purge**: deletion requests don't hard-delete; they set `participants.deletion_requested_at` and bump `deletion_request_count` (cap = 5, then `rate_limited`). Hard delete happens via `public.purge_flagged_participants()` (rows older than 24h), scheduled by `pg_cron` if the extension is available — see [supabase/migrations/20260428000000_deletion_purge_function.sql](../supabase/migrations/20260428000000_deletion_purge_function.sql). The DO-block wraps the schedule call in EXCEPTION handlers so the migration still applies cleanly on tiers without `pg_cron`.
- Active CHECK constraints on `public.feedback` (do not weaken without reason — the table is open to anonymous inserts):
  - `ease_rating` is `NULL` or 1–5
  - `feedback_text` ≤ 4000 chars
  - `participant_id` ≤ 64 chars
  - `voicemail_language` ≤ 32 chars
  - `ui_language` ≤ 8 chars
- Active constraints on `public.participants`: length checks on `participant_id` (1–64), `email` (3–254), `phone` (3–32), `phone_model` (1–128), `ui_language` (≤8), plus a `unique (phone)` constraint relied on by `register_or_get_participant`.
- RLS is **enabled** on both tables. Policies in place: `anon can insert feedback` (feedback) and `anon can insert participants` (participants). All reads/updates happen via `security definer` RPCs or the dashboard / service-role key — do **not** add `select` or `update` policies for `anon`.

## Supabase CLI workflow (this machine)

- Binary: `~/.local/bin/supabase` (v2.90.0). Add `~/.local/bin` to PATH if invoking from a fresh shell.
- Project is already linked (`supabase link --project-ref tbfnxnfnsabajfkkkxvg`). Local CLI cache lives in `supabase/.temp/` and is gitignored (it contains the pooler URL with the DB password).
- Standard flow for a schema change:
  1. Write `supabase/migrations/<ts>_<name>.sql`.
  2. `supabase db push --include-all --yes --password '<db_pw>'` — **always pass `--password` inline**. The CLI does **not** read `SUPABASE_DB_PASSWORD`; without `--password` it falls back to an interactive prompt and the command will appear to hang in non-interactive shells.
- **Running ad-hoc SQL against the linked DB**: `supabase db query --linked` requires a logged-in session (`SUPABASE_ACCESS_TOKEN` or `supabase login`). The reliable alternative is to pass the pooler URL directly:

  ```bash
  DBURL="postgresql://postgres.tbfnxnfnsabajfkkkxvg:<URL-ENCODED-PW>@aws-1-eu-north-1.pooler.supabase.com:5432/postgres"
  supabase db query --db-url "$DBURL" --output table "<sql>"
  ```

  Notes:
  - URL-encode special chars in the password (`!` → `%21`, etc.).
  - Use port **5432** (session pooler) for ad-hoc queries. Port **6543** (transaction pooler) frequently errors with `prepared statement "lrupsc_1_0" already exists` on repeated CLI calls.
- **Smoke-testing an RPC from the shell**: hit it through the public REST endpoint with the publishable anon key:

  ```bash
  SBKEY='sb_publishable_JbK3ufdlaTxjczSvYL0ZQw_fkSsEJpT'
  SBURL='https://tbfnxnfnsabajfkkkxvg.supabase.co'
  curl -s -X POST "$SBURL/rest/v1/rpc/<rpc_name>" \
    -H "Content-Type: application/json" \
    -H "apikey: $SBKEY" -H "Authorization: Bearer $SBKEY" \
    -d '{"p_arg":"value"}'
  ```

  This is exactly the path the browser takes, so a green curl run is a real end-to-end check. Cover all `status` branches the function can return, then clean up any test rows via `supabase db query --db-url …`.
- **Credentials**: never echo or commit Personal Access Tokens or DB passwords. If the user pastes one, use it for the operation, then remind them to rotate it. The publishable anon key is the only key that may live in source.

## Git conventions

- Default branch: `main`. Remote: `git@github.com:vhock/aufo.voicemail.git`.
- The user sometimes amends/rewrites already-pushed commits, causing "branch diverged" with the same commit message on both sides. The fix is `git push --force-with-lease origin main` after confirming the local tree is the desired state. Never force-push without diffing local vs remote first (`git diff <local> <remote>`) and confirming with the user.
- `.gitignore` essentials: `.vscode/`, `supabase/.temp/`, `supabase/.branches/`. Do **not** re-add `node_modules/` or `feedback-submissions.jsonl` — they belong to the removed backend.

## Things to avoid

- Do **not** create new Markdown summary/changelog files unless explicitly requested.
- Do **not** introduce build tooling, package managers, or frameworks. Project is intentionally zero-dependency on the frontend.
- Do **not** wire the form to a new backend without removing the Supabase fetch first; only one storage destination at a time.
- Do **not** add `select` or `update` policies for `anon` on `public.feedback` or `public.participants` — submissions must not be readable/mutable by anonymous visitors. Mediate any such access through a `security definer` RPC instead.
- Do **not** call `supabase db push` without `--password '<pw>'` in a non-interactive shell — it will hang on the password prompt.
- Do **not** add a second phone field without giving it its own `intlTelInput` instance and reusing the same German-only options.
