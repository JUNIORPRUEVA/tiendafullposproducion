ALTER TABLE "marketing_daily_stories"
ADD COLUMN "instagram_media_id" TEXT,
ADD COLUMN "instagram_story_id" TEXT,
ADD COLUMN "instagram_container_id" TEXT,
ADD COLUMN "published_channels" TEXT[] DEFAULT ARRAY[]::TEXT[] NOT NULL,
ADD COLUMN "publish_targets" TEXT[] DEFAULT ARRAY[]::TEXT[] NOT NULL;

UPDATE "marketing_daily_stories"
SET
  "instagram_media_id" = COALESCE("instagram_media_id", "instagram_post_id"),
  "published_channels" = CASE
    WHEN COALESCE("facebook_post_id", '') <> '' AND COALESCE("instagram_post_id", '') <> ''
      THEN ARRAY['facebook_post', 'instagram_post']::TEXT[]
    WHEN COALESCE("facebook_post_id", '') <> ''
      THEN ARRAY['facebook_post']::TEXT[]
    WHEN COALESCE("instagram_post_id", '') <> ''
      THEN ARRAY['instagram_post']::TEXT[]
    ELSE ARRAY[]::TEXT[]
  END,
  "publish_targets" = CASE
    WHEN COALESCE("instagram_post_id", '') <> '' OR COALESCE("facebook_post_id", '') <> ''
      THEN ARRAY['facebook_post', 'instagram_post']::TEXT[]
    ELSE ARRAY[]::TEXT[]
  END;