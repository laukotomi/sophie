CREATE TABLE "note_order" (
	"user_id" text NOT NULL,
	"note_id" text NOT NULL,
	"position" integer NOT NULL
);
--> statement-breakpoint
ALTER TABLE "note_order" ADD CONSTRAINT "note_order_user_id_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "note_order" ADD CONSTRAINT "note_order_note_id_note_id_fk" FOREIGN KEY ("note_id") REFERENCES "public"."note"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
CREATE UNIQUE INDEX "note_order_user_id_note_id_idx" ON "note_order" USING btree ("user_id","note_id");