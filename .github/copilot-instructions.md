# Copilot instructions — aufo.voicemail

Concise, project-specific guidance so an AI agent can be productive immediately. Keep edits aligned with the conventions below.

## What this project is

- **Single static page** ([index.html](../index.html)) for recruiting/instructing participants in an audio-forensics voicemail study.
- **No build step, no bundler, no framework.** Vanilla HTML + inline `<style>` + inline `<script>`.
- Hosting: open the file directly (works with `file://`) or drop it on any static host (GitHub Pages, Netlify, Cloudflare Pages, …).

## Architecture (the whole picture)

```
Browser (index.html)
   │   POST JSON
   ▼
Supabase REST  https://tbfnxnfnsabajfkkkxvg.supabase.co/rest/v1/feedback
   │   anon RLS policy: INSERT only
   ▼
Postgres table  public.feedback   (managed via supabase/migrations/*.sql)
```

- The page formerly had a Node.js backend (`server.js`, `package.json`, `feedback-submissions.jsonl`). **It has been removed.** Do not reintroduce a local server unless explicitly asked. If you see references to `/api/feedback`, `localhost:3000`, `feedback-submissions.jsonl`, or `npm start` — they're stale.
- Project ref: `tbfnxnfnsabajfkkkxvg`. Publishable (anon) key is embedded in [index.html](../index.html) and is safe to commit (RLS only allows `INSERT` on `public.feedback`).
- DB schema is owned by the repo: source of truth is [supabase/migrations](../supabase/migrations). Apply with `supabase db push`.

## Frontend conventions

- **i18n**: every user-visible string has a `data-i18n="key"` (or `data-i18n-placeholder="key"`) attribute and an entry under both `en` and `de` in the `translations` dict at the bottom of [index.html](../index.html). When adding UI, **always add both languages** and the `data-i18n*` attribute. `applyLanguage(lang)` walks the DOM and swaps text/placeholders. Default lang is `en`; toggle buttons live in the header.
- **Single-file rule**: keep CSS in the `<style>` block and JS in the `<script>` block at the bottom. The user previously deleted a separate `style.css` — do not re-extract assets unless asked.
- **Form payload → snake_case**: the `feedbackForm` submit handler maps camelCase form fields to the snake_case columns Supabase expects (`participant_id`, `voicemail_language`, `ease_rating`, `feedback_text`, `ui_language`, `submitted_at`). `received_at` is filled by Postgres `default now()`. Don't change column casing.
- **Error UX**: surfaces the backend error message in parentheses after the localized base error (`feedbackError`). Successful submit shows `feedbackSuccess`. Both message keys exist in the translations dict.

## Database conventions

- All schema changes go through a **new migration file** under [supabase/migrations](../supabase/migrations) using the timestamp prefix `YYYYMMDDHHMMSS_description.sql`. Never edit historical migrations.
- Use **idempotent DDL**: `drop constraint if exists … ; add constraint …` so re-runs are safe. See [supabase/migrations/20260422000000_feedback_constraints.sql](../supabase/migrations/20260422000000_feedback_constraints.sql) as the canonical pattern.
- Active CHECK constraints on `public.feedback` (do not weaken without reason — the table is open to anonymous inserts):
  - `ease_rating` is `NULL` or 1–5
  - `feedback_text` ≤ 4000 chars
  - `participant_id` ≤ 64 chars
  - `voicemail_language` ≤ 32 chars
  - `ui_language` ≤ 8 chars
- RLS is **enabled**; only the `anon can insert feedback` policy exists. Reading is via the dashboard / service-role key only.

## Supabase CLI workflow (this machine)

- Binary: `~/.local/bin/supabase` (v2.90.0). Add `~/.local/bin` to PATH if invoking from a fresh shell.
- Project is already linked (`supabase link --project-ref tbfnxnfnsabajfkkkxvg`). Local CLI cache lives in `supabase/.temp/` and is gitignored (it contains the pooler URL with the DB password).
- Standard flow for a schema change:
  1. Write `supabase/migrations/<ts>_<name>.sql`
  2. `supabase db push --include-all --yes` (use `SUPABASE_ACCESS_TOKEN` env var + `--password '<db_pw>'` for non-interactive runs)
- **Credentials**: never echo or commit Personal Access Tokens or DB passwords. If the user pastes one, use it for the operation, then remind them to rotate it. The publishable anon key is the only key that may live in source.

## Git conventions

- Default branch: `main`. Remote: `git@github.com:vhock/aufo.voicemail.git`.
- The user sometimes amends/rewrites already-pushed commits, causing "branch diverged" with the same commit message on both sides. The fix is `git push --force-with-lease origin main` after confirming the local tree is the desired state. Never force-push without diffing local vs remote first (`git diff <local> <remote>`) and confirming with the user.
- `.gitignore` essentials: `.vscode/`, `supabase/.temp/`, `supabase/.branches/`. Do **not** re-add `node_modules/` or `feedback-submissions.jsonl` — they belong to the removed backend.

## Things to avoid

- Do **not** create new Markdown summary/changelog files unless explicitly requested.
- Do **not** introduce build tooling, package managers, or frameworks. Project is intentionally zero-dependency on the frontend.
- Do **not** wire the form to a new backend without removing the Supabase fetch first; only one storage destination at a time.
- Do **not** add `select` policies to `public.feedback` — submissions must not be readable by anonymous visitors.
