FROM node:20-alpine AS builder

WORKDIR /build

COPY package.json package-lock.json* ./
RUN npm ci

COPY . .

# Copy tesseract worker + WASM core + language data to public/ so Vite includes them in dist/
RUN mkdir -p public/tesseract/lang && \
    cp node_modules/tesseract.js/dist/worker.min.js public/tesseract/ && \
    cp node_modules/tesseract.js-core/tesseract-core-lstm.wasm.js public/tesseract/ && \
    cp node_modules/tesseract.js-core/tesseract-core-lstm.wasm public/tesseract/ && \
    cp public/tesseract/lang/*.gz public/tesseract/lang/ 2>/dev/null || true

RUN npm run build

FROM caddy:2-alpine

COPY --from=builder /build/dist /srv
COPY Caddyfile /etc/caddy/Caddyfile

EXPOSE 80

HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
    CMD wget -qO- http://localhost:80/ || exit 1
