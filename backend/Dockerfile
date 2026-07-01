FROM golang:1.22-alpine AS builder

RUN apk add --no-cache git ca-certificates

WORKDIR /app

# Сначала копируем ВЕСЬ код — go mod tidy нужны исходники чтобы понять зависимости
COPY . .

# Теперь генерируем go.sum и скачиваем всё
RUN go mod tidy
RUN go mod download
RUN go mod verify

# Собираем бинарник
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o /messenger ./cmd/server

FROM alpine:3.19
RUN apk add --no-cache ca-certificates tzdata
COPY --from=builder /messenger /messenger

EXPOSE 8080
CMD ["/messenger"]
