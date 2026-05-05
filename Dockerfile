FROM node:20-alpine AS builder

WORKDIR /app

COPY package*.json ./

# npm install works without package-lock.json
# --omit=dev skips dev dependencies
RUN npm install --omit=dev

COPY src/ ./src/

FROM node:20-alpine AS production

RUN addgroup -S appgroup && adduser -S appuser -G appgroup

WORKDIR /app

COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/src ./src
COPY package.json ./

ARG COMMIT_HASH=unknown
ARG BUILD_NUMBER=unknown

LABEL git.commit="${COMMIT_HASH}"
LABEL build.number="${BUILD_NUMBER}"

ENV IMAGE_TAG=${COMMIT_HASH}

USER appuser

EXPOSE 8080

CMD ["node", "src/index.js"]