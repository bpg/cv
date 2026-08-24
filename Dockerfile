FROM ghcr.io/gohugoio/hugo:v0.161.1@sha256:cef5b132b220dd5a661787d410124afe807b0ed3a79829604bdf0c3eefb85488 AS builder

WORKDIR /src

ENV HUGO_BASEURL=""

COPY config.yaml ./
COPY layouts/ ./layouts/
COPY assets/ ./assets/
COPY static/ ./static/
COPY data/ ./data/
COPY content/ ./content/

RUN --mount=type=cache,target=/tmp/hugo_cache \
	hugo --minify --gc --cacheDir /tmp/hugo_cache

# PDF generation and font optimization stage
FROM alpine:3.23@sha256:fd791d74b68913cbb027c6546007b3f0d3bc45125f797758156952bc2d6daf40 AS pdf-generator

# Chromium for PDF rendering, Python for font subsetting, libwebp for image conversion
RUN apk add --no-cache chromium busybox-extras py3-pip libwebp-tools && \
	pip install --break-system-packages --quiet fonttools brotli

WORKDIR /src

COPY --from=builder /src/public ./public
COPY --from=builder /src/assets/images/profile.jpg ./assets/
COPY data/data.yaml ./data/
COPY scripts/generate-pdf.sh scripts/subset-fonts.sh ./scripts/

RUN chmod +x ./scripts/generate-pdf.sh ./scripts/subset-fonts.sh && \
	cwebp -q 85 ./assets/profile.jpg -o ./public/profile.webp && \
	./scripts/generate-pdf.sh ./public ./data/data.yaml && \
	./scripts/subset-fonts.sh ./public/assets/fontawesome

# Get static-web-server binary
FROM joseluisq/static-web-server:2@sha256:2c1a7c3e0feaea5859307403b74e1c575f3ec1499094fc077344173d11abaae2 AS sws

# Final minimal image using distroless static (smaller, no glibc needed)
FROM gcr.io/distroless/static-debian12:nonroot@sha256:f5b485ea962d9bd1186b2f6b3a061191539b905b82ec395de78cbfae51f20e35

ARG GITHUB_REPOSITORY
LABEL org.opencontainers.image.title="CV Site"
LABEL org.opencontainers.image.description="Personal CV/Resume site built with Hugo and served with static-web-server"
LABEL org.opencontainers.image.source="https://github.com/${GITHUB_REPOSITORY:-unknown/unknown}"

COPY --from=sws /static-web-server /static-web-server
COPY static-web-server.toml /config.toml
COPY --from=pdf-generator /src/public /public

USER nonroot:nonroot

EXPOSE 8080

CMD ["/static-web-server", "--config-file", "/config.toml"]
