# MUDA Decision Log

This file records decisions that should survive individual Codex sessions. Add a
new dated entry when a decision changes; do not silently rewrite history.

## 2026-08-29 — Events publish immediately

**Decision:** A newly created event is stored as `published`, receives a
`published_at` value immediately, and currently uses `review_status =
not_required`.

**Reason:** The MVP does not require admin approval before an activity becomes
visible. Admin review endpoints are retained for a possible future moderation
policy.

**Consequence:** Do not introduce a mandatory pending-review screen or hide new
events unless a later product decision explicitly changes this rule.

## 2026-08-29 — MUDA does not process activity payments

**Decision:** The platform shows an organizer-provided estimated per-person
offline cost in KRW but provides no payment, transfer, escrow, refund, or financial
guarantee.

**Reason:** Payments and platform fees are outside the MVP, and advance transfers
between strangers create fraud and safety risks.

**Consequence:** Join confirmation must communicate the estimate and safety
warning. Amount `0` means free. Product copy must not imply that MUDA charges or
guarantees the amount.

## 2026-08-29 — Exact meeting points are approval-gated

**Decision:** Event lists never return the exact meeting point. Event detail may
return it only to the organizer or a participant whose status is `approved` or
`attended`.

**Reason:** A precise offline location is sensitive and should only be revealed to
people accepted into the activity.

**Consequence:** Anonymous, pending, waitlisted, rejected, and withdrawn users see
only public city/region information. Every new detail or participation endpoint
must preserve this authorization boundary.

## 2026-08-29 — Catalogs and regions are database-backed

**Decision:** Flutter loads activity categories and administrative regions from
the API. Stable administrative codes are identifiers; the admin manages localized
names, order, and active state.

**Reason:** Hard-coded catalogs diverge across clients and prevent operational
updates.

**Consequence:** Do not add production category/region lists to Dart. A referenced
region cannot be physically deleted; disable it instead. The current seed is not a
complete official Korea administrative dataset.

## 2026-08-29 — Preserve existing category icons pending migration

**Decision:** Existing database emoji icon values remain valid for now. The
preferred future direction is a stable `icon_key` mapped to Flutter Material icons
with optional SVG support later.

**Reason:** The product may move away from emoji, but deleting current data before
a compatibility migration would break existing categories and clients.

**Consequence:** Any icon-system change needs a new migration, fallback behavior,
and coordinated App/Admin/API updates.

## 2026-09-01 — Documentation is split by responsibility

**Decision:** Repository guidance is organized as follows:

- `AGENTS.md`: durable working instructions and invariants.
- `PROJECT.md`: stable product and architecture overview.
- `HANDOFF.md`: current implementation state and next action.
- `DECISIONS.md`: durable decisions and rationale.
- `DEVELOPMENT_CONTEXT.md`: retained detailed historical reference.

**Reason:** A single growing context file mixes permanent rules with volatile
session state, increasing token use and making stale information harder to spot.

**Consequence:** Update only the file whose responsibility changed. Keep handoffs
concise, reference source paths instead of copying code, and verify claims against
the repository before acting.

## 2026-09-07 — User-facing location names follow the App locale

**Decision:** Reverse-geocoded labels use the language selected inside the App,
not the device or browser locale. Chinese requests explicitly prefer Simplified
Chinese, and cached labels are isolated by App language.

**Reason:** A device locale or stale shared cache could otherwise show Traditional
Chinese while the App itself is set to Simplified Chinese.

**Consequence:** Any future geocoder must accept the current App language and must
not reuse a human-readable location label across different languages.
