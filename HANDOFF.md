# MUDA Session Handoff

Updated: 2026-09-01 (Asia/Seoul)

## Current objective

Finish the real, database-backed event participation loop before broad UI polish
or unrelated refactoring.

## Repository state at handoff

The repository is located at `C:\User\damumu\github\damumu`.

At the time this handoff was created, pre-existing uncommitted state included:

- Modified: `restapi/appsettings.json`
- Untracked: `restapi/.codex-build/`

Those items predate this documentation split. Treat them as user-owned, inspect
before touching, do not commit build output, and do not copy configuration secrets
into documentation or chat output.

New documentation created in this handoff:

- `AGENTS.md`
- `PROJECT.md`
- `HANDOFF.md`
- `DECISIONS.md`

`DEVELOPMENT_CONTEXT.md` was intentionally retained as detailed historical
context; it was not replaced or deleted.

## Last known implementation status

Connected to real API/database paths:

- Registration, login, session restoration, profiles, and avatars.
- Category and administrative-region catalogs.
- Event creation and home/discovery event lists.
- My Activities for hosted and joined activities.
- Broad admin operations.

Available in the API but not yet complete in the Flutter app:

- `GET /events/{id}` as the source of truth for event details.
- Real join and leave flows.
- Organizer approval/rejection and member management.
- Event edit, cancel, and check-in.
- Real notifications, conversations, and messages.
- Reports, blocking, reviews, and safety-meeting flows.

## Recommended next actions

1. Inspect the current event model and usages, then replace the Flutter
   `EventItem.id` integer/hash representation with the real UUID string.
2. Load event details from `GET /events/{id}` rather than relying on the list item
   and local UI state.
3. Connect join and leave actions to the API.
4. Add the join confirmation content: no platform payment/escrow, no advance
   transfer to strangers, offline personal/property safety, and expected KRW cost.
5. Connect organizer member review, capacity, approval, rejection, and waitlist
   state.
6. Make My Activities open the real detail and expose appropriate organizer
   actions.
7. Connect notifications and activity chat, then governance and safety flows.

## Acceptance checks for the next vertical slice

- A real event UUID survives list -> detail -> join/leave without hashing.
- Anonymous or unapproved users cannot receive an exact meeting point.
- Joining an organizer's own event is rejected.
- Capacity is checked atomically and participant counts use people, not just row
  count.
- The app displays the real API outcome and does not silently fall back to demo
  state.
- Relevant Flutter analysis/tests and API build pass.

## Validation commands

Run only the commands relevant to the changed area, expanding to the full set for
cross-cutting work:

```bash
cd app
dart format lib test
flutter analyze
flutter test

cd ../restapi
dotnet build

cd ../admin
npm run lint
npm run build
```

Quick API checks when services and the database are running:

```bash
curl http://localhost:8080/api/v1/health
curl http://localhost:8080/api/v1/regions
curl "http://localhost:8080/api/v1/events?limit=20"
```

## Known cautions

- Confirm the active PostgreSQL container name with `docker ps`; project history
  mentions both `mudazi-postgres` and `muda-postgres`.
- Do not update Flutter golden images without visually inspecting the difference.
- Do not describe estimated activity spending as a platform fee.
- Do not require admin review for event publication unless the product policy is
  explicitly changed.
- Do not perform a large component split merely because central files are large;
  close the real user flow first.

## New-session bootstrap prompt

```text
Read AGENTS.md, PROJECT.md, HANDOFF.md, and DECISIONS.md. Then inspect git status,
the relevant source, and the tests. Reconcile documentation with the code, treat
code/migrations/test results as the source of truth, and continue from the first
unfinished item in HANDOFF.md without redoing completed work.
```

