#!/usr/bin/env ruby
# generate_values.rb - Fixed for missing ports + better defaults

require 'yaml'
require 'fileutils'
require 'optparse'

options = { force: false, dry_run: false }
OptionParser.new do |opts|
  opts.on("-f", "--force", "Overwrite without confirmation") { options[:force] = true }
  opts.on("-d", "--dry-run", "Dry run") { options[:dry_run] = true }
  opts.on("-v", "--version VERSION", "Set version") { |v| options[:version] = v }
end.parse!

REPO_ROOT = Dir.pwd
LIB_DIR = File.join(REPO_ROOT, 'lib')
HELM_VALUES_PATH = File.join(REPO_ROOT, 'helm', 'values.yaml')

GLOBAL = {
  'domain'          => 'erp.uno',
  'environment'     => 'production',
  'registry'        => 'docker.io',
  'imagePullPolicy' => 'IfNotPresent',
  'version'         => options[:version] || ENV['VERSION'] || '2024.6.15'
}.freeze

def default_resources
  {
    'requests' => { 'cpu' => '100m', 'memory' => '256Mi' },
    'limits'   => { 'cpu' => '500m', 'memory' => '512Mi' }
  }
end

def extract_service_config(service_dir)
  config = {
    'enabled'   => true,
    'replicas'  => 1,
    'resources' => default_resources,
    'port'      => 8080   # ← Default port as fallback
  }

  deployment_path = File.join(service_dir, 'deployment.yaml')
  return config unless File.exist?(deployment_path)

  begin
    dep = YAML.safe_load(File.read(deployment_path)) || {}
    spec = dep['spec'] || {}
    template = spec.dig('template', 'spec') || {}
    container = template.dig('containers', 0) || {}

    config['replicas'] = spec['replicas'] if spec['replicas']

    if container['image']
      config['image'] = container['image'].split('/').last.split(':').first
    end

    # Ports - critical fix
    if (ports = container['ports'])
      main = ports.first
      config['port'] = main['containerPort'] if main && main['containerPort']
      config['protocol'] = main['protocol'] || 'TCP'
    end

    # Resources
    if (resources = container['resources'])
      config['resources'] = {
        'requests' => resources['requests'] || default_resources['requests'],
        'limits'   => resources['limits']   || resources['requests'] || default_resources['limits']
      }
    end

    # Persistence
    if container.dig('volumeMounts') || spec.dig('volumeClaimTemplates')
      config['persistence'] = {
        'enabled' => true,
        'size' => '10Gi',
        'mountPath' => '/data'
      }
    end

    if File.exist?(File.join(service_dir, 'hpa.yaml'))
      config['hpa'] = { 'enabled' => true, 'minReplicas' => 2, 'maxReplicas' => 6, 'targetCPUUtilization' => 75 }
    end

  rescue => e
    warn "⚠️ Parse error #{deployment_path}: #{e.message}"
  end

  config
end

# ... rest of generate_values and main stays the same as previous version ...
def generate_values
  values = {
    'global' => GLOBAL.dup,
    'namespaces' => {},
    'services' => {}
  }

  Dir.glob(File.join(LIB_DIR, '*/')).sort.each do |ns_dir|
    ns_name = File.basename(ns_dir.chomp('/'))
    next unless ns_name.start_with?('erp-')

    values['namespaces'][ns_name] = {
      'enabled' => true,
      'tier' => case ns_name
                when /infra/ then 'infrastructure'
                when /telemetry/ then 'observability'
                when /security/ then 'security'
                when /ai/ then 'application'
                else 'application'
                end
    }

    values['services'][ns_name] = {}

    Dir.glob(File.join(ns_dir, '*/')).sort.each do |svc_dir|
      service_name = File.basename(svc_dir.chomp('/'))
      next if service_name.empty?

      config = extract_service_config(svc_dir)
      values['services'][ns_name][service_name] = config
    end
  end

  values['rbac'] = { 'create' => true }
  values['networkPolicy'] = { 'enabled' => true }

  values['ingress'] = {
    'enabled' => true,
    'className' => 'nginx',
    'tls' => { 'enabled' => false },
    'hosts' => [
      { 'host' => GLOBAL['domain'], 'paths' => [{ 'path' => '/', 'service' => 'nitro-portal', 'namespace' => 'erp-services', 'port' => 8510 }] }
    ]
  }

  values
end

puts "🔨 Generating helm/values.yaml..."

values = generate_values

if options[:dry_run]
  puts values.to_yaml(line_width: -1)
  exit 0
end

if File.exist?(HELM_VALUES_PATH) && !options[:force]
  print "Overwrite? (y/N): "
  exit 1 unless STDIN.gets.strip.downcase == 'y'
end

FileUtils.mkdir_p(File.dirname(HELM_VALUES_PATH))
File.write(HELM_VALUES_PATH, values.to_yaml(line_width: -1))

puts "✅ Generated successfully!"
puts "   Namespaces: #{values['namespaces'].size}"
puts "   Services: #{values['services'].values.sum(&:size)}"
