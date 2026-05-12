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
      end

      # Reset per-invocation state so a single instance can be safely reused
      # (e.g. `cli = CLI.new; cli.call(['-v']); cli.call(['x'])`).
      def call(argv)
        @output_path = @halt = nil
        @overwrite = false
        run(argv)
      rescue OptionParser::ParseError, JSON::JSONRepairError, SystemCallError, IOError,
             SystemStackError => e
        @stderr.puts "json-repair: #{e.message}"
        1
      end

      private

      def run(argv)
        positional = catch(:halt) { parser.parse(argv) }
        return @halt if @halt

        input_path = positional.first
        return 1 unless validate(positional, input_path)

        repaired = JSON.repair(read_input(input_path))
        write_output(repaired, input_path)
        0
      end

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
        raw = input_path ? File.read(input_path) : @stdin.read
        raw.force_encoding(Encoding::UTF_8)
        raise JSON::JSONRepairError, 'input is not valid UTF-8' unless raw.valid_encoding?

        raw
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
      # File.rename cannot overwrite an existing destination. The original
      # file's mode is preserved (Tempfile defaults to 0600).
      #
      # Symlinks are followed via File.realpath so the underlying file is
      # rewritten in place and the link is left pointing at it; otherwise
      # the rename would replace the link itself with a regular file.
      def replace_in_place(input_path, repaired)
        real_path = File.realpath(input_path)
        original_mode = File.stat(real_path).mode
        Tempfile.create(['json-repair', '.tmp'], File.dirname(real_path)) do |tmp|
          tmp.write(repaired)
          tmp.close
          File.chmod(original_mode, tmp.path)
          FileUtils.mv(tmp.path, real_path, force: true)
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

      OVERWRITE_DESC = 'Replace the input file in place (requires filename; conflicts with --output)'
      private_constant :OVERWRITE_DESC

      def define_options(opts)
        opts.on('-o', '--output FILE', 'Write repaired JSON to FILE') { |f| @output_path = f }
        opts.on('--overwrite', OVERWRITE_DESC) { @overwrite = true }
        opts.on('-v', '--version', 'Print version and exit') { halt_with(JSON::Repair::VERSION) }
        opts.on('-h', '--help', 'Print this help and exit') { halt_with(opts.help) }
      end

      # Print to stdout and short-circuit `parser.parse` so trailing args
      # after --version/--help do not raise OptionParser::ParseError and
      # flip the exit code (the option text promises "...and exit").
      def halt_with(message)
        @stdout.puts message
        @halt = 0
        throw :halt
      end
    end
  end
end
