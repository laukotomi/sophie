# Sophie

Hi there, Sophie is a mobile-first (with web app support) notes and task manager that I created for myself and for my wife, Sophie. I was using Moe Memos before but it was missing some features I needed, like shared notes. Through the months I put more and more features in this app so I decided to release it on GitHub. However this description is not complete yet as I use it via Debian package but soon I'll add a guide and pipeline to build docker image.

## What It Does

- Create and edit notes with colors, todo list mode, and optional pinning behavior.
- Share notes with collaborators using view or edit permissions.
- Attach files to notes.
- Create one-off or recurring tasks.
- Add task alerts as absolute times or relative reminders before a due date.
- Alarm snooze.
- Offline mode if there is no connection to the backend.

## Repository Layout

```text
.
├── api/      # Hono + TypeScript + Drizzle + PostgreSQL backend
└── mobile/   # Flutter client for Android, iOS, desktop, and web targets
```

## Tech Stack

### Mobile

- Flutter
- get_it for service location
- shared_preferences for local persistence
- awesome_notifications and alarm for alerts
- rrule and rrule_generator for recurring tasks
- file_picker for attachments

### API

- Node.js
- TypeScript
- Hono
- better-auth
- Drizzle ORM
- PostgreSQL

## Architecture Overview

### Mobile app

The Flutter app initializes local storage and notification services on startup, then signs in against a user-provided server URL. Domain logic is split into small services for backend access, storage, alerts, and event handling.

Main areas:

- `lib/screens/` contains the UI flows such as login, home, notes, tasks, and snooze handling.
- `lib/services/` contains backend clients, storage, alert scheduling, and event buses.
- `lib/events/` contains the note and task event models used for local apply and later sync.

### Backend

The API is a Hono server with route modules for notes, tasks, dashboard data, auth token exchange, and file handling. Authentication is provided by better-auth, persistence is handled through Drizzle ORM, and the database schema is managed with SQL migrations in `api/drizzle/`.

Main endpoints:

- `/api/auth/**`
- `/api/token`
- `/api/dashboard`
- `/api/notes`
- `/api/tasks`
- `/api/files`

## Prerequisites

### For the API

- Node.js 18+
- npm
- PostgreSQL

### For the mobile app

- Flutter SDK compatible with `sdk: ^3.11.4`
- A configured Android, iOS, desktop, or web toolchain depending on your target

## Quick Start

### Option 1: Run the API with Docker Compose

From `api/`:

```bash
docker-compose up --build
```

This starts:

- PostgreSQL
- the Sophie API on `http://localhost:3000`
- Adminer on `http://localhost:8888`

### Option 2: Run the API manually

1. Create an env file in `api/`.
2. Install dependencies.
3. Run migrations.
4. Start the dev server.

Example:

```bash
cd api
cp .env.example .env
npm ci
npm run db:migrate
npm run dev
```

## API Environment Variables

Set these in `api/.env`:

```env
DATABASE_URL=postgres://user:password@localhost:5432/sophie
PORT=3000
ORIGIN=http://localhost:3000
CORS_ORIGIN=http://localhost:5173
UPLOADS_DIR=./uploads
BETTER_AUTH_SECRET=change-me-to-a-long-random-secret
```

Notes:

- `BETTER_AUTH_SECRET` should be replaced with a long random value.
- `UPLOADS_DIR` must point to a writable directory.
- `ORIGIN` must match the base URL the auth system should use.

## Create the First User

The mobile app signs in with email and password. To create the first account:

```bash
cd api
npm run create-user
```

The script prompts for:

- email
- password
- name

## Run the Mobile App

```bash
cd mobile
flutter pub get
flutter run
```

On first login, the app asks for:

- server URL
- email
- password

For a local Android emulator, `http://10.0.2.2:3000` is usually the correct server URL. For a physical device, use your computer's LAN IP address, for example `http://192.168.x.y:3000`.

## Useful Commands

### API

```bash
npm run dev
npm run build
npm start
npm run db:push
npm run db:generate
npm run db:migrate
npm run db:studio
npm run auth:schema
npm run create-user
```

### Mobile

```bash
flutter pub get
flutter run
flutter test
flutter build apk
flutter build ios
```

## Data Model Highlights

The backend stores:

- users and auth/session records
- notes and note history
- note collaborators and per-user note ordering
- note file metadata
- tasks, collaborators, and task alerts

Task alerts support two reminder styles:

- absolute date-time reminders
- relative reminders before the task due date

## Operational Notes

- The Docker Compose file currently contains development credentials and should not be used unchanged in production.
- The mobile app requests notification and exact alarm permissions at runtime.
- File uploads require both database state and a writable upload directory on the API host.
- The repository currently has little automated test coverage, so manual verification is still important for notification flows, attachments, and recurring-task behavior.

## Development Notes

- The API entrypoint runs database migrations before starting the server.
- Mobile authentication state and server URL are stored locally.
- The app is localized for English and Hungarian.

## License

See `LICENSE`.
