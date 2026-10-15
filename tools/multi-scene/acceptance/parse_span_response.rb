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
def parse_rows(text)
  check_keys(Psych.parse_stream(text))
  value = YAML.safe_load(text, permitted_classes: [Time, Date], aliases: false)
  abort("Expected a span row array") unless value.is_a?(Array)
  value
end

if ARGV.fetch(0) == "--batch-json"
  inputs = JSON.parse(ARGV.fetch(1))
  abort("Expected bounded string input batch") unless inputs.is_a?(Array) &&
    inputs.length.between?(1, 100) && inputs.all? { |input| input.is_a?(String) }
  puts JSON.generate(inputs.map { |input| parse_rows(input) })
else
  puts JSON.generate(parse_rows(ARGV.fetch(0)))
end
