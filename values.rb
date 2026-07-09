#!/usr/bin/env ruby
# values.rb - Generates helm/values.yaml from lib/ manifests
# Reads deployment.yaml for resource config; falls back to per-service values.yaml for image/port.
# For ERP services without explicit image, generates erpuno/{service}:{version}.

require 'yaml'
require 'fileutils'
require 'optparse'

options = { force: false, dry_run: false }
OptionParser.new do |opts|
  opts.on("-f", "--force",                    "Overwrite without confirmation") { options[:force]   = true }
  opts.on("-d", "--dry-run",                  "Print to stdout, do not write")  { options[:dry_run] = true }
  opts.on("-v", "--version VERSION", String,  "Set image version tag")           { |v| options[:version] = v }
end.parse!

REPO_ROOT           = Dir.pwd
LIB_DIR             = File.join(REPO_ROOT, 'lib')
HELM_VALUES_PATH    = File.join(REPO_ROOT, 'helm', 'values.yaml')

VERSION = options[:version] || ENV['VERSION'] || '2024.6.15'

GLOBAL = {
  'domain'          => 'erp.uno',
  'environment'     => 'production',
  'registry'        => 'docker.io',
  'imagePullPolicy' => 'IfNotPresent',
  'version'         => VERSION
}.freeze

# Known public images that should NOT get the erpuno/ prefix
PUBLIC_IMAGES = {
  'prometheus'      => "prom/prometheus:v2.53.0",
  'grafana'         => "grafana/grafana:11.1.0",
  'otel-collector'  => "otel/opentelemetry-collector-contrib:0.102.0",
  'docker-registry' => "registry:2.8.3",
  'ns-dns'          => "erpuno/ns:#{VERSION}",
  'ca-pki'          => "erpuno/ca:#{VERSION}",
  'ldap-directory'  => "erpuno/ldap:#{VERSION}",
}.freeze

# Parse image string → { registry_prefix, image_name, tag }
def parse_image(full_image)
  # e.g. "prom/prometheus:v2.53.0" → image="prom/prometheus", tag="v2.53.0"
  # e.g. "registry:2.8.3"          → image="registry",        tag="2.8.3"
  # e.g. "erpuno/health:2024.6.15" → image="erpuno/health",   tag="2024.6.15"
  parts  = full_image.split(':')
  tag    = parts.length > 1 ? parts.last : 'latest'
  image  = parts[0..-2].join(':').empty? ? parts[0] : parts[0..-2].join(':')
  { 'image' => image, 'tag' => tag }
end

def default_resources
  {
    'requests' => { 'cpu' => '100m', 'memory' => '256Mi' },
    'limits'   => { 'cpu' => '500m', 'memory' => '512Mi' }
  }
end

