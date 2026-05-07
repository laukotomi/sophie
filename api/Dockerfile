FROM node:alpine AS builder

WORKDIR /app

COPY package.json package-lock.json* ./
RUN npm ci

COPY tsconfig.json ./
COPY src/ ./src/
COPY scripts/ ./scripts/
RUN sed -i 's|\.\./src/|\.\./dist/|g' scripts/*.ts

RUN npm run build


FROM node:alpine AS runner

ARG VERSION=dev
LABEL org.opencontainers.image.version="${VERSION}"

WORKDIR /app

COPY package.json package-lock.json* ./
RUN npm ci --omit=dev && npm install tsx drizzle-kit

COPY --from=builder /app/dist ./dist
COPY --from=builder /app/scripts ./scripts
COPY drizzle.config.ts ./
COPY drizzle/ ./drizzle/
COPY entrypoint.sh ./
RUN chmod +x entrypoint.sh

EXPOSE 3000

CMD ["./entrypoint.sh"]
