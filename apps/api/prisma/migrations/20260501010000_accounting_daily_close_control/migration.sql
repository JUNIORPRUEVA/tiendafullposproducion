-- Accounting daily closing control.
ALTER TYPE "CloseType" ADD VALUE IF NOT EXISTS 'PHYTOEMAGRY';

ALTER TABLE "Close"
ADD COLUMN IF NOT EXISTS "otherIncome" DECIMAL(12,2) NOT NULL DEFAULT 0,
ADD COLUMN IF NOT EXISTS "notes" TEXT,
ADD COLUMN IF NOT EXISTS "evidenceUrl" TEXT,
ADD COLUMN IF NOT EXISTS "evidenceFileName" TEXT,
ADD COLUMN IF NOT EXISTS "reviewedById" UUID,
ADD COLUMN IF NOT EXISTS "reviewedByName" TEXT,
ADD COLUMN IF NOT EXISTS "reviewedAt" TIMESTAMP(3);

UPDATE "Close" SET "status" = 'approved' WHERE "status" = 'closed';
UPDATE "Close" SET "status" = 'pending' WHERE "status" IS NULL OR "status" = 'draft';

CREATE INDEX IF NOT EXISTS "Close_reviewedById_idx" ON "Close"("reviewedById");

CREATE INDEX IF NOT EXISTS "Close_type_date_active_idx"
ON "Close"("type", "date")
WHERE "status" <> 'rejected';
