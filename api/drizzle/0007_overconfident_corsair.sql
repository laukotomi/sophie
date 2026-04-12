ALTER TABLE "note" ADD COLUMN "editing_by" text;--> statement-breakpoint
ALTER TABLE "note" ADD COLUMN "locked_until" timestamp with time zone;--> statement-breakpoint
ALTER TABLE "note" ADD CONSTRAINT "note_editing_by_user_id_fk" FOREIGN KEY ("editing_by") REFERENCES "public"."user"("id") ON DELETE set null ON UPDATE no action;