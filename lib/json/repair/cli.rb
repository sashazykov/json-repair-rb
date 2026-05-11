# frozen_string_literal: true

require 'fileutils'
require 'optparse'
require 'tempfile'
require_relative '../repair'

module JSON
  module Repair
    class CLI
      def self.call(argv, stdin: $stdin, stdout: $stdout, stderr: $stderr)
        new(stdin: stdin, stdout: stdout, stderr: stderr).call(argv)
      end

      def initialize(stdin: $stdin, stdout: $stdout, stderr: $stderr)
        @stdin = stdin
        @stdout = stdout
        @stderr = stderr
        @output_path = nil
        @overwrite = false
        @halt = nil
      end

      def call(argv)
        positional = parser.parse(argv)
        return @halt if @halt

        input_path = positional.first
        return 1 unless validate(positional, input_path)

        repaired = JSON.repair(read_input(input_path))
        write_output(repaired, input_path)
        0
      rescue OptionParser::ParseError, JSON::JSONRepairError, SystemCallError, IOError => e
        @stderr.puts "json-repair: #{e.message}"
        1
      end

      private

      def validate(positional, input_path)
        error = validation_error(positional, input_path)
        return true unless error

        @stderr.puts "json-repair: #{error}"
        false
      end

      def validation_error(positional, input_path)
        return "unexpected argument: #{positional[1]}" if positional.length > 1
        return '--overwrite requires a filename' if @overwrite && input_path.nil?
        return '--overwrite and --output are mutually exclusive' if @overwrite && @output_path

        nil
      end

      def read_input(input_path)
        input_path ? File.read(input_path) : @stdin.read
      end

      def write_output(repaired, input_path)
        if @overwrite
          replace_in_place(input_path, repaired)
        elsif @output_path
          File.write(@output_path, repaired)
        else
          @stdout.write(repaired)
          @stdout.write("\n") unless repaired.end_with?("\n")
        end
      end

      # Write to a uniquely-named tempfile alongside the input, then move it
      # over the original. Tempfile.create uses O_EXCL + a random suffix, so
      # the temp path is safe against symlink / clobber races; FileUtils.mv
      # with force: true handles cross-device renames and Windows, where
      # File.rename cannot overwrite an existing destination.
      def replace_in_place(input_path, repaired)
        Tempfile.create(['json-repair', '.tmp'], File.dirname(input_path)) do |tmp|
          tmp.write(repaired)
          tmp.close
          FileUtils.mv(tmp.path, input_path, force: true)
        end
      end

      def parser
        OptionParser.new do |opts|
          opts.banner = 'Usage: json-repair [filename] [options]'
          opts.separator ''
          opts.separator 'Repair a broken JSON document. Reads stdin when no filename is given.'
          opts.separator ''
          define_options(opts)
        end
      end

      def define_options(opts)
        opts.on('-o', '--output FILE', 'Write repaired JSON to FILE') { |f| @output_path = f }
        opts.on('--overwrite', 'Replace the input file in place (requires filename)') { @overwrite = true }
        opts.on('-v', '--version', 'Print version and exit') do
          @stdout.puts JSON::Repair::VERSION
          @halt = 0
        end
        opts.on('-h', '--help', 'Print this help and exit') do
          @stdout.puts opts.help
          @halt = 0
        end
      end
    end
  end
end
