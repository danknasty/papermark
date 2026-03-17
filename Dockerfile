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

# ── Build-time env vars ──────────────────────────────────────
# NEXT_PUBLIC_* vars are inlined by Next.js at build time.
# DO App Platform injects RUN_AND_BUILD_TIME vars as Docker build args,
# overriding ARG defaults. Keep ARGs for NEXT_PUBLIC_* so the platform
# can supply real values.
ARG NEXT_PUBLIC_BASE_URL=""
ARG NEXT_PUBLIC_MARKETING_URL=""
ARG NEXT_PUBLIC_APP_BASE_HOST=""
ARG NEXT_PUBLIC_UPLOAD_TRANSPORT="s3"
ARG NEXT_PUBLIC_HANKO_TENANT_ID="placeholder"
ARG NEXT_PUBLIC_WEBHOOK_BASE_URL=""
ARG NEXT_PUBLIC_WEBHOOK_BASE_HOST=""
ARG NEXT_PUBLIC_POSTHOG_KEY=""
ARG NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY=""
ARG NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY_LIVE=""
ARG NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY_OLD=""
ARG NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY_LIVE_OLD=""

# All server-side env vars that are read at module level by SDK
# constructors or guard clauses. These placeholders exist ONLY to
# prevent throws during Next.js page-data collection. They never
# reach the production runtime image (separate FROM stage).
ENV NEXT_PUBLIC_BASE_URL=${NEXT_PUBLIC_BASE_URL} \
    NEXT_PUBLIC_MARKETING_URL=${NEXT_PUBLIC_MARKETING_URL} \
    NEXT_PUBLIC_APP_BASE_HOST=${NEXT_PUBLIC_APP_BASE_HOST} \
    NEXT_PUBLIC_UPLOAD_TRANSPORT=${NEXT_PUBLIC_UPLOAD_TRANSPORT} \
    NEXT_PUBLIC_HANKO_TENANT_ID=${NEXT_PUBLIC_HANKO_TENANT_ID} \
    NEXT_PUBLIC_WEBHOOK_BASE_URL=${NEXT_PUBLIC_WEBHOOK_BASE_URL} \
    NEXT_PUBLIC_WEBHOOK_BASE_HOST=${NEXT_PUBLIC_WEBHOOK_BASE_HOST} \
    NEXT_PUBLIC_POSTHOG_KEY=${NEXT_PUBLIC_POSTHOG_KEY} \
    NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY=${NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY} \
    NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY_LIVE=${NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY_LIVE} \
    NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY_OLD=${NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY_OLD} \
    NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY_LIVE_OLD=${NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY_LIVE_OLD} \
    NEXT_PRIVATE_UPLOAD_DISTRIBUTION_HOST=placeholder \
    NEXT_PRIVATE_UPLOAD_DISTRIBUTION_HOST_US=placeholder \
    NEXT_PRIVATE_DOCUMENT_PASSWORD_KEY=placeholder \
    NEXT_PRIVATE_VERIFICATION_SECRET=placeholder \
    NEXT_PRIVATE_UNSUBSCRIBE_JWT_SECRET=placeholder \
    NEXT_PRIVATE_SLACK_ENCRYPTION_KEY=placeholder \
    NEXT_PRIVATE_CONVERSION_BASE_URL=https://placeholder \
    NEXT_PRIVATE_CONVERT_API_KEY=placeholder \
    NEXT_PRIVATE_CONVERT_API_URL=https://placeholder \
    NEXT_PRIVATE_INTERNAL_AUTH_TOKEN=placeholder \
    NEXTAUTH_SECRET=placeholder \
    NEXTAUTH_URL=http://localhost:3000 \
    OPENAI_API_KEY=sk-placeholder-for-build \
    GOOGLE_VERTEX_API_KEY=placeholder \
    HANKO_API_KEY=placeholder \
    SLACK_CLIENT_ID=placeholder \
    SLACK_CLIENT_SECRET=placeholder \
    STRIPE_SECRET_KEY=sk_test_placeholder \
    STRIPE_SECRET_KEY_LIVE=sk_live_placeholder \
    STRIPE_SECRET_KEY_OLD=sk_test_placeholder \
    STRIPE_SECRET_KEY_LIVE_OLD=sk_live_placeholder \
    STRIPE_WEBHOOK_SECRET=whsec_placeholder \
    STRIPE_WEBHOOK_SECRET_OLD=whsec_placeholder \
    STRIPE_LIST_ID=placeholder \
    GOOGLE_CLIENT_ID=placeholder \
    GOOGLE_CLIENT_SECRET=placeholder \
    LINKEDIN_CLIENT_ID=placeholder \
    LINKEDIN_CLIENT_SECRET=placeholder \
    UPSTASH_REDIS_REST_URL=https://placeholder.upstash.io \
    UPSTASH_REDIS_REST_TOKEN=placeholder \
    UPSTASH_REDIS_REST_LOCKER_URL=https://placeholder.upstash.io \
    UPSTASH_REDIS_REST_LOCKER_TOKEN=placeholder \
    QSTASH_TOKEN=placeholder \
    QSTASH_CURRENT_SIGNING_KEY=placeholder \
    QSTASH_NEXT_SIGNING_KEY=placeholder \
    RESEND_API_KEY=re_placeholder \
    RESEND_MARKETING_SEGMENT_ID=placeholder \
    TINYBIRD_TOKEN=placeholder \
    DUB_API_KEY=placeholder \
    UNSEND_API_KEY=placeholder \
    UNSEND_BASE_URL=https://placeholder \
    UNSEND_CONTACT_BOOK_ID=placeholder \
    EDGE_CONFIG=https://placeholder \
    EDGE_CONFIG_ID=placeholder \
    INTERNAL_API_KEY=placeholder \
    AUTH_BEARER_TOKEN=placeholder \
    REVALIDATE_TOKEN=placeholder \
    JITSU_HOST=placeholder \
    JITSU_WRITE_KEY=placeholder \
    PPMK_SLACK_WEBHOOK_URL=https://placeholder \
    PPMK_STORE_WEBHOOK_URL=https://placeholder \
    PPMK_TRIAL_SLACK_WEBHOOK_URL=https://placeholder \
    POSTGRES_PRISMA_URL=postgresql://p:p@localhost:5432/p \
    POSTGRES_PRISMA_URL_NON_POOLING=postgresql://p:p@localhost:5432/p

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
