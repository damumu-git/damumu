-- Public activity feed: fixed creation order with UUID as the unique tie-breaker.
CREATE INDEX IF NOT EXISTS ix_event_public_created_id
    ON event (created_at DESC, id DESC)
    WHERE deleted_at IS NULL AND visibility = 'public'
      AND status IN ('published', 'full');
