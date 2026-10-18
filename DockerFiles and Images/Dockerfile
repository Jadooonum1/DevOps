# syntax=docker/dockerfile:1

############################
# Stage 1 - "build": full Go toolchain (~470 MB on disk). Nothing from here ships
# except the compiled binary.
############################
FROM golang:1.23-alpine AS build
WORKDIR /src

# dependency layer first for cache reuse (no external deps here, but the habit matters)
COPY go.mod ./
RUN go mod download

COPY main.go ./
# CGO off -> fully static binary that needs no libc in the final image
# -trimpath and -s -w strip local paths and debug symbols to shrink it
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" -o /out/catalog-api .

############################
# Stage 2 - "runtime": distroless static image, no shell, no package manager,
# runs as a non-root user by default.
############################
FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=build /out/catalog-api /catalog-api
EXPOSE 8080
USER nonroot:nonroot
ENTRYPOINT ["/catalog-api"]
