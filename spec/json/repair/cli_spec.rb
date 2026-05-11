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

    it 'returns non-zero on empty input' do
      status, out, err = run([], stdin: '')
      expect(status).to eq(1)
      expect(out).to eq('')
      expect(err).to include('json-repair:')
    end

    it 'does not append a second newline when the repaired output already ends with one' do
      status, out, _err = run([], stdin: "[1, 2, 3]\n")
      expect(status).to eq(0)
      expect(out).to eq("[1, 2, 3]\n")
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

    it 'preserves the original file mode' do
      Tempfile.create(['broken', '.json']) do |f|
        f.write('{a:1,}')
        f.close
        File.chmod(0o644, f.path)
        run([f.path, '--overwrite'])
        expect(File.stat(f.path).mode & 0o777).to eq(0o644)
      end
    end

    it 'leaves no temp files behind on a successful overwrite' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'broken.json')
        File.write(path, '{a:1,}')
        run([path, '--overwrite'])
        expect(Dir.children(dir)).to contain_exactly('broken.json')
      end
    end

    it 'cleans up the temp file when the repaired write fails to land' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'broken.json')
        File.write(path, '{a:1,}')
        allow(FileUtils).to receive(:mv).and_raise(Errno::EXDEV)
        status, _out, err = run([path, '--overwrite'])
        expect(status).to eq(1)
        expect(err).to include('json-repair:')
        expect(Dir.children(dir)).to contain_exactly('broken.json')
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

    it 'documents that --overwrite conflicts with --output' do
      _, out, = run(['--help'])
      expect(out).to match(/--overwrite[^\n]*conflicts with --output/)
    end
  end

  describe 'unknown options' do
    it 'exits non-zero with a message' do
      status, _out, err = run(['--bogus'])
      expect(status).to eq(1)
      expect(err).to include('invalid option')
    end

    it 'rejects --output with no argument' do
      status, _out, err = run(['-o'])
      expect(status).to eq(1)
      expect(err).to include('missing argument')
    end
  end

  describe 'argument validation' do
    it 'rejects more than one positional argument' do
      status, _out, err = run(['a.json', 'b.json'])
      expect(status).to eq(1)
      expect(err).to include('unexpected argument: b.json')
    end
  end

  describe 'instance reuse' do
    it 'resets option state between calls so prior --version/--help does not short-circuit' do
      stdout = StringIO.new
      stderr = StringIO.new
      cli = described_class.new(stdin: StringIO.new('{a:1,}'), stdout: stdout, stderr: stderr)

      first = cli.call(['--version'])
      expect(first).to eq(0)
      expect(stdout.string).to include(JSON::Repair::VERSION)

      stdout.truncate(0)
      stdout.rewind
      second = cli.call([])
      expect(second).to eq(0)
      expect(stdout.string).to eq("{\"a\":1}\n")
    end

    it 'does not carry --overwrite forward between calls on the same instance' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'broken.json')
        File.write(path, '{a:1,}')
        stderr = StringIO.new
        cli = described_class.new(stdin: StringIO.new('{b:2}'), stdout: StringIO.new, stderr: stderr)

        first = cli.call([path, '--overwrite'])
        expect(first).to eq(0)

        # Without reset, @overwrite would still be true on this second call and
        # the bare stdin invocation would fail with "--overwrite requires a filename".
        second = cli.call([])
        expect(second).to eq(0)
        expect(stderr.string).to eq('')
      end
    end
  end
end
