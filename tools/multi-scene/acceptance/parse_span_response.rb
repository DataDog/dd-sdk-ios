# Parse only connector evidence with the system YAML parser; never load arbitrary objects.
require "yaml"
require "json"
require "date"


def check_keys(node)
  if node.is_a?(Psych::Nodes::Mapping)
    keys = node.children.each_slice(2).map do |key, _|
      abort("Non-scalar span mapping key") unless key.is_a?(Psych::Nodes::Scalar)
      key.value
    end
    abort("Duplicate span mapping key") unless keys.uniq.length == keys.length
  end
  (node.children || []).each { |child| check_keys(child) }
end
check_keys(Psych.parse_stream(ARGV.fetch(0)))

value = YAML.safe_load(ARGV.fetch(0), permitted_classes: [Time, Date], aliases: false)
abort("Expected a span row array") unless value.is_a?(Array)
puts JSON.generate(value)
