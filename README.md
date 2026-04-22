# aufo.voicemail

Website with instructions how to participate in Aufo trials.

It is a single static page (`index.html`) — no build step, no server required. Open the file directly or host it on any static web host (GitHub Pages, Netlify, Cloudflare Pages, etc.).

## Feedback storage

The feedback form posts directly from the browser to a [Supabase](https://supabase.com) project (REST endpoint `/rest/v1/feedback`) using the publishable anon key embedded in `index.html`. Row Level Security only permits inserts, so the key is safe to publish.

To view collected submissions: Supabase dashboard → Table Editor → `feedback`.

## Database schema

The schema lives under `supabase/migrations/`. To apply changes to the linked project:

```
supabase db push
```

(requires the [Supabase CLI](https://supabase.com/docs/guides/cli) and `supabase link --project-ref <ref>`).
