# aufo.voicemail
Website with instructions how to participate in Aufo Trials

## Run locally

1. Install Node.js (v18+ recommended)
2. Start the server:

	 npm start

3. Open:

	 http://localhost:3000

## Feedback storage

- Feedback form submissions are sent to `POST /api/feedback`.
- The server appends each submission as one JSON line to:

	`feedback-submissions.jsonl`

- To inspect collected submissions from all visitors/devices that hit this server:

	`GET /api/feedback`
