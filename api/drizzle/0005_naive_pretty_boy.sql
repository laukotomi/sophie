CREATE TABLE "task" (
	"id" text PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"owner" text NOT NULL,
	"text" text NOT NULL,
	"rrule" text,
	"due_at" timestamp with time zone,
	"done_at" timestamp with time zone,
	"created_at" timestamp DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "task_alert" (
	"id" serial PRIMARY KEY NOT NULL,
	"task_id" text NOT NULL,
	"alert_at" timestamp with time zone,
	"time_before" time
);
--> statement-breakpoint
CREATE TABLE "task_collaborator" (
	"id" serial PRIMARY KEY NOT NULL,
	"user_id" text NOT NULL,
	"task_id" text NOT NULL
);
--> statement-breakpoint
ALTER TABLE "task" ADD CONSTRAINT "task_owner_user_id_fk" FOREIGN KEY ("owner") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "task_alert" ADD CONSTRAINT "task_alert_task_id_task_id_fk" FOREIGN KEY ("task_id") REFERENCES "public"."task"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "task_collaborator" ADD CONSTRAINT "task_collaborator_user_id_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "task_collaborator" ADD CONSTRAINT "task_collaborator_task_id_task_id_fk" FOREIGN KEY ("task_id") REFERENCES "public"."task"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
CREATE UNIQUE INDEX "task_collaborator_user_id_task_id_idx" ON "task_collaborator" USING btree ("user_id","task_id");