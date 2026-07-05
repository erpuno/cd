#!/usr/bin/env ruby

def clean_yaml(input_path, output_path)
  lines = File.readlines(input_path)
  out_lines = []
  skip_until_indent = -1

  lines.each do |line|
    stripped = line.lstrip
    if stripped.empty?
      out_lines.push(line)
      next
    end
    indent = line.length - stripped.length

    # If in skip mode
    if skip_until_indent >= 0
      if indent > skip_until_indent
        next
      else
        skip_until_indent = -1
      end
    end

    # Check for block to skip (status or managedFields)
    if stripped.start_with?('status:') || stripped.start_with?('managedFields:')
      if ['status: {}', 'status: null', 'managedFields: []', 'managedFields: {}'].include?(stripped.strip)
        next
      else
        skip_until_indent = indent
        next
      end
    end

    # Check for metadata fields to skip
    if stripped =~ /^(resourceVersion|uid|creationTimestamp|generation|selfLink):\s/
      next
    end

    out_lines.push(line)
  end

  File.open(output_path, 'w') do |f|
    f.write(out_lines.join)
  end
end

if __FILE__ == $0
  if ARGV.length < 2
    puts "Usage: #{$0} <input_path> <output_path>"
    exit 1
  end
  clean_yaml(ARGV[0], ARGV[1])
end
