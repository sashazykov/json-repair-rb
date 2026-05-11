# frozen_string_literal: true

require 'json/repair/cli'
require 'stringio'
require 'tempfile'

RSpec.describe JSON::Repair::CLI do
  def run(argv, stdin: '')
    stdout = StringIO.new
    stderr = StringIO.new
    status = described_class.call(argv, stdin: StringIO.new(stdin), stdout: stdout, stderr: stderr)
    [status, stdout.string, stderr.string]
  end

  describe 'stdin → stdout' do
    it 'repairs JSON read from stdin' do
      status, out, err = run([], stdin: '{a:1,}')
      expect(status).to eq(0)
      expect(out).to eq("{\"a\":1}\n")
      expect(err).to eq('')
    end

    it 'returns non-zero with an error on stderr for unrepairable input' do
      status, out, err = run([], stdin: 'garbage,,')
      expect(status).to eq(1)
      expect(out).to eq('')
      expect(err).to match(/json-repair:.*at index/)
    end
  end

  describe 'file input' do
    it 'repairs JSON read from a file and writes to stdout' do
      Tempfile.create(['broken', '.json']) do |f|
        f.write('{a:1,}')
        f.close
        status, out, err = run([f.path])
        expect(status).to eq(0)
        expect(out).to eq("{\"a\":1}\n")
        expect(err).to eq('')
      end
    end

    it 'exits non-zero when the file is missing' do
      status, _out, err = run(['does-not-exist.json'])
      expect(status).to eq(1)
      expect(err).to match(/json-repair:.*No such file/)
    end
  end

  describe '--output' do
    it 'writes the repaired JSON to the given file without printing to stdout' do
      Tempfile.create(['broken', '.json']) do |input|
        input.write('{a:1,}')
        input.close
        Tempfile.create(['fixed', '.json']) do |output|
          output.close
          status, stdout_str, _err = run([input.path, '-o', output.path])
          expect(status).to eq(0)
          expect(stdout_str).to eq('')
          expect(File.read(output.path)).to eq('{"a":1}')
        end
      end
    end

    it 'exits non-zero with a message when the output path is not writable' do
      status, _out, err = run(['-o', '/nonexistent-dir/out.json'], stdin: '{a:1}')
      expect(status).to eq(1)
      expect(err).to include('json-repair:')
    end
  end

  describe '--overwrite' do
    it 'replaces the input file in place' do
      Tempfile.create(['broken', '.json']) do |f|
        f.write('{a:1,}')
        f.close
        status, _out, _err = run([f.path, '--overwrite'])
        expect(status).to eq(0)
        expect(File.read(f.path)).to eq('{"a":1}')
      end
    end

    it 'errors out without a filename' do
      status, _out, err = run(['--overwrite'])
      expect(status).to eq(1)
      expect(err).to include('--overwrite requires a filename')
    end

    it 'errors out when combined with --output' do
      Tempfile.create(['broken', '.json']) do |f|
        f.write('{a:1,}')
        f.close
        status, _out, err = run([f.path, '--overwrite', '-o', 'whatever.json'])
        expect(status).to eq(1)
        expect(err).to include('--overwrite and --output are mutually exclusive')
      end
    end
  end

  describe '--version' do
    it 'prints the version and exits 0' do
      status, out, _err = run(['--version'])
      expect(status).to eq(0)
      expect(out.strip).to eq(JSON::Repair::VERSION)
    end
  end

  describe '--help' do
    it 'prints usage and exits 0' do
      status, out, _err = run(['--help'])
      expect(status).to eq(0)
      expect(out).to include('Usage: json-repair')
      expect(out).to include('--output')
      expect(out).to include('--overwrite')
    end
  end

  describe 'unknown options' do
    it 'exits non-zero with a message' do
      status, _out, err = run(['--bogus'])
      expect(status).to eq(1)
      expect(err).to include('invalid option')
    end
  end
end
