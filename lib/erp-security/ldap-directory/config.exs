import Config

config :ldap,
  port: 389,
  instance: "/app/db/ldap.db",
  module: LDAP,
  logger_level: :info,
  logger: [{:handler, :default, :logger_std_h, %{level: :info}}]
