FROM alpine:3.20 AS builder
RUN apk add --no-cache git erlang elixir build-base
ARG GIT_SOURCE=http://host.docker.internal:3000
WORKDIR /app
RUN git clone ${GIT_SOURCE}/synrc/ldap.git .
COPY config.exs config/config.exs
RUN mix local.hex --force && mix local.rebar --force
ENV MIX_ENV=prod
RUN mix deps.get && mix deps.compile && mix release

FROM alpine:3.20
RUN apk add --no-cache openssl ncurses libstdc++ libgcc
WORKDIR /app
COPY --from=builder /app/_build/prod/rel/ldap ./
ENV HOME=/app
ENV MIX_ENV=prod
EXPOSE 389
CMD ["bin/ldap", "start"]
