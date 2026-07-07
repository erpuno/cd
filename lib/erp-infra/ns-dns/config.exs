import Config

config :ns,
  servers: [[{:name, :inet_dns}, {:address, ~c"0.0.0.0"}, {:port, 53}, {:family, :inet}, {:processes, 2}]],
  dnssec: [{:enabled, false}],
  use_root_hints: false,
  catch_exceptions: false,
  zones: ~c"/synrc.zone.json",
  pools: [{:tcp_worker_pool, :erldns_worker, [{:size, 10},{:max_overflow, 20}]}],
  logger_level: :info,
  logger: [{:handler, :default, :logger_std_h, %{level: :info}}]
