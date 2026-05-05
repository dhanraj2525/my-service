# ── Stage 1: Build ──────────────────────────────────
FROM node:20-alpine AS builder

WORKDIR /app

COPY package*.json ./
RUN npm ci --only=production

COPY src/ ./src/

# ── Stage 2: Production image ────────────────────────
FROM node:20-alpine AS production

# Non-root user for security
RUN addgroup -S appgroup && adduser -S appuser -G appgroup

WORKDIR /app

COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/src ./src
COPY package.json ./

# Build args → baked into image as labels
ARG COMMIT_HASH=unknown
ARG BUILD_NUMBER=unknown
ARG BRANCH=unknown

LABEL git.commit="${COMMIT_HASH}"
LABEL build.number="${BUILD_NUMBER}"
LABEL build.branch="${BRANCH}"

# Pass commit hash as env var (visible in /health endpoint)
ENV IMAGE_TAG=${COMMIT_HASH}

USER appuser

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD wget -qO- http://localhost:8080/health/live || exit 1

CMD ["node", "src/index.js"]