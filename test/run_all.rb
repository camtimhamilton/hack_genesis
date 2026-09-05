#!/usr/bin/env ruby
# frozen_string_literal: true

# Единая команда запуска всех тестов без внешних gem (только stdlib minitest).
#
#   ruby test/run_all.rb
#
# Подхватывает все *_test.rb (unit) и *_spec.rb (spec) из test/.

$LOAD_PATH.unshift(File.expand_path('../src/lib', __dir__))
$LOAD_PATH.unshift(__dir__)

require 'minitest/autorun'

Dir[File.join(__dir__, 'unit', '*_test.rb')].sort.each { |f| require f }
Dir[File.join(__dir__, 'spec', '*_spec.rb')].sort.each { |f| require f }