def extract_service_config(service_dir, service_name)
  config = {
    'enabled'  => true,
    'replicas' => 1,
    'resources' => default_resources,
  }

  # --- Step 1: Try per-service values.yaml for image/port overrides ---
  svc_values_path = File.join(service_dir, 'values.yaml')
  if File.exist?(svc_values_path)
    begin
      svc_vals = YAML.safe_load(File.read(svc_values_path)) || {}
      config['image'] = svc_vals['image'] if svc_vals['image']
      config['port']  = svc_vals['port']  if svc_vals['port']
    rescue => e
      warn "⚠️  Parse error #{svc_values_path}: #{e.message}"
    end
  end

  # --- Step 2: Parse deployment.yaml for authoritative spec ---
  deployment_path = File.join(service_dir, 'deployment.yaml')
  if File.exist?(deployment_path)
    begin
      dep       = YAML.safe_load(File.read(deployment_path)) || {}
      spec      = dep['spec'] || {}
      template  = spec.dig('template', 'spec') || {}
      container = template.dig('containers', 0) || {}

      config['replicas'] = spec['replicas'] if spec['replicas']

      # Full image field wins over values.yaml
      if container['image'] && !container['image'].empty?
        parsed = parse_image(container['image'])
        config['image'] = parsed['image']
        config['tag']   = parsed['tag']
      end

      # Ports
      if (ports = container['ports'])
        main = ports.first
        if main && main['containerPort']
          config['port']     = main['containerPort']
          config['protocol'] = main['protocol'] || 'TCP'
        end
      end

      # Resources
      if (resources = container['resources'])
        config['resources'] = {
          'requests' => resources['requests'] || default_resources['requests'],
          'limits'   => resources['limits']   || resources['requests'] || default_resources['limits']
        }
      end

      # Persistence (volumeMounts pointing to PVC, or volumeClaimTemplates)
      has_pvc = false
      pvc_mount_path = nil

      if spec['volumeClaimTemplates']
        has_pvc = true
        pvc_mount_path = '/data'
      elsif template['volumes'] && container['volumeMounts']
        pvc_vol_names = template['volumes']
          .select { |v| v['persistentVolumeClaim'] }
          .map { |v| v['name'] }
        matching_mount = container['volumeMounts'].find { |m| pvc_vol_names.include?(m['name']) }
        if matching_mount
          has_pvc = true
          pvc_mount_path = matching_mount['mountPath']
        end
      end

      if has_pvc
        config['persistence'] = {
          'enabled'        => true,
          'size'           => '10Gi',
          'storageClassName' => 'standard',
          'mountPath'      => pvc_mount_path || '/data'
        }
      end
    rescue => e
      warn "⚠️  Parse error #{deployment_path}: #{e.message}"
    end
  end

  # --- Step 3: HPA ---
  if File.exist?(File.join(service_dir, 'hpa.yaml'))
    config['hpa'] = {
      'enabled'              => true,
      'minReplicas'          => 2,
      'maxReplicas'          => 6,
      'targetCPUUtilization' => 75
    }
  end

  # --- Step 4: Fallback image from PUBLIC_IMAGES map ---
  unless config['image']
    if PUBLIC_IMAGES.key?(service_name)
      parsed = parse_image(PUBLIC_IMAGES[service_name])
      config['image'] = parsed['image']
      config['tag']   = parsed['tag']
    else
      # Generic ERP service fallback
      config['image'] = "erpuno/#{service_name}"
      config['tag']   = VERSION
    end
  end

  # Fallback port
  config['port'] ||= 8080

  config
end

def generate_values
  values = {
    'global'     => GLOBAL.dup,
    'namespaces' => {},
    'services'   => {}
  }

  Dir.glob(File.join(LIB_DIR, '*/')).sort.each do |ns_dir|
    ns_name = File.basename(ns_dir.chomp('/'))
    next unless ns_name.start_with?('erp-')

    values['namespaces'][ns_name] = {
      'enabled' => true,
      'tier' => case ns_name
                when /infra/     then 'infrastructure'
                when /telemetry/ then 'observability'
                when /security/  then 'security'
                when /ai/        then 'ai'
                else                  'application'
                end
    }

    values['services'][ns_name] = {}

    Dir.glob(File.join(ns_dir, '*/')).sort.each do |svc_dir|
      service_name = File.basename(svc_dir.chomp('/'))
      next if service_name.empty?

      config = extract_service_config(svc_dir, service_name)
      values['services'][ns_name][service_name] = config
    end
  end

  values['rbac']          = { 'create' => true }
  values['networkPolicy'] = { 'enabled' => true }
  values['ingress'] = {
    'enabled'   => true,
    'className' => 'nginx',
    'tls'       => { 'enabled' => false },
    'hosts'     => [
      {
        'host'  => GLOBAL['domain'],
        'paths' => [{ 'path' => '/', 'service' => 'nitro-portal', 'namespace' => 'erp-services', 'port' => 8510 }]
      }
    ]
  }

  values
end

puts "🔨 Generating helm/values.yaml  (version: #{VERSION})"

values = generate_values

if options[:dry_run]
  puts values.to_yaml(line_width: -1)
  exit 0
end

if File.exist?(HELM_VALUES_PATH) && !options[:force]
  print "Overwrite #{HELM_VALUES_PATH}? (y/N): "
  exit 1 unless STDIN.gets.strip.downcase == 'y'
end

FileUtils.mkdir_p(File.dirname(HELM_VALUES_PATH))
File.write(HELM_VALUES_PATH, values.to_yaml(line_width: -1))

puts "✅ Generated successfully!"
puts "   Namespaces : #{values['namespaces'].size}"
puts "   Services   : #{values['services'].values.sum(&:size)}"
