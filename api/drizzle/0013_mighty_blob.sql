ALTER TABLE "note" ALTER COLUMN "created_at" DROP DEFAULT;--> statement-breakpoint
ALTER TABLE "note" ALTER COLUMN "updated_at" DROP DEFAULT;--> statement-breakpoint
ALTER TABLE "task" ALTER COLUMN "created_at" DROP DEFAULT;--> statement-breakpoint
ALTER TABLE "task" ADD COLUMN "updated_at" timestamp with time zone;--> statement-breakpoint
UPDATE "task" SET "updated_at" = "created_at" WHERE "updated_at" IS NULL;--> statement-breakpoint
ALTER TABLE "task" ALTER COLUMN "updated_at" SET NOT NULL;