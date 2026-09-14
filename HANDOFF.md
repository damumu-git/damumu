# DAMUMU Session Handoff

Updated: 2026-09-07 (Asia/Seoul)

## Current objective

Finish the real, database-backed event participation loop before broad UI polish
or unrelated refactoring.

The permanent Latin-letter product brand is now `DAMUMU`; the previous uppercase
brand has been removed from tracked source and documentation. Lowercase and
PascalCase internal identifiers are retained for compatibility pending a separate
migration.

An independent static introduction website now lives in `website/dist/`. It
describes the App without depending on the Flutter, API, or Admin runtimes.

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

Recent UI startup fix:

- The Flutter web loader now stays opaque until browser fonts are ready and at
  least 300 ms after `flutter-first-frame`. This prevents CanvasKit's transient
  missing-glyph squares from flashing during a slow startup; the former delay
  was measured from page load and therefore became zero when startup exceeded
  650 ms.

Recent ownership and localization fixes:

- Public event cards compare `organizer_user_id` with the signed-in user and mark
  matching rows as `我发布的`. Their detail CTA opens `我的活动` instead of offering
  join, waitlist, or leave actions.
- Reverse-geocoded location labels now follow the App locale (`zh-Hans`, `ko`, or
  `en`) and use language-specific v3 caches, invalidating older Traditional
  Chinese labels.
- Admin npm dependencies are installed locally, audit reports zero known
  vulnerabilities, and build/lint pass. The Vite development server was verified
  at `http://localhost:5173` with the API and dashboard endpoints returning 200.
- Activity capacity now includes the organizer as the first approved person.
  Migration `009_count_organizer_in_capacity.sql` repairs historical counters;
  it was applied to the configured target database and verified with no count or
  organizer mismatches.
- Organizer activity records now load pending applications and can approve or
  reject them (with a required reason) through the real member-review endpoints.
- Home filters now use raw start timestamps, geocoded coordinates/region fallback,
  popularity ordering, and a server-provided beginner-friendly signal instead of
  relying only on formatted display strings.

Connected to real API/database paths:

- Registration, login, session restoration, profiles, and avatars.
- Category and administrative-region catalogs.
- Event creation and home/discovery event lists.
- My Activities for hosted and joined activities.
- Broad admin operations.

Available in the API but not yet complete in the Flutter app:

- `GET /events/{id}` as the source of truth for event details.
- Real join and leave flows.
- Full organizer member management beyond pending approval/rejection.
- Event edit, cancel, and check-in.
- Real notifications, conversations, and messages.
- Reports, blocking, reviews, and safety-meeting flows.

## Recommended next actions

1. Install or expose a Flutter SDK on this host, then run `flutter analyze` and
   `flutter test`; the ownership widget test has been added but could not run here.
2. Inspect the current event model and usages, then replace the Flutter
   `EventItem.id` integer/hash representation with the real UUID string.
3. Load event details from `GET /events/{id}` rather than relying on the list item
   and local UI state.
4. Connect join and leave actions to the API.
5. Add the join confirmation content: no platform payment/escrow, no advance
   transfer to strangers, offline personal/property safety, and expected KRW cost.
6. Complete organizer capacity, approved-member, and waitlist management beyond
   the connected pending approval/rejection actions.
7. Make My Activities open the real detail and expose appropriate organizer
   actions.
8. Connect notifications and activity chat, then governance and safety flows.

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
