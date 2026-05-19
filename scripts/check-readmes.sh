#!/usr/bin/env bash
set -euo pipefail

ruby <<'RUBY'
expected_files = [
  "README.md",
  "README.zh-CN.md",
  "README.zh-Hant.md",
  "README.hi.md",
  "README.ja.md",
  "README.ko.md",
  "README.de.md",
  "README.fr.md",
  "README.es.md",
  "README.pt-BR.md"
]

expected_nav = "[English](README.md) | [简体中文](README.zh-CN.md) | [繁體中文](README.zh-Hant.md) | [हिन्दी](README.hi.md) | [日本語](README.ja.md) | [한국어](README.ko.md) | [Deutsch](README.de.md) | [Français](README.fr.md) | [Español](README.es.md) | [Português (Brasil)](README.pt-BR.md)"

failures = []

def counts_for(values)
  counts = Hash.new(0)
  values.each { |value| counts[value] += 1 }
  counts
end

expected_files.each do |file|
  unless File.exist?(file)
    failures << "missing README: #{file}"
    next
  end

  lines = File.readlines(file, chomp: true, encoding: "UTF-8")
  nav = lines.find { |line| line.start_with?("[English](README.md)") }
  failures << "#{file}: missing language navigation" unless nav
  failures << "#{file}: language navigation differs from expected" if nav && nav != expected_nav

  links = nav.to_s.scan(/\[[^\]]+\]\((README[^)]*\.md)\)/).flatten
  missing_links = expected_files - links
  extra_links = links - expected_files
  duplicate_links = counts_for(links).select { |_, count| count > 1 }.keys

  failures << "#{file}: missing nav links: #{missing_links.join(", ")}" unless missing_links.empty?
  failures << "#{file}: unexpected nav links: #{extra_links.join(", ")}" unless extra_links.empty?
  failures << "#{file}: duplicate nav links: #{duplicate_links.join(", ")}" unless duplicate_links.empty?

  links.each do |linked_file|
    failures << "#{file}: broken nav link #{linked_file}" unless File.exist?(linked_file)
  end
end

if failures.empty?
  puts "README link check passed for #{expected_files.length} files."
else
  warn failures.join("\n")
  exit 1
end
RUBY
