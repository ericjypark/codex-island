#!/usr/bin/env bash
set -euo pipefail

ruby <<'RUBY'
require "set"

locales = %w[en zh-Hans zh-Hant hi ja ko de fr es pt-BR]
root = Dir.pwd

def unescape_string(value)
  value.gsub(/\\(["\\])/, "\\1")
end

def counts_for(values)
  counts = Hash.new(0)
  values.each { |value| counts[value] += 1 }
  counts
end

def parse_strings(path)
  raw = File.read(path, encoding: "UTF-8")
  keys = []
  values = {}

  raw.scan(/^\s*"((?:\\.|[^"\\])*)"\s*=\s*"((?:\\.|[^"\\])*)";/) do |key, value|
    key = unescape_string(key)
    keys << key
    values[key] = unescape_string(value)
  end

  duplicates = counts_for(keys).select { |_, count| count > 1 }.keys
  [keys, values, duplicates]
end

def placeholders(value)
  found = []
  index = 0
  while index < value.length
    if value[index] == "%"
      if value[index + 1] == "%"
        index += 2
        next
      end

      match = value[index..].match(/\A%(?:\d+\$)?[-+ 0#]*(?:\*|\d+)?(?:\.(?:\*|\d+))?[hlLzjtq]*([@dDuUxXoOfeEgGcCsSpaAF])/)
      if match
        found << match[1]
        index += match[0].length
        next
      end
    end
    index += 1
  end
  found
end

def swift_string_literals(source, pattern)
  source.scan(pattern).flatten.map { |value| unescape_string(value) }
end

all_values = {}
failures = []

locales.each do |locale|
  path = File.join(root, "Resources", "#{locale}.lproj", "Localizable.strings")
  unless File.exist?(path)
    failures << "missing strings file: #{path}"
    next
  end

  keys, values, duplicates = parse_strings(path)
  failures << "#{locale}: duplicate keys: #{duplicates.sort.join(", ")}" unless duplicates.empty?
  all_values[locale] = values
end

base = all_values["en"] || {}
base_keys = base.keys.to_set

all_values.each do |locale, values|
  keys = values.keys.to_set
  missing = base_keys - keys
  extra = keys - base_keys

  failures << "#{locale}: missing keys: #{missing.to_a.sort.join(", ")}" unless missing.empty?
  failures << "#{locale}: extra keys: #{extra.to_a.sort.join(", ")}" unless extra.empty?

  (base_keys & keys).each do |key|
    expected = placeholders(base[key])
    actual = placeholders(values[key])
    failures << "#{locale}: placeholder mismatch for #{key.inspect}: #{actual.inspect} != #{expected.inspect}" if actual != expected
  end
end

swift_sources = Dir.glob(File.join(root, "Sources", "**", "*.swift")).map { |path| File.read(path, encoding: "UTF-8") }
static_keys = swift_sources.flat_map do |source|
  swift_string_literals(source, /L10n\.tr\(\s*"((?:\\.|[^"\\])*)"/)
end

settings_path = File.join(root, "Sources", "Views", "SettingsView.swift")
settings = File.read(settings_path, encoding: "UTF-8")
settings_variable_keys = []
settings_variable_keys.concat(swift_string_literals(settings, /sectionLabel\(\s*"((?:\\.|[^"\\])*)"/))
settings_variable_keys.concat(swift_string_literals(settings, /SettingsRow\(\s*title:\s*"((?:\\.|[^"\\])*)"/m))
settings_variable_keys.concat(swift_string_literals(settings, /subtitle:\s*(?:[A-Za-z0-9_.$()]+\s*\?\?\s*)?"((?:\\.|[^"\\])*)"/))
settings_variable_keys.concat(swift_string_literals(settings, /PillButton\(\s*label:\s*"((?:\\.|[^"\\])*)"/))
settings_variable_keys.concat(swift_string_literals(settings, /previewButton\(\s*"((?:\\.|[^"\\])*)"/))
settings_variable_keys.concat(swift_string_literals(settings, /accessibilityPrefix:\s*"((?:\\.|[^"\\])*)"/))
settings_variable_keys.concat(%w[General Display Providers Compact Notch-style])

required_keys = (static_keys + settings_variable_keys).uniq
ignored_keys = Set[
  "Claude",
  "Codex"
]
missing_required = required_keys.reject { |key| ignored_keys.include?(key) || base.key?(key) }
failures << "missing localized keys referenced from Swift: #{missing_required.sort.join(", ")}" unless missing_required.empty?

if failures.empty?
  puts "Localization check passed for #{locales.length} locales and #{base_keys.length} keys."
else
  warn failures.join("\n")
  exit 1
end
RUBY
