FROM golang:1.26-alpine AS builder

RUN apk add --no-cache git ca-certificates tzdata

WORKDIR /build

COPY go.mod go.sum ./
RUN go mod download

COPY . .

ARG VERSION=dev
ARG BUILD_TIME=unknown
ARG GIT_COMMIT=unknown

RUN CGO_ENABLED=0 GOOS=linux go build \
    -ldflags="-s -w -X main.Version=${VERSION} -X main.BuildTime=${BUILD_TIME} -X main.GitCommit=${GIT_COMMIT}" \
    -o /healthvault ./cmd/healthvault

FROM alpine:3.20

RUN apk add --no-cache ca-certificates tzdata \
    && addgroup -g 1000 -S healthvault \
    && adduser -u 1000 -S healthvault -G healthvault \
    && mkdir -p /data/keys /data/uploads \
    && chown -R healthvault:healthvault /data

COPY --from=builder /healthvault /usr/local/bin/healthvault

USER healthvault:healthvault

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD wget -qO- http://localhost:8080/health || exit 1

ENTRYPOINT ["healthvault"]
CMD ["serve"]
