#!/usr/bin/env ruby
require 'yaml'

def clean_resource(doc)
  return nil if doc.nil?
  return doc unless doc.is_a?(Hash)

  if doc['kind'] == 'List' && doc['items'].is_a?(Array)
    doc['items'] = doc['items'].map { |item| clean_resource(item) }.compact
    return doc
  end

  # General metadata cleanup
  if doc['metadata']
    m = doc['metadata']
    m.delete('resourceVersion')
    m.delete('uid')
    m.delete('creationTimestamp')
    m.delete('generation')
    m.delete('selfLink')
    m.delete('managedFields')
    
    if m['annotations']
      a = m['annotations']
      a.delete('kubectl.kubernetes.io/last-applied-configuration')
      a.delete('pv.kubernetes.io/bind-completed')
      a.delete('pv.kubernetes.io/bound-by-controller')
      a.delete('volume.kubernetes.io/selected-node')
      a.delete('volume.kubernetes.io/storage-provisioner')
      a.delete('volume.beta.kubernetes.io/storage-provisioner')
      m.delete('annotations') if a.empty?
    end

    if doc['kind'] == 'PersistentVolumeClaim'
      m.delete('finalizers')
    end
  end

  doc.delete('status')

  if doc['kind'] == 'PersistentVolumeClaim' && doc['spec']
    doc['spec'].delete('volumeName')
  end

  doc
end

def clean_yaml(input_path, output_path)
  content = File.read(input_path)
  docs = YAML.load_stream(content)
  cleaned_docs = docs.map do |doc|
    next nil if doc.nil? || doc.empty?
    clean_resource(doc)
  end.compact

  File.open(output_path, 'w') do |f|
    cleaned_docs.each do |doc|
      f.write(YAML.dump(doc))
    end
  end
end

if __FILE__ == $0
  if ARGV.length < 2
    puts "Usage: #{$0} <input_path> <output_path>"
    exit 1
  end
  clean_yaml(ARGV[0], ARGV[1])
end
