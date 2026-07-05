# Stage 1: Build the Erlang/Elixir release
FROM alpine:3.20 AS builder

# Install build dependencies, including Erlang and Elixir
RUN apk add --no-cache git erlang elixir

WORKDIR /app

# Clone the repository from GitHub
RUN git clone https://github.com/synrc/ca.git .

# Stub out the optional TPM module and remove the NIF compiler to avoid C library dependencies
RUN sed -i 's/compilers: \[:nif_make\] ++ Mix.compilers()/compilers: Mix.compilers()/' mix.exs && \
    echo -e 'defmodule CA.TPM do\n  def generate_key(_), do: {:error, :tpm_disabled}\n  def sign(_, _), do: {:error, :tpm_disabled}\n  def delete_key(_), do: {:error, :tpm_disabled}\nend' > lib/signing/tpm.ex

# Install hex and rebar
RUN mix local.hex --force && \
    mix local.rebar --force

ENV MIX_ENV=prod

# Fetch dependencies and release the application
RUN mix deps.get && \
    mix deps.compile && \
    mix release

# Stage 2: Runtime stage
FROM alpine:3.20

# Install minimal runtime dependencies needed by the BEAM VM
RUN apk add --no-cache openssl libstdc++ ncurses-libs

WORKDIR /app

# Copy release from builder
COPY --from=builder /app/_build/prod/rel/ca ./

ENV HOME=/app
ENV MIX_ENV=prod

# Expose ports (EST: 8047, CMP: 8829, CMC: 5318)
EXPOSE 8047 8829 5318

CMD ["bin/ca", "start"]
