BEGIN;

-- Retain existing members, even when a group already exceeds the new cap.
UPDATE web_group SET capacity=50 WHERE capacity IS NULL OR capacity>50;
ALTER TABLE web_group ALTER COLUMN capacity SET DEFAULT 50;
ALTER TABLE web_group DROP CONSTRAINT IF EXISTS ck_web_group_capacity_limit;
ALTER TABLE web_group ADD CONSTRAINT ck_web_group_capacity_limit CHECK (capacity BETWEEN 2 AND 50);

COMMIT;
