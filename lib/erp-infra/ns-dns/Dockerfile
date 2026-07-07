FROM alpine:3.20 AS builder
RUN apk add --no-cache git erlang elixir build-base
WORKDIR /app
RUN git clone https://github.com/synrc/ns.git .
COPY config.exs config/config.exs
COPY erp.zone.json priv/synrc.zone.json
RUN mix local.hex --force && mix local.rebar --force
ENV MIX_ENV=prod
RUN mix deps.get && mix deps.compile && mix release

FROM alpine:3.20
RUN apk add --no-cache openssl ncurses
WORKDIR /app
COPY --from=builder /app/_build/prod/rel/ns ./
ENV HOME=/app
ENV MIX_ENV=prod
EXPOSE 53/udp 53/tcp
CMD ["bin/ns", "start"]
