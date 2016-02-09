# encoding: utf-8
# frozen_string_literal: true

require 'spec_helper'

describe RuboCop::Config do
  include FileHelper

  subject(:configuration) { described_class.new(hash, loaded_path) }
  let(:hash) { {} }
  let(:loaded_path) { 'example/.rubocop.yml' }

  describe '#validate', :isolated_environment do
    subject(:configuration) do
      RuboCop::ConfigLoader.load_file(configuration_path)
    end

    let(:configuration_path) { '.rubocop.yml' }

    context 'when the configuration includes any unrecognized cop name' do
      before do
        create_file(configuration_path, [
                      'LyneLenth:',
                      '  Enabled: true',
                      '  Max: 100'
                    ])
        $stderr = StringIO.new
      end

      after do
        $stderr = STDERR
      end

      it 'prints a warning message' do
        configuration # ConfigLoader.load_file will validate config
        expect($stderr.string).to match(/unrecognized cop LyneLenth/)
      end
    end

    context 'when the configuration includes an empty section' do
      before do
        create_file(configuration_path, ['Metrics/LineLength:'])
      end

      it 'raises validation error' do
        expect { configuration.validate }
          .to raise_error(RuboCop::ValidationError,
                          %r{^empty section Metrics/LineLength})
      end
    end

    context 'when the empty section is AllCops' do
      before do
        create_file(configuration_path, ['AllCops:'])
      end

      it 'raises validation error' do
        expect { configuration.validate }
          .to raise_error(RuboCop::ValidationError, /^empty section AllCops/)
      end
    end

    context 'when the configuration is in the base RuboCop config folder' do
      before do
        create_file(configuration_path, [
                      'InvalidProperty:',
                      '  Enabled: true'
                    ])
        stub_const('RuboCop::ConfigLoader::RUBOCOP_HOME', rubocop_home_path)
      end

      let(:rubocop_home_path) { File.realpath('.') }
      let(:configuration_path) { 'config/.rubocop.yml' }

      it 'is not validated' do
        expect { configuration.validate }.to_not raise_error
      end
    end

    context 'when the configuration includes any unrecognized parameter' do
      before do
        create_file(configuration_path, [
                      'Metrics/LineLength:',
                      '  Enabled: true',
                      '  Min: 10'
                    ])
        $stderr = StringIO.new
      end

      after do
        $stderr = STDERR
      end

      it 'prints a warning message' do
        configuration # ConfigLoader.load_file will validate config
        expect($stderr.string).to match(
          %r{unrecognized parameter Metrics/LineLength:Min})
      end
    end

    context 'when the configuration includes any common parameter' do
      # Common parameters are parameters that are not in the default
      # configuration, but are nonetheless allowed for any cop.
      before do
        create_file(configuration_path, [
                      'Metrics/ModuleLength:',
                      '  Exclude:',
                      '    - lib/file.rb',
                      '  Include:',
                      '    - lib/file.xyz',
                      '  Severity: warning',
                      '  StyleGuide: https://example.com/some-style.html'
                    ])
      end

      it 'does not raise validation error' do
        expect { configuration.validate }.to_not raise_error
      end
    end
  end

  describe '#make_excludes_absolute' do
    context 'when config is in root directory' do
      let(:hash) do
        {
          'AllCops' => {
            'Exclude' => [
              'config/environment',
              'spec'
            ]
          }
        }
      end

      before do
        allow(configuration)
          .to receive(:base_dir_for_path_parameters)
          .and_return('/home/foo/project')
        configuration.make_excludes_absolute
      end

      it 'should generate valid absolute directory' do
        excludes = configuration['AllCops']['Exclude']
                   .map { |e| e.sub(/^[A-Z]:/, '') }
        expect(excludes)
          .to eq [
            '/home/foo/project/config/environment',
            '/home/foo/project/spec'
          ]
      end
    end

    context 'when config is in subdirectory' do
      let(:hash) do
        {
          'AllCops' => {
            'Exclude' => [
              '../../config/environment',
              '../../spec'
            ]
          }
        }
      end

      before do
        allow(configuration)
          .to receive(:base_dir_for_path_parameters)
          .and_return('/home/foo/project/config/tools')
        configuration.make_excludes_absolute
      end

      it 'should generate valid absolute directory' do
        excludes = configuration['AllCops']['Exclude']
                   .map { |e| e.sub(/^[A-Z]:/, '') }
        expect(excludes)
          .to eq [
            '/home/foo/project/config/environment',
            '/home/foo/project/spec'
          ]
      end
    end
  end

  describe '#file_to_include?' do
    let(:hash) do
      {
        'AllCops' => {
          'Include' => ['**/Gemfile', 'config/unicorn.rb.example']
        }
      }
    end

    let(:loaded_path) { '/home/foo/project/.rubocop.yml' }

    context 'when the passed path matches any of patterns to include' do
      it 'returns true' do
        file_path = '/home/foo/project/Gemfile'
        expect(configuration.file_to_include?(file_path)).to be_truthy
      end
    end

    context 'when the passed path does not match any of patterns to include' do
      it 'returns false' do
        file_path = '/home/foo/project/Gemfile.lock'
        expect(configuration.file_to_include?(file_path)).to be_falsey
      end
    end
  end

  describe '#file_to_exclude?' do
    before { $stderr = StringIO.new }
    after { $stderr = STDERR }

    let(:hash) do
      {
        'AllCops' => {
          'Exclude' => [
            "#{Dir.pwd}/log/**/*",
            '**/bar.rb'
          ]
        }
      }
    end

    let(:loaded_path) { '/home/foo/project/.rubocop.yml' }

    context 'when the passed path matches any of patterns to exclude' do
      it 'returns true' do
        file_path = "#{Dir.pwd}/log/foo.rb"
        expect(configuration.file_to_exclude?(file_path)).to be_truthy

        expect(configuration.file_to_exclude?('log/foo.rb')).to be_truthy

        expect(configuration.file_to_exclude?('bar.rb')).to be_truthy
      end
    end

    context 'when the passed path does not match any of patterns to exclude' do
      it 'returns false' do
        file_path = "#{Dir.pwd}/log_file.rb"
        expect(configuration.file_to_exclude?(file_path)).to be_falsey

        expect(configuration.file_to_exclude?('app/controller.rb')).to be_falsey

        expect(configuration.file_to_exclude?('baz.rb')).to be_falsey
      end
    end
  end

  describe '#patterns_to_include' do
    subject(:patterns_to_include) do
      configuration = described_class.new(hash, loaded_path)
      configuration.patterns_to_include
    end

    let(:hash) { {} }
    let(:loaded_path) { 'example/.rubocop.yml' }

    context 'when config file has AllCops => Include key' do
      let(:hash) do
        {
          'AllCops' => {
            'Include' => ['**/Gemfile', 'config/unicorn.rb.example']
          }
        }
      end

      it 'returns the Include value' do
        expect(patterns_to_include).to eq([
                                            '**/Gemfile',
                                            'config/unicorn.rb.example'
                                          ])
      end
    end
  end

  describe '#patterns_to_exclude' do
    subject(:patterns_to_exclude) do
      configuration = described_class.new(hash, loaded_path)
      configuration.patterns_to_exclude
    end

    let(:hash) { {} }
    let(:loaded_path) { 'example/.rubocop.yml' }

    context 'when config file has AllCops => Exclude key' do
      let(:hash) do
        {
          'AllCops' => {
            'Exclude' => ['log/*']
          }
        }
      end

      it 'returns the Exclude value' do
        expect(patterns_to_exclude).to eq(['log/*'])
      end
    end
  end

  describe '#deprecation_check' do
    context 'when there is no AllCops configuration' do
      let(:hash) { {} }

      it 'does not yield' do
        expect { |b| configuration.deprecation_check(&b) }.not_to yield_control
      end
    end

    context 'when there is AllCops configuration' do
      context 'if there are no Excludes or Includes keys' do
        let(:hash) { { 'AllCops' => { 'Exclude' => [], 'Include' => [] } } }

        it 'does not yield' do
          expect do |b|
            configuration.deprecation_check(&b)
          end.not_to yield_control
        end
      end

      context 'if there are is an Includes key' do
        let(:hash) { { 'AllCops' => { 'Includes' => [] } } }

        it 'yields' do
          expect do |b|
            configuration.deprecation_check(&b)
          end.to yield_with_args(String)
        end
      end

      context 'if there are is an Excludes key' do
        let(:hash) { { 'AllCops' => { 'Excludes' => [] } } }

        it 'yields' do
          expect do |b|
            configuration.deprecation_check(&b)
          end.to yield_with_args(String)
        end
      end
    end
  end

  describe '#cop_enabled?' do
    context 'when an entire cop type is disabled' do
      context 'but an individual cop is enabled' do
        let(:hash) do
          {
            'Style' => { 'Enabled' => false },
            'Style/TrailingWhitespace' => { 'Enabled' => true }
          }
        end

        it 'still disables the cop' do
          cop_class = RuboCop::Cop::Style::TrailingWhitespace
          expect(configuration.cop_enabled?(cop_class)).to be false
        end
      end
    end

    context 'when an entire cop type is enabled' do
      context 'but an individual cop is disabled' do
        let(:hash) do
          {
            'Style' => { 'Enabled' => true },
            'Style/TrailingWhitespace' => { 'Enabled' => false }
          }
        end

        it 'still disables the cop' do
          cop_class = RuboCop::Cop::Style::TrailingWhitespace
          expect(configuration.cop_enabled?(cop_class)).to be false
        end
      end
    end
  end
end
