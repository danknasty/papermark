# ── Stage 1: Install dependencies ──────────────────────────────
FROM node:22-alpine AS deps
RUN apk add --no-cache libc6-compat python3 make g++
WORKDIR /app

COPY package.json package-lock.json ./
COPY prisma ./prisma/
RUN npm install --legacy-peer-deps

# ── Stage 2: Build the application ───────────────────────────
FROM node:22-alpine AS builder
WORKDIR /app

COPY --from=deps /app/node_modules ./node_modules
COPY . .

# Inject standalone output for optimized Docker image
RUN sed -i 's/reactStrictMode: true/output: "standalone",\n  reactStrictMode: true/' next.config.mjs

# Generate Prisma client
RUN npx prisma generate

# NEXT_PUBLIC_* vars must be present at build time
ARG NEXT_PUBLIC_BASE_URL=""
ARG NEXT_PUBLIC_MARKETING_URL=""
ARG NEXT_PUBLIC_APP_BASE_HOST=""
ARG NEXT_PUBLIC_UPLOAD_TRANSPORT="s3"
ARG NEXT_PUBLIC_HANKO_TENANT_ID=""
ARG NEXT_PUBLIC_WEBHOOK_BASE_URL=""
ARG NEXT_PUBLIC_WEBHOOK_BASE_HOST=""
ARG NEXT_PRIVATE_UPLOAD_DISTRIBUTION_HOST=""

ENV NEXT_PUBLIC_BASE_URL=${NEXT_PUBLIC_BASE_URL} \
    NEXT_PUBLIC_MARKETING_URL=${NEXT_PUBLIC_MARKETING_URL} \
    NEXT_PUBLIC_APP_BASE_HOST=${NEXT_PUBLIC_APP_BASE_HOST} \
    NEXT_PUBLIC_UPLOAD_TRANSPORT=${NEXT_PUBLIC_UPLOAD_TRANSPORT} \
    NEXT_PUBLIC_HANKO_TENANT_ID=${NEXT_PUBLIC_HANKO_TENANT_ID} \
    NEXT_PUBLIC_WEBHOOK_BASE_URL=${NEXT_PUBLIC_WEBHOOK_BASE_URL} \
    NEXT_PUBLIC_WEBHOOK_BASE_HOST=${NEXT_PUBLIC_WEBHOOK_BASE_HOST} \
    NEXT_PRIVATE_UPLOAD_DISTRIBUTION_HOST=${NEXT_PRIVATE_UPLOAD_DISTRIBUTION_HOST}

RUN npm run build

# ── Stage 3: Production runtime ──────────────────────────────
FROM node:22-alpine AS runner
WORKDIR /app

ENV NODE_ENV=production \
    PORT=3000

RUN addgroup --system --gid 1001 nodejs && \
    adduser --system --uid 1001 nextjs

# Copy public assets
COPY --from=builder /app/public ./public

# Copy standalone server + static assets
COPY --from=builder --chown=nextjs:nodejs /app/.next/standalone ./
COPY --from=builder --chown=nextjs:nodejs /app/.next/static ./.next/static

# Copy Prisma runtime (needed for database queries)
COPY --from=builder /app/node_modules/.prisma ./node_modules/.prisma
COPY --from=builder /app/node_modules/@prisma ./node_modules/@prisma
COPY --from=builder /app/prisma ./prisma

USER nextjs
EXPOSE 3000

CMD ["node", "server.js"]
