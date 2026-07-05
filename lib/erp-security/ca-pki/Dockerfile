FROM alpine:3.20 AS builder
RUN apk add --no-cache git erlang elixir
WORKDIR /app
RUN git clone https://github.com/synrc/ca .
RUN mix local.hex --force && mix local.rebar --force
ENV MIX_ENV=prod
RUN mix deps.get && mix deps.compile && mix release
FROM alpine:3.20
RUN apk add --no-cache openssl libstdc++ ncurses-libs
WORKDIR /app
COPY --from=builder /app/_build/prod/rel/ca ./
ENV HOME=/app
ENV MIX_ENV=prod
EXPOSE 8047 8829 5318
CMD ["bin/ca", "start"]
