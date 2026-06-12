# frozen_string_literal: true

require 'pathname'
require 'stringio'
require 'tempfile'

RSpec.describe JSON do
  describe '.repair' do
    it 'parses a valid JSON' do
      expect(JSON.repair('{"a":2.3e100,"b":"str","c":null,"d":false,"e":[1,2,3]}')).to \
        eq('{"a":2.3e+100,"b":"str","c":null,"d":false,"e":[1,2,3]}')
    end

    it 'collapses surrounding whitespace on the fast path' do
      expect(JSON.repair("  { \n } \t ")).to eq('{}')
    end

    it 'parses object' do
      expect(JSON.repair('{}')).to eq('{}')
      expect(JSON.repair('{  }')).to eq('{}')
      expect(JSON.repair('{"a": {}}')).to eq('{"a":{}}')
      expect(JSON.repair('{"a": "b"}')).to eq('{"a":"b"}')
      expect(JSON.repair('{"a": 2}')).to eq('{"a":2}')
    end

    it 'parses array' do
      expect(JSON.repair('[]')).to eq('[]')
      expect(JSON.repair('[  ]')).to eq('[]')
      expect(JSON.repair('[1,2,3]')).to eq('[1,2,3]')
      expect(JSON.repair('[ 1 , 2 , 3 ]')).to eq('[1,2,3]')
      expect(JSON.repair('[1,2,[3,4,5]]')).to eq('[1,2,[3,4,5]]')
      expect(JSON.repair('[{}]')).to eq('[{}]')
      expect(JSON.repair('{"a":[]}')).to eq('{"a":[]}')
      expect(JSON.repair('[1, "hi", true, false, null, {}, []]')).to eq('[1,"hi",true,false,null,{},[]]')
    end

    it 'parses number' do
      expect(JSON.repair('23')).to eq('23')
      expect(JSON.repair('0')).to eq('0')
      expect(JSON.repair('0e+2')).to eq('0.0')
      expect(JSON.repair('0.0')).to eq('0.0')
      expect(JSON.repair('-0')).to eq('0')
      expect(JSON.repair('2.3')).to eq('2.3')
      expect(JSON.repair('2300e3')).to eq('2300000.0')
      expect(JSON.repair('2300e+3')).to eq('2300000.0')
      expect(JSON.repair('2300e-3')).to eq('2.3')
      expect(JSON.repair('-2')).to eq('-2')
      expect(JSON.repair('2e-3')).to eq('0.002')
      expect(JSON.repair('2.3e-3')).to eq('0.0023')
    end

    it 'parses string' do
      expect(JSON.repair('"str"')).to eq('"str"')
      expect(JSON.repair('"\\"\\\\\\/\\b\\f\\n\\r\\t"')).to eq('"\"\\\\/\\b\\f\\n\\r\\t"')
      expect(JSON.repair('"\\u260E"')).to eq('"☎"')
    end

    it 'parses keywords' do
      expect(JSON.repair('true')).to eq('true')
      expect(JSON.repair('false')).to eq('false')
      expect(JSON.repair('null')).to eq('null')
    end

    it 'correctly handles strings equaling a JSON delimiter' do
      expect(JSON.repair('""')).to eq('""')
      expect(JSON.repair('"["')).to eq('"["')
      expect(JSON.repair('"]"')).to eq('"]"')
      expect(JSON.repair('"{"')).to eq('"{"')
      expect(JSON.repair('"}"')).to eq('"}"')
      expect(JSON.repair('":"')).to eq('":"')
      expect(JSON.repair('","')).to eq('","')
    end

    it 'supports unicode characters in a string' do
      expect(JSON.repair('"★"')).to eq('"★"')
      expect(JSON.repair('"\u2605"')).to eq('"★"')
      expect(JSON.repair('"😀"')).to eq('"😀"')
      expect(JSON.repair('"\ud83d\ude00"')).to eq('"😀"')
      expect(JSON.repair('"йнформация"')).to eq('"йнформация"')
    end

    it 'supports escaped unicode characters in a string' do
      expect(JSON.repair('"\u2605"')).to eq('"★"')
      expect(JSON.repair('"\u2605A"')).to eq('"★A"')
      expect(JSON.repair('"\ud83d\ude00"')).to eq('"😀"')
      expect(JSON.repair('"\u0439\u043d\u0444\u043e\u0440\u043c\u0430\u0446\u0438\u044f"')).to \
        eq('"йнформация"')
    end

    it 'supports unicode characters in a key' do
      expect(JSON.repair('{"★":true}')).to eq('{"★":true}')
      expect(JSON.repair('{"\u2605":true}')).to eq('{"★":true}')
      expect(JSON.repair('{"😀":true}')).to eq('{"😀":true}')
      expect(JSON.repair('{"\ud83d\ude00":true}')).to eq('{"😀":true}')
    end

    it 'leaves string content untouched' do
      expect(JSON.repair('"[1,2,3,]"')).to eq('"[1,2,3,]"')
      expect(JSON.repair('"{a:2,}"')).to eq('"{a:2,}"')
      expect(JSON.repair('"{a:b}"')).to eq('"{a:b}"')
      expect(JSON.repair('"/* comment */"')).to eq('"/* comment */"')
    end

    it 'does not add extra items to an array' do
      expect(JSON.repair("[\n{},\n{}\n]")).to eq('[{},{}]')
    end

    context 'when repairing invalid JSON' do
      it 'adds missing quotes' do
        expect(JSON.repair('abc')).to eq('"abc"')
        expect(JSON.repair('hello   world')).to eq('"hello   world"')
        expect(JSON.repair("{\nmessage: hello world\n}")).to eq('{"message":"hello world"}')
        expect(JSON.repair('{a:2}')).to eq('{"a":2}')
        expect(JSON.repair('{a: 2}')).to eq('{"a":2}')
        expect(JSON.repair('{2: 2}')).to eq('{"2":2}')
        expect(JSON.repair('{true: 2}')).to eq('{"true":2}')
        expect(JSON.repair("{\n  a: 2\n}")).to eq('{"a":2}')
        expect(JSON.repair('[a,b]')).to eq('["a","b"]')
        expect(JSON.repair("[\na,\nb\n]")).to eq('["a","b"]')
      end

      it 'adds missing end quote' do
        expect(JSON.repair('"abc')).to eq('"abc"')
        expect(JSON.repair("'abc")).to eq('"abc"')

        expect(JSON.repair('"12:20')).to eq('"12:20"')
        expect(JSON.repair('{"time":"12:20}')).to eq('{"time":"12:20"}')
        expect(JSON.repair('{"date":2024-10-18T18:35:22.229Z}')).to \
          eq('{"date":"2024-10-18T18:35:22.229Z"}')
        expect(JSON.repair('"She said:')).to eq('"She said:"')
        expect(JSON.repair('{"text": "She said:')).to eq('{"text":"She said:"}')
        expect(JSON.repair('["hello, world]')).to eq('["hello","world"]')
        expect(JSON.repair('["hello,"world"]')).to eq('["hello","world"]')

        expect(JSON.repair('{"a":"b}')).to eq('{"a":"b"}')
        expect(JSON.repair('{"a":"b,"c":"d"}')).to eq('{"a":"b","c":"d"}')
        expect(JSON.repair('{"a":"b,c,"d":"e"}')).to eq('{"a":"b,c","d":"e"}')
        expect(JSON.repair('{a:"b,c,"d":"e"}')).to eq('{"a":"b,c","d":"e"}')
        expect(JSON.repair('["b,c,]')).to eq('["b","c"]')

        expect(JSON.repair("\u2018abc")).to eq('"abc"')
        expect(JSON.repair('"it\'s working')).to eq("\"it's working\"")
        expect(JSON.repair('["abc+/*comment*/"def"]')).to eq('["abcdef"]')
        expect(JSON.repair('["abc/*comment*/+"def"]')).to eq('["abcdef"]')
        expect(JSON.repair('["abc,/*comment*/"def"]')).to eq('["abc","def"]')
      end

      it 'repairs an unquoted url' do
        expect(JSON.repair('https://www.bible.com/')).to eq('"https://www.bible.com/"')
        expect(JSON.repair('{url:https://www.bible.com/}')).to \
          eq('{"url":"https://www.bible.com/"}')
        expect(JSON.repair('{url:https://www.bible.com/,"id":2}')).to \
          eq('{"url":"https://www.bible.com/","id":2}')
        expect(JSON.repair('[https://www.bible.com/]')).to eq('["https://www.bible.com/"]')
        expect(JSON.repair('[https://www.bible.com/,2]')).to eq('["https://www.bible.com/",2]')
      end

      it 'repairs a url with missing end quote' do
        expect(JSON.repair('"https://www.bible.com/')).to eq('"https://www.bible.com/"')
        expect(JSON.repair('{"url":"https://www.bible.com/}')).to \
          eq('{"url":"https://www.bible.com/"}')
        expect(JSON.repair('{"url":"https://www.bible.com/,"id":2}')).to \
          eq('{"url":"https://www.bible.com/","id":2}')
        expect(JSON.repair('["https://www.bible.com/]')).to eq('["https://www.bible.com/"]')
        expect(JSON.repair('["https://www.bible.com/,2]')).to eq('["https://www.bible.com/",2]')
      end

      it 'repairs truncated JSON' do
        expect(JSON.repair('"foo')).to eq('"foo"')
        expect(JSON.repair('[')).to eq('[]')
        expect(JSON.repair('["foo')).to eq('["foo"]')
        expect(JSON.repair('["foo"')).to eq('["foo"]')
        expect(JSON.repair('["foo",')).to eq('["foo"]')
        expect(JSON.repair('{"foo":"bar')).to eq('{"foo":"bar"}')
        expect(JSON.repair('{"foo":"bar')).to eq('{"foo":"bar"}')
        expect(JSON.repair('{"foo":')).to eq('{"foo":null}')
        expect(JSON.repair('{"foo"')).to eq('{"foo":null}')
        expect(JSON.repair('{"foo')).to eq('{"foo":null}')
        expect(JSON.repair('{')).to eq('{}')
        expect(JSON.repair('2.')).to eq('2.0')
        expect(JSON.repair('2e')).to eq('2.0')
        expect(JSON.repair('2e+')).to eq('2.0')
        expect(JSON.repair('2e-')).to eq('2.0')
        expect(JSON.repair('{"foo":"bar\u20')).to eq('{"foo":"bar"}')
        expect(JSON.repair('"\\u')).to eq('""')
        expect(JSON.repair('"\\u2')).to eq('""')
        expect(JSON.repair('"\\u260')).to eq('""')
        expect(JSON.repair('"\\u2605')).to eq('"★"')
        expect(JSON.repair('{"s \\ud')).to eq('{"s":null}')
        expect(JSON.repair('{"message": "it\'s working')).to eq("{\"message\":\"it's working\"}")
        expect(JSON.repair('{"text":"Hello Sergey,I hop')).to eq('{"text":"Hello Sergey,I hop"}')
        expect(JSON.repair('{"message": "with, multiple, commma\'s, you see?')).to \
          eq("{\"message\":\"with, multiple, commma's, you see?\"}")
      end

      it 'repairs a string truncated at a lone backslash' do
        expect(JSON.repair('"abc\\')).to eq('"abc"')
        expect(JSON.repair('"\\')).to eq('""')
        expect(JSON.repair('["abc\\')).to eq('["abc"]')
        expect(JSON.repair('{"a": "b\\')).to eq('{"a":"b"}')
      end

      it 'repairs every prefix of a reference document into parseable JSON' do
        doc = <<~'JSON'
          {
            "id": 42,
            "name": "héllo — ☃",
            "esc": "quote:\" back:\\ nl:\n uni:\u2605",
            "nums": [-0.25, 1.5e-3, 1000],
            "nested": {
              "arr": [1, [2, {"deep": true}]],
              "ok": false,
              "nil": null
            }
          }
        JSON

        expect(JSON.parse(JSON.repair(doc))).to eq(JSON.parse(doc))

        (1..doc.length).each do |i|
          prefix = doc[0, i]
          expect { JSON.parse(JSON.repair(prefix)) }.not_to \
            raise_error, "failed at prefix length #{i}: #{prefix.inspect}"
        end
      end

      it 'repairs a string followed by a backslash-escaped delimiter' do
        expect(JSON.repair('["y"\\, "z"]')).to eq('["y\\"","z"]')
        expect(JSON.repair('"y"\\, "z"')).to eq('["y\\"","z"]')
        expect(JSON.repair('{"a": "y"\\, "b": "z"}')).to eq('{"a":"y\\"","b":"z"}')
      end

      it 'repairs ellipsis in an array' do
        expect(JSON.repair('[1,2,3,...]')).to eq('[1,2,3]')
        expect(JSON.repair('[1, 2, 3, ... ]')).to eq('[1,2,3]')
        expect(JSON.repair('[1,2,3,/*comment1*/.../*comment2*/]')).to eq('[1,2,3]')
        expect(JSON.repair("[\n  1,\n  2,\n  3,\n  /*comment1*/  .../*comment2*/\n]")).to \
          eq('[1,2,3]')
        expect(JSON.repair('{"array":[1,2,3,...]}')).to eq('{"array":[1,2,3]}')
        expect(JSON.repair('[1,2,3,...,9]')).to eq('[1,2,3,9]')
        expect(JSON.repair('[...,7,8,9]')).to eq('[7,8,9]')
        expect(JSON.repair('[..., 7,8,9]')).to eq('[7,8,9]')
        expect(JSON.repair('[...]')).to eq('[]')
        expect(JSON.repair('[ ... ]')).to eq('[]')
      end

      it 'repairs ellipsis in an object' do
        expect(JSON.repair('{"a":2,"b":3,...}')).to eq('{"a":2,"b":3}')
        expect(JSON.repair('{"a":2,"b":3,/*comment1*/.../*comment2*/}')).to eq('{"a":2,"b":3}')
        expect(JSON.repair("{\n  \"a\":2,\n  \"b\":3,\n  /*comment1*/.../*comment2*/\n}")).to \
          eq('{"a":2,"b":3}')
        expect(JSON.repair('{"a":2,"b":3, ... }')).to eq('{"a":2,"b":3}')
        expect(JSON.repair('{"nested":{"a":2,"b":3, ... }}')).to eq('{"nested":{"a":2,"b":3}}')
        expect(JSON.repair('{"a":2,"b":3,...,"z":26}')).to eq('{"a":2,"b":3,"z":26}')
        expect(JSON.repair('{"a":2,"b":3,...}')).to eq('{"a":2,"b":3}')
        expect(JSON.repair('{...}')).to eq('{}')
        expect(JSON.repair('{ ... }')).to eq('{}')
      end

      it 'adds missing start quote' do
        expect(JSON.repair('abc"')).to eq('"abc"')
        expect(JSON.repair('[a","b"]')).to eq('["a","b"]')
        expect(JSON.repair('[a",b"]')).to eq('["a","b"]')
        expect(JSON.repair('{"a":"foo","b":"bar"}')).to eq('{"a":"foo","b":"bar"}')
        expect(JSON.repair('{a":"foo","b":"bar"}')).to eq('{"a":"foo","b":"bar"}')
        expect(JSON.repair('{"a":"foo",b":"bar"}')).to eq('{"a":"foo","b":"bar"}')
        expect(JSON.repair('{"a":foo","b":"bar"}')).to eq('{"a":"foo","b":"bar"}')
      end

      it 'stops at the first next return when missing an end quote' do
        expect(JSON.repair("[\n\"abc,\n\"def\"\n]")).to eq('["abc","def"]')
        expect(JSON.repair("[\n\"abc,  \n\"def\"\n]")).to eq('["abc","def"]')
        expect(JSON.repair("[\"abc]\n")).to eq('["abc"]')
        expect(JSON.repair("[\"abc  ]\n")).to eq('["abc"]')
        expect(JSON.repair("[\n[\n\"abc\n]\n]\n")).to eq('[["abc"]]')
      end

      it 'replaces single quotes with double quotes' do
        expect(JSON.repair("{'a':2}")).to eq('{"a":2}')
        expect(JSON.repair("{'a':'foo'}")).to eq('{"a":"foo"}')
        expect(JSON.repair('{"a":\'foo\'}')).to eq('{"a":"foo"}')
        expect(JSON.repair("{a:'foo',b:'bar'}")).to eq('{"a":"foo","b":"bar"}')
      end

      it 'replaces special quotes with double quotes' do
        expect(JSON.repair('{“a”:“b”}')).to eq('{"a":"b"}')
        expect(JSON.repair('{‘a’:‘b’}')).to eq('{"a":"b"}')
        expect(JSON.repair('{`a´:`b´}')).to eq('{"a":"b"}')
      end

      it 'does not replace special quotes inside a normal string' do
        expect(JSON.repair('"Rounded “ quote"')).to eq('"Rounded “ quote"')
        expect(JSON.repair("'Rounded “ quote'")).to eq('"Rounded “ quote"')
        expect(JSON.repair('"Rounded ’ quote"')).to eq('"Rounded ’ quote"')
        expect(JSON.repair("'Rounded ’ quote'")).to eq('"Rounded ’ quote"')
        expect(JSON.repair("'Double \" quote'")).to eq('"Double \" quote"')
      end

      it 'does not crash when repairing quotes' do
        expect(JSON.repair("{pattern: '’'}")).to eq('{"pattern":"’"}')
      end

      it 'adds/remove escape characters' do
        expect(JSON.repair('"foo\'bar"')).to eq("\"foo'bar\"")
        expect(JSON.repair('"foo\\"bar"')).to eq('"foo\"bar"')
        expect(JSON.repair("'foo\"bar'")).to eq('"foo\"bar"')
        expect(JSON.repair("'foo\\'bar'")).to eq("\"foo'bar\"")
        expect(JSON.repair('"foo\\\'bar"')).to eq("\"foo'bar\"")
        expect(JSON.repair('"\\a"')).to eq('"a"')
      end

      it 'replaces backslash-escaped newline characters' do
        expect(JSON.repair("\"first\\\nsecond\"")).to eq('"first\\nsecond"')
      end

      it 'repairs a missing object value' do
        expect(JSON.repair('{"a":}')).to eq('{"a":null}')
        expect(JSON.repair('{"a":,"b":2}')).to eq('{"a":null,"b":2}')
        expect(JSON.repair('{"a":')).to eq('{"a":null}')
      end

      it 'repairs undefined values' do
        expect(JSON.repair('{"a":undefined}')).to eq('{"a":null}')
        expect(JSON.repair('[undefined]')).to eq('[null]')
        expect(JSON.repair('undefined')).to eq('null')
      end

      it 'escapes unescaped control characters' do
        expect(JSON.repair("\"hello\bworld\"")).to eq('"hello\\bworld"')
        expect(JSON.repair("\"hello\fworld\"")).to eq('"hello\\fworld"')
        expect(JSON.repair("\"hello\nworld\"")).to eq('"hello\\nworld"')
        expect(JSON.repair("\"hello\rworld\"")).to eq('"hello\\rworld"')
        expect(JSON.repair("\"hello\tworld\"")).to eq('"hello\\tworld"')
        expect(JSON.repair("{\"key\nafter\": \"foo\"}")).to eq('{"key\\nafter":"foo"}')

        expect(JSON.repair("[\"hello\nworld\"]")).to eq('["hello\\nworld"]')
        expect(JSON.repair("[\"hello\nworld\"  ]")).to eq('["hello\\nworld"]')
        expect(JSON.repair("[\"hello\nworld\"\n]")).to eq('["hello\\nworld"]')
      end

      it 'escapes unescaped double quotes' do
        expect(JSON.repair('"The TV has a 24" screen"')).to eq('"The TV has a 24\" screen"')
        expect(JSON.repair('{"key": "apple "bee" carrot"}')).to eq('{"key":"apple \"bee\" carrot"}')

        expect(JSON.repair('["a" 2]')).to eq('["a",2]')
        expect(JSON.repair('["a" 2')).to eq('["a",2]')
        expect(JSON.repair('["," 2')).to eq('[",",2]')
      end

      it 'replaces special white space characters' do
        expect(JSON.repair("{\"a\":\u00a0\"foo\u00a0bar\"}")).to eq('{"a":"foo bar"}')
        expect(JSON.repair("{\"a\":\u202F\"foo\"}")).to eq('{"a":"foo"}')
        expect(JSON.repair("{\"a\":\u205F\"foo\"}")).to eq('{"a":"foo"}')
        expect(JSON.repair("{\"a\":\u3000\"foo\"}")).to eq('{"a":"foo"}')
        expect(JSON.repair("{\"a\":\u180e\"foo\"}")).to eq('{"a":"foo"}')
        expect(JSON.repair("{\"a\":\u2000\"foo\"}")).to eq('{"a":"foo"}')
        expect(JSON.repair("{\"a\":\u2002\"foo\"}")).to eq('{"a":"foo"}')
        expect(JSON.repair("{\"a\":\u200b\"foo\"}")).to eq('{"a":"foo"}')
        expect(JSON.repair("{\"a\":\ufeff\"foo\"}")).to eq('{"a":"foo"}')
      end

      it 'replaces non normalized left/right quotes' do
        expect(JSON.repair("\u2018foo\u2019")).to eq('"foo"')
        expect(JSON.repair("\u201Cfoo\u201D")).to eq('"foo"')
        expect(JSON.repair("\u0060foo\u00B4")).to eq('"foo"')

        expect(JSON.repair("\u0060foo'")).to eq('"foo"')

        expect(JSON.repair("\u0060foo'")).to eq('"foo"')
      end

      it 'removes block comments' do
        expect(JSON.repair('/* foo */ {}')).to eq('{}')
        expect(JSON.repair('{} /* foo */ ')).to eq('{}')
        expect(JSON.repair('{} /* foo ')).to eq('{}')
        expect(JSON.repair("\n/* foo */\n{}")).to eq('{}')
        expect(JSON.repair('{"a":"foo",/*hello*/"b":"bar"}')).to eq('{"a":"foo","b":"bar"}')
        expect(JSON.repair('{"flag":/*boolean*/true}')).to eq('{"flag":true}')
      end

      it 'removes line comments' do
        expect(JSON.repair('{} // comment')).to eq('{}')
        expect(JSON.repair("{\n\"a\":\"foo\",//hello\n\"b\":\"bar\"\n}")).to \
          eq('{"a":"foo","b":"bar"}')
      end

      it 'keeps unquoted values starting with #' do
        # the hash-comment lookahead (see hash_comment?) must leave these
        # repairs untouched; Python's json_repair eats them as comments
        # and loses the data
        expect(JSON.repair('{"color": #ff0000}')).to eq('{"color":"#ff0000"}')
        expect(JSON.repair('{"tag": #hashtag}')).to eq('{"tag":"#hashtag"}')
        expect(JSON.repair('["#a", #b]')).to eq('["#a","#b"]')
        expect(JSON.repair('["#a", #b, "c"]')).to eq('["#a","#b","c"]')
        expect(JSON.repair('{#tag: 1}')).to eq('{"#tag":1}')
        expect(JSON.repair('#standalone')).to eq('"#standalone"')
        expect(JSON.repair('{"a": #tag')).to eq('{"a":"#tag"}')
      end

      it 'does not remove # inside a string' do
        expect(JSON.repair('"# not a comment"')).to eq('"# not a comment"')
        expect(JSON.repair('{"a": "x # y"')).to eq('{"a":"x # y"}')
      end

      it 'removes # line comments' do
        # divergence from upstream, which raises on # as of v3.14.0;
        # see the # branch in parse_comment
        expect(JSON.repair("{\"a\": 1 # comment\n}")).to eq('{"a":1}')
        expect(JSON.repair('{"a": 1 # comment}')).to eq('{"a":1}')
        expect(JSON.repair('[1, 2 # comment]')).to eq('[1,2]')
        expect(JSON.repair("[\"a\" # note\n, \"b\"]")).to eq('["a","b"]')
        expect(JSON.repair("{ # note\n \"a\": 1}")).to eq('{"a":1}')
        expect(JSON.repair("{ #TODO\n \"a\": 1}")).to eq('{"a":1}')
        expect(JSON.repair("{\"a\": 1, # b\n \"c\": 2}")).to eq('{"a":1,"c":2}')
        expect(JSON.repair("{\"a\": # note\n 1}")).to eq('{"a":1}')
        expect(JSON.repair("{\"a\" # c\n: 1}")).to eq('{"a":1}')
        expect(JSON.repair("# lead\n{\"a\": 1}")).to eq('{"a":1}')
        expect(JSON.repair("{ # a\n # b\n \"x\": 1}")).to eq('{"x":1}')
        expect(JSON.repair("{\"a\": 1}\n# trailing")).to eq('{"a":1}')
        expect(JSON.repair("{\"a\":1}\n{\"b\":2} # note")).to eq('[{"a":1},{"b":2}]')
        expect(JSON.repair("\"a\" + # note\n \"b\"")).to eq('"ab"')
        expect(JSON.repair("{\"a\":1}\n# note\n{\"b\":2}")).to eq('[{"a":1},{"b":2}]')
        expect(JSON.repair("{\"a\": 1 # c\r\n, \"b\": 2}")).to eq('{"a":1,"b":2}')
        expect(JSON.repair('{"a": 1 #')).to eq('{"a":1}')
        expect(JSON.repair('"a" + #note')).to eq('"a"')
      end

      it 'treats whitespace-bearing # tokens at value positions as comments' do
        # the flip side of the lookahead: once whitespace follows the #
        # before any structural delimiter, the token reads as comment
        # prose, even where a value is expected — a conscious tradeoff
        # (Python's json_repair drops these too), pinned so a future
        # change can't flip it silently
        expect(JSON.repair('{"a": #b c}')).to eq('{"a":null}')
        expect(JSON.repair("{\"a\": #tag\n}")).to eq('{"a":null}')
        expect { JSON.repair("# note\n") }.to \
          raise_error(JSON::JSONRepairError, 'Unexpected end of json string at index 7')
      end

      it 'does not remove comments inside a string' do
        expect(JSON.repair('"/* foo */"')).to eq('"/* foo */"')
      end

      it 'removes comments after a string containing a delimiter' do
        expect(JSON.repair('["a"/* foo */]')).to eq('["a"]')
        expect(JSON.repair('["(a)"/* foo */]')).to eq('["(a)"]')
        expect(JSON.repair('["a]"/* foo */]')).to eq('["a]"]')
        expect(JSON.repair('{"a":"b"/* foo */}')).to eq('{"a":"b"}')
        expect(JSON.repair('{"a":"(b)"/* foo */}')).to eq('{"a":"(b)"}')
      end

      it 'strips JSONP notation' do
        expect(JSON.repair('callback_123({});')).to eq('{}')
        expect(JSON.repair('callback_123([]);')).to eq('[]')
        expect(JSON.repair('callback_123(2);')).to eq('2')
        expect(JSON.repair('callback_123("foo");')).to eq('"foo"')
        expect(JSON.repair('callback_123(null);')).to eq('null')
        expect(JSON.repair('callback_123(true);')).to eq('true')
        expect(JSON.repair('callback_123(false);')).to eq('false')
        expect(JSON.repair('callback({}')).to eq('{}')
        expect(JSON.repair('/* foo bar */ callback_123 (  {}  )')).to eq('{}')
        expect(JSON.repair('  /* foo bar */   callback_123({});  ')).to eq('{}')
        expect(JSON.repair("\n/* foo\nbar */\ncallback_123 ({});\n\n")).to eq('{}')

        expect { JSON.repair('callback {}') }.to \
          raise_error(JSON::JSONRepairError, 'Unexpected character "{" at index 9')
      end

      it 'strips markdown fenced code blocks' do
        expect(JSON.repair("```\n{\"a\":\"b\"}\n```")).to eq('{"a":"b"}')
        expect(JSON.repair("```json\n{\"a\":\"b\"}\n```")).to eq('{"a":"b"}')
        expect(JSON.repair("```\n{\"a\":\"b\"}\n")).to eq('{"a":"b"}')
        expect(JSON.repair("\n{\"a\":\"b\"}\n```")).to eq('{"a":"b"}')
        expect(JSON.repair('```{"a":"b"}```')).to eq('{"a":"b"}')
        expect(JSON.repair("```\n[1,2,3]\n```")).to eq('[1,2,3]')
        expect(JSON.repair("```python\n{\"a\":\"b\"}\n```")).to eq('{"a":"b"}')
        expect(JSON.repair("\n ```json\n{\"a\":\"b\"}\n```\n  ")).to eq('{"a":"b"}')
      end

      it 'strips invalid markdown fenced code blocks' do
        expect(JSON.repair("[```\n{\"a\":\"b\"}\n```]")).to eq('{"a":"b"}')
        expect(JSON.repair("[```json\n{\"a\":\"b\"}\n```]")).to eq('{"a":"b"}')
        expect(JSON.repair("{```\n{\"a\":\"b\"}\n```}")).to eq('{"a":"b"}')
        expect(JSON.repair("{```json\n{\"a\":\"b\"}\n```}")).to eq('{"a":"b"}')
      end

      it 'repairs escaped string contents' do
        expect(JSON.repair('\\"hello world\\"')).to eq('"hello world"')
        expect(JSON.repair('\\"hello world\\')).to eq('"hello world"')
        expect(JSON.repair('\\"hello \\\\"world\\\\"\\')).to eq('"hello \"world\""')
        expect(JSON.repair('[\\"hello \\\\"world\\\\"\\"]')).to eq('["hello \"world\""]')
        expect(JSON.repair('{\\"stringified\\": \\"hello \\\\"world\\\\"\\"}')).to \
          eq('{"stringified":"hello \"world\""}')

        # TODO: Check this case
        # expect(JSON.repair('[\\"hello\\, \\"world\\"]')).to eq('["hello","world"]')
        expect(JSON.repair('\\"hello"')).to eq('"hello"')
      end

      it 'strips a leading comma from an array' do
        expect(JSON.repair('[,1,2,3]')).to eq('[1,2,3]')
        expect(JSON.repair('[/* a */,/* b */1,2,3]')).to eq('[1,2,3]')
        expect(JSON.repair('[, 1,2,3]')).to eq('[1,2,3]')
        expect(JSON.repair('[ , 1,2,3]')).to eq('[1,2,3]')
      end

      it 'strips a leading comma from an object' do
        expect(JSON.repair('{,"message": "hi"}')).to eq('{"message":"hi"}')
        expect(JSON.repair('{/* a */,/* b */"message": "hi"}')).to eq('{"message":"hi"}')
        expect(JSON.repair('{ ,"message": "hi"}')).to eq('{"message":"hi"}')
        expect(JSON.repair('{, "message": "hi"}')).to eq('{"message":"hi"}')
      end

      it 'strips trailing commas from an array' do
        expect(JSON.repair('[1,2,3,]')).to eq('[1,2,3]')
        expect(JSON.repair("[1,2,3,\n]")).to eq('[1,2,3]')
        expect(JSON.repair("[1,2,3,  \n  ]")).to eq('[1,2,3]')
        expect(JSON.repair('[1,2,3,/*foo*/]')).to eq('[1,2,3]')
        expect(JSON.repair('{"array":[1,2,3,]}')).to eq('{"array":[1,2,3]}')
      end

      it 'strips trailing commas from an object' do
        expect(JSON.repair('{"a":2,}')).to eq('{"a":2}')
        expect(JSON.repair('{"a":2  ,  }')).to eq('{"a":2}')
        expect(JSON.repair("{\"a\":2  , \n }")).to eq('{"a":2}')
        expect(JSON.repair('{"a":2/*foo*/,/*foo*/}')).to eq('{"a":2}')
        expect(JSON.repair('{},')).to eq('{}')
      end

      it 'strips trailing comma at the end' do
        expect(JSON.repair('4,')).to eq('4')
        expect(JSON.repair('4 ,')).to eq('4')
        expect(JSON.repair('4 , ')).to eq('4')
        expect(JSON.repair('{"a":2},')).to eq('{"a":2}')
        expect(JSON.repair('[1,2,3],')).to eq('[1,2,3]')
      end

      it 'adds a missing closing brace for an object' do
        expect(JSON.repair('{')).to eq('{}')
        expect(JSON.repair('{"a":2')).to eq('{"a":2}')
        expect(JSON.repair('{"a":2,')).to eq('{"a":2}')
        expect(JSON.repair('{"a":{"b":2}')).to eq('{"a":{"b":2}}')
        expect(JSON.repair("{\n  \"a\":{\"b\":2\n}")).to eq('{"a":{"b":2}}')
        expect(JSON.repair('[{"b":2]')).to eq('[{"b":2}]')
        expect(JSON.repair("[{\"b\":2\n]")).to eq('[{"b":2}]')
        expect(JSON.repair('[{"i":1{"i":2}]')).to eq('[{"i":1},{"i":2}]')
        expect(JSON.repair('[{"i":1,{"i":2}]')).to eq('[{"i":1},{"i":2}]')
      end

      it 'removes a redundant closing bracket for an object' do
        expect(JSON.repair('{"a": 1}}')).to eq('{"a":1}')
        expect(JSON.repair('{"a": 1}}]}')).to eq('{"a":1}')
        expect(JSON.repair('{"a": 1 }  }  ]  }  ')).to eq('{"a":1}')
        expect(JSON.repair('{"a":2]')).to eq('{"a":2}')
        expect(JSON.repair('{"a":2,]')).to eq('{"a":2}')
        expect(JSON.repair('{}}')).to eq('{}')
        expect(JSON.repair('[2,}')).to eq('[2]')
        expect(JSON.repair('[}')).to eq('[]')
        expect(JSON.repair('{]')).to eq('{}')
      end

      it 'adds a missing closing bracket for an array' do
        expect(JSON.repair('[')).to eq('[]')
        expect(JSON.repair('[1,2,3')).to eq('[1,2,3]')
        expect(JSON.repair('[1,2,3,')).to eq('[1,2,3]')
        expect(JSON.repair('[[1,2,3,')).to eq('[[1,2,3]]')
        expect(JSON.repair("{\n\"values\":[1,2,3\n}")).to eq('{"values":[1,2,3]}')
        expect(JSON.repair("{\n\"values\":[1,2,3\n")).to eq('{"values":[1,2,3]}')
      end

      it 'strips MongoDB data types' do
        # simple
        expect(JSON.repair('NumberLong("2")')).to eq('"2"')
        expect(JSON.repair('{"_id":ObjectId("123")}')).to eq('{"_id":"123"}')

        # extensive
        mongo_document = <<~MONGO_DOCUMENT
          {
              "_id" : ObjectId("123"),
              "isoDate" : ISODate("2012-12-19T06:01:17.171Z"),
              "regularNumber" : 67,
              "long" : NumberLong("2"),
              "long2" : NumberLong(2),
              "int" : NumberInt("3"),
              "int2" : NumberInt(3),
              "decimal" : NumberDecimal("4"),
              "decimal2" : NumberDecimal(4)
          }
        MONGO_DOCUMENT

        expected_json = '{"_id":"123","isoDate":"2012-12-19T06:01:17.171Z","regularNumber":67,' \
                        '"long":"2","long2":2,"int":"3","int2":3,"decimal":"4","decimal2":4}'

        expect(JSON.repair(mongo_document)).to eq(expected_json)
      end

      it 'parses an unquoted string' do
        expect(JSON.repair('hello world')).to eq('"hello world"')
        expect(JSON.repair('She said: no way')).to eq('"She said: no way"')
        expect(JSON.repair('["This is C(2)", "This is F(3)]')).to \
          eq('["This is C(2)","This is F(3)"]')
        expect(JSON.repair('["This is C(2)", This is F(3)]')).to \
          eq('["This is C(2)","This is F(3)"]')
      end

      it 'replaces Python constants None, True, False' do
        expect(JSON.repair('True')).to eq('true')
        expect(JSON.repair('False')).to eq('false')
        expect(JSON.repair('None')).to eq('null')
      end

      it 'replaces Ruby constant nil' do
        expect(JSON.repair('nil')).to eq('null')
      end

      it 'turns unknown symbols into a string' do
        expect(JSON.repair('foo')).to eq('"foo"')
        expect(JSON.repair('[1,foo,4]')).to eq('[1,"foo",4]')
        expect(JSON.repair('{foo: bar}')).to eq('{"foo":"bar"}')
        expect(JSON.repair('foo 2 bar')).to eq('"foo 2 bar"')
        expect(JSON.repair('{greeting: hello world}')).to \
          eq('{"greeting":"hello world"}')
        expect(JSON.repair("{greeting: hello world\nnext: \"line\"}")).to \
          eq('{"greeting":"hello world","next":"line"}')
        expect(JSON.repair('{greeting: hello world!}')).to \
          eq('{"greeting":"hello world!"}')
      end

      it 'treats a lone minus followed by a non-digit as an unquoted string' do
        expect(JSON.repair('-x')).to eq('"-x"')
        expect(JSON.repair('[-foo]')).to eq('["-foo"]')
      end

      it 'turns invalid numbers into strings' do
        expect(JSON.repair('ES2020')).to eq('"ES2020"')
        expect(JSON.repair('0.0.1')).to eq('"0.0.1"')
        expect(JSON.repair('746de9ad-d4ff-4c66-97d7-00a92ad46967')).to \
          eq('"746de9ad-d4ff-4c66-97d7-00a92ad46967"')
        expect(JSON.repair('234..5')).to eq('"234..5"')
        expect(JSON.repair('[0.0.1,2]')).to eq('["0.0.1",2]')
        expect(JSON.repair('[2 0.0.1 2]')).to eq('[2,"0.0.1 2"]')
        expect(JSON.repair('2e3.4')).to eq('"2e3.4"')
      end

      it 'repairs regular expressions' do
        expect(JSON.repair('{regex: /standalone-styles.css/}')).to \
          eq('{"regex":"/standalone-styles.css/"}')
        expect(JSON.repair('/[a-z]_/')).to eq('"/[a-z]_/"')

        # with escape char
        repaired_regex = JSON.repair('/\\//')
        expect(repaired_regex).to eq('"/\\\\//"')
      end

      it 'escapes quotes in repaired regular expressions' do
        # Prevent a string like:
        #     '/foo"; console.log(-1); "/'
        # from being parsed into:
        #     '"/foo"; console.log(-1); "/"'
        # which would be executed as JavaScript when this JSON is being parsed with `eval`.
        # See https://github.com/josdejong/jsonrepair/issues/150
        expect(JSON.repair('/foo"; console.log(-1); "/')).to \
          eq('"/foo\"; console.log(-1); \"/"')
      end

      it 'concatenates strings' do
        expect(JSON.repair('"hello" + " world"')).to eq('"hello world"')
        expect(JSON.repair("\"hello\" +\n \" world\"")).to eq('"hello world"')
        expect(JSON.repair('"a"+"b"+"c"')).to eq('"abc"')
        expect(JSON.repair('"hello" + /*comment*/ " world"')).to eq('"hello world"')
        expect(JSON.repair("{\n  \"greeting\": 'hello' +\n 'world'\n}")).to \
          eq('{"greeting":"helloworld"}')
        expect(JSON.repair("\"hello +\n \" world\"")).to eq('"hello world"')
        expect(JSON.repair('"hello +')).to eq('"hello"')
        expect(JSON.repair('["hello +]')).to eq('["hello"]')
      end

      it 'repairs missing comma between array items' do
        expect(JSON.repair('{"array": [{}{}]}')).to eq('{"array":[{},{}]}')
        expect(JSON.repair('{"array": [{} {}]}')).to eq('{"array":[{},{}]}')
        expect(JSON.repair("{\"array\": [{}\n{}]}")).to eq('{"array":[{},{}]}')
        expect(JSON.repair("{\"array\": [\n{}\n{}\n]}")).to eq('{"array":[{},{}]}')
        expect(JSON.repair("{\"array\": [\n1\n2\n]}")).to eq('{"array":[1,2]}')
        expect(JSON.repair("{\"array\": [\n\"a\"\n\"b\"\n]}")).to eq('{"array":["a","b"]}')
      end

      it 'repairs missing comma between object properties' do
        expect(JSON.repair("{\"a\":2\n\"b\":3\n}")).to eq('{"a":2,"b":3}')
        expect(JSON.repair("{\"a\":2\n\"b\":3\nc:4}")).to eq('{"a":2,"b":3,"c":4}')
        expect(JSON.repair("{\n  \"firstName\": \"John\"\n  lastName: Smith")).to \
          eq('{"firstName":"John","lastName":"Smith"}')
        expect(JSON.repair("{\n  \"firstName\": \"John\" /* comment */ \n  lastName: Smith")).to \
          eq('{"firstName":"John","lastName":"Smith"}')

        # verify parsing a comma after a return (since in parse_string we stop at a return)
        expect(JSON.repair("{\n  \"firstName\": \"John\"\n  ,  lastName: Smith")).to \
          eq('{"firstName":"John","lastName":"Smith"}')
      end

      it 'repairs numbers at the end' do
        expect(JSON.repair('{"a":2.')).to eq('{"a":2.0}')
        expect(JSON.repair('{"a":2e')).to eq('{"a":2.0}')
        expect(JSON.repair('{"a":2e-')).to eq('{"a":2.0}')
        expect(JSON.repair('{"a":-')).to eq('{"a":0}')
        expect(JSON.repair('[2e,')).to eq('[2.0]')
        expect(JSON.repair('[2e ')).to eq('[2.0]')
        expect(JSON.repair('[-,')).to eq('[0]')
      end

      it 'repairs missing colon between object key and value' do
        expect(JSON.repair('{"a" "b"}')).to eq('{"a":"b"}')
        expect(JSON.repair('{"a" 2}')).to eq('{"a":2}')
        expect(JSON.repair('{"a" true}')).to eq('{"a":true}')
        expect(JSON.repair('{"a" false}')).to eq('{"a":false}')
        expect(JSON.repair('{"a" null}')).to eq('{"a":null}')
        expect(JSON.repair('{"a"2}')).to eq('{"a":2}')
        expect(JSON.repair("{\n\"a\" \"b\"\n}")).to eq('{"a":"b"}')
        expect(JSON.repair('{"a" \'b\'}')).to eq('{"a":"b"}')
        expect(JSON.repair("{'a' 'b'}")).to eq('{"a":"b"}')
        expect(JSON.repair('{“a” “b”}')).to eq('{"a":"b"}')
        expect(JSON.repair("{a 'b'}")).to eq('{"a":"b"}')
        expect(JSON.repair('{a “b”}')).to eq('{"a":"b"}')
      end

      it 'repairs missing a combination of comma, quotes and brackets' do
        expect(JSON.repair("{\"array\": [\na\nb\n]}")).to eq('{"array":["a","b"]}')
        expect(JSON.repair("1\n2")).to eq('[1,2]')
        expect(JSON.repair("[a,b\nc]")).to eq('["a","b","c"]')
      end

      it 'repairs newline separated JSON (for example from MongoDB)' do
        text = "/* 1 */\n{}\n\n/* 2 */\n{}\n\n/* 3 */\n{}\n"

        expected = '[{},{},{}]'
        expect(JSON.repair(text)).to eq(expected)
      end

      it 'repairs newline separated JSON having commas' do
        text = "/* 1 */\n{},\n\n/* 2 */\n{},\n\n/* 3 */\n{}\n"

        expected = '[{},{},{}]'
        expect(JSON.repair(text)).to eq(expected)
      end

      it 'repairs newline separated JSON having commas and trailing comma' do
        text = "/* 1 */\n{},\n\n/* 2 */\n{},\n\n/* 3 */\n{},\n"

        expected = '[{},{},{}]'
        expect(JSON.repair(text)).to eq(expected)
      end

      it 'repairs a comma separated list with value' do
        expect(JSON.repair('1,2,3')).to eq('[1,2,3]')
        expect(JSON.repair('1,2,3,')).to eq('[1,2,3]')
        expect(JSON.repair("1\n2\n3")).to eq('[1,2,3]')
        expect(JSON.repair("a\nb")).to eq('["a","b"]')
      end

      it 'repairs a number with leading zero' do
        expect(JSON.repair('0789')).to eq('"0789"')
        expect(JSON.repair('000789')).to eq('"000789"')
        expect(JSON.repair('001.2')).to eq('"001.2"')
        expect(JSON.repair('002e3')).to eq('"002e3"')
        expect(JSON.repair('[0789]')).to eq('["0789"]')
        expect(JSON.repair('{value:0789}')).to eq('{"value":"0789"}')
      end

      it 'repairs a negative number with leading zero' do
        expect(JSON.repair('-05')).to eq('"-05"')
        expect(JSON.repair('-0789')).to eq('"-0789"')
        expect(JSON.repair('[-05]')).to eq('["-05"]')
        expect(JSON.repair('[-05e3]')).to eq('["-05e3"]')
        expect(JSON.repair('{"n": -05}')).to eq('{"n":"-05"}')
        # valid negative-zero numbers are untouched
        expect(JSON.repair('[-0]')).to eq('[0]')
        expect(JSON.repair('[-0.5]')).to eq('[-0.5]')
      end

      it 'repairs a truncated number with leading zero' do
        expect(JSON.repair('[05e]')).to eq('["05e0"]')
        expect(JSON.repair('00e')).to eq('"00e0"')
        expect(JSON.repair('00.')).to eq('"00.0"')
        expect(JSON.repair('[-05e]')).to eq('["-05e0"]')
        expect(JSON.repair('-00.')).to eq('"-00.0"')
        # a single leading zero stays numeric after padding
        expect(JSON.repair('[0e]')).to eq('[0.0]')
        expect(JSON.repair('[0.]')).to eq('[0.0]')
        expect(JSON.repair('[-0e]')).to eq('[-0.0]')
        expect(JSON.repair('[-0.]')).to eq('[-0.0]')
      end

      it 'repairs a number starting with a dot' do
        expect(JSON.repair('.5')).to eq('0.5')
        expect(JSON.repair('-.5')).to eq('-0.5')
        expect(JSON.repair('[.5, .25]')).to eq('[0.5,0.25]')
        expect(JSON.repair('{"a": .5}')).to eq('{"a":0.5}')
        expect(JSON.repair('.5e2')).to eq('50.0')
      end

      it 'repairs a number cut off after a leading dot' do
        expect(JSON.repair('.')).to eq('0.0')
        expect(JSON.repair('[-., 1]')).to eq('[-0.0,1]')
      end

      it 'repairs a stray e or E into an unquoted string' do
        expect(JSON.repair('[e]')).to eq('["e"]')
        expect(JSON.repair('[E]')).to eq('["E"]')
        expect(JSON.repair('[e5]')).to eq('["e5"]')
        expect(JSON.repair('[E5]')).to eq('["E5"]')
        expect(JSON.repair('e')).to eq('"e"')
        expect(JSON.repair('[e, 1]')).to eq('["e",1]')
        expect(JSON.repair('[e-]')).to eq('["e-"]')
        expect(JSON.repair('{"k": e}')).to eq('{"k":"e"}')
        expect(JSON.repair('[truee]')).to eq('[true,"e"]')
        expect(JSON.repair('["z"e]')).to eq('["z","e"]')
        # the concatenation path declines after the stray e, like [a+]
        expect { JSON.repair('[e+]') }.to \
          raise_error(JSON::JSONRepairError, 'Unexpected character "+" at index 2')
        # a real mantissa + e + non-digit/non-end also falls through to unquoted string
        expect(JSON.repair('[2ex]')).to eq('["2ex"]')
      end

      it 'repairs an object with an unquoted key and unclosed array value' do
        expect(JSON.repair('{foo: [}')).to eq('{"foo":[]}')
      end

      it 'repairs a truncated nested container without dropping the enclosing comma' do
        expect(JSON.repair('[{{]')).to eq('[{},{}]')
        expect(JSON.repair('["x",{{]')).to eq('["x",{},{}]')
        expect(JSON.repair('[{"a":1,{]')).to eq('[{"a":1},{}]')
        expect(JSON.repair('[1,[}]')).to eq('[1,[]]')
        expect(JSON.repair('[1,[}')).to eq('[1,[]]')
        expect(JSON.repair('{"a": 1, "b": [}')).to eq('{"a":1,"b":[]}')
        expect(JSON.repair('{"a": 1, "b": {]')).to eq('{"a":1,"b":{}}')
        # doubled braces at the root still raise (no enclosing comma to lose)
        expect { JSON.repair('{{') }.to \
          raise_error(JSON::JSONRepairError, 'Unexpected character "{" at index 1')
        expect { JSON.repair('{{}}') }.to \
          raise_error(JSON::JSONRepairError, 'Unexpected character "{" at index 1')
        expect { JSON.repair('{"a":{{') }.to \
          raise_error(JSON::JSONRepairError, 'Unexpected character "{" at index 6')
      end

      it 'repairs a value behind a Markdown list marker' do
        expect(JSON.repair('- { "k": 1 }')).to eq('{"k":1}')
        expect(JSON.repair('- [1, 2]')).to eq('[1,2]')
        expect(JSON.repair('- "text"')).to eq('"text"')
        expect(JSON.repair('- 5')).to eq('5')
        expect(JSON.repair('- true')).to eq('true')
        expect(JSON.repair('- -5')).to eq('-5')
        expect(JSON.repair('- item one')).to eq('"item one"')
        expect(JSON.repair('- .5')).to eq('0.5')
        # NBSP after the marker counts as same-line whitespace
        expect(JSON.repair("-\u00A0{\"a\": 1}")).to eq('{"a":1}')
      end

      it 'repairs a Markdown list marker after a leading comment' do
        expect(JSON.repair("/* c */\n- {\"a\": 1}")).to eq('{"a":1}')
        expect(JSON.repair("// note\n- 1\n- 2")).to eq('[1,2]')
      end

      it 'repairs a value behind an asterisk or plus Markdown list marker' do
        expect(JSON.repair('* {"a": 1}')).to eq('{"a":1}')
        expect(JSON.repair('* 5')).to eq('5')
        expect(JSON.repair('* item')).to eq('"item"')
        expect(JSON.repair('+ {"a": 1}')).to eq('{"a":1}')
      end

      it 'repairs a value behind an ordered Markdown list marker' do
        expect(JSON.repair('1. {"a": 1}')).to eq('{"a":1}')
        expect(JSON.repair('2) {"a": 1}')).to eq('{"a":1}')
        expect(JSON.repair('12. {"a": 1}')).to eq('{"a":1}')
        expect(JSON.repair('123456789. 5')).to eq('5')
      end

      it 'repairs a Markdown list marker inside a fenced code block' do
        expect(JSON.repair("```json\n- {\"a\": 1}\n```")).to eq('{"a":1}')
      end

      it 'does not mistake numbers or truncated input for Markdown list markers' do
        expect(JSON.repair('-5')).to eq('-5')
        expect(JSON.repair('- ')).to eq('0')
        expect(JSON.repair('* ')).to eq('"*"')
        expect { JSON.repair('+ ') }.to raise_error(JSON::JSONRepairError)
        expect(JSON.repair('1.')).to eq('1.0')
        expect(JSON.repair("-\n{\"a\": 1}")).to eq('[0,{"a":1}]')
        expect(JSON.repair('[- 1, 2]')).to eq('[0,1,2]')
        expect { JSON.repair('1234567890. 5') }.to raise_error(JSON::JSONRepairError)
        expect { JSON.repair('- - 5') }.to raise_error(JSON::JSONRepairError)
      end

      it 'repairs a multi-line Markdown list into an array' do
        expect(JSON.repair("- {\"a\": 1}\n- {\"b\": 2}")).to eq('[{"a":1},{"b":2}]')
        expect(JSON.repair("* {\"a\": 1}\n* {\"b\": 2}")).to eq('[{"a":1},{"b":2}]')
        expect(JSON.repair("1. {\"a\": 1}\n2. {\"b\": 2}")).to eq('[{"a":1},{"b":2}]')
        expect(JSON.repair("- item one\n- item two")).to eq('["item one","item two"]')
        expect(JSON.repair("1. first\n2. second")).to eq('["first","second"]')
        expect(JSON.repair("- {\"a\": 1},\n- {\"b\": 2}")).to eq('[{"a":1},{"b":2}]')
        expect(JSON.repair("1) {\"a\": 1}\n2) {\"b\": 2}")).to eq('[{"a":1},{"b":2}]')
        expect(JSON.repair("+ 1\n+ 2")).to eq('[1,2]')
        expect(JSON.repair("- .5\n- .25")).to eq('[0.5,0.25]')
      end

      it 'repairs newline delimited JSON with Markdown list markers on some lines' do
        expect(JSON.repair("{\"a\": 1}\n* {\"b\": 2}")).to eq('[{"a":1},{"b":2}]')
        expect(JSON.repair("3\n- 5\n7")).to eq('[3,5,7]')
        expect(JSON.repair("1\n- 2,\n- 3")).to eq('[1,2,3]')
      end

      it 'keeps newline delimited decimals and concatenated strings intact' do
        expect(JSON.repair("1.5\n2.5")).to eq('[1.5,2.5]')
        expect(JSON.repair("\"a\"\n+ \"b\"")).to eq('"ab"')
      end

      it 'repairs an object string value with unescaped quotes around a colon' do
        expect(JSON.repair('{"a": "b": "c"}')).to eq('{"a":"b\": \"c"}')
        expect(JSON.repair('{"a": "b":"c"}')).to eq('{"a":"b\":\"c"}')
        expect(JSON.repair('{"a": "b": "c", "d": "e"}')).to eq('{"a":"b\": \"c","d":"e"}')
        expect(JSON.repair('{"a": "b" : "c"}')).to eq('{"a":"b\" : \"c"}')
        expect(JSON.repair(%q({"a": 'b': 'c'}))).to eq(%q({"a":"b': 'c"}))
        expect(JSON.repair('[{"a": "b": "c"}]')).to eq('[{"a":"b\": \"c"}]')
        expect(JSON.repair('{"a": "b": "c"}', return_objects: true)).to eq({ 'a' => 'b": "c' })
        expect(JSON.repair('{"a": b": "c"}')).to eq('{"a":"b\": \"c"}')
      end

      it 'repairs repeated doubled colons greedily' do
        expect(JSON.repair('{"a": "b": "c": "d"}')).to eq('{"a":"b\": \"c\": \"d"}')
        expect(JSON.repair('{"a": "b": "c, x": "d"}')).to eq('{"a":"b\": \"c, x\": \"d"}')
      end

      it 'repairs a doubled colon in truncated or comma-less objects' do
        expect(JSON.repair('{"a": "b": "c"')).to eq('{"a":"b\": \"c"}')
        expect(JSON.repair('{"a": "b": "c" "d": "e"}')).to eq('{"a":"b\": \"c","d":"e"}')
      end

      it 'preserves the literal span when merging a doubled colon' do
        expect(JSON.repair(%({"a": "b"\n: "c"}))).to eq('{"a":"b\"\n: \"c"}')
        expect(JSON.repair('{"a": "b\"": "c"}')).to eq('{"a":"b\"\": \"c"}')
        expect(JSON.repair('{"a": "b\"": "c"}', return_objects: true)).to eq({ 'a' => 'b"": "c' })
        expect(JSON.repair('{"a": “b”: “c”}')).to eq('{"a":"b”: “c"}')
      end

      it 'repairs a doubled colon across special whitespace' do
        expect(JSON.repair("{\"a\": \"b\"\u00A0: \"c\"}")).to eq("{\"a\":\"b\\\"\u00A0: \\\"c\"}")
        expect(JSON.repair("{\"a\": \"b\":\u00A0\"c\"}")).to eq("{\"a\":\"b\\\":\u00A0\\\"c\"}")
        expect(JSON.repair('{"a": "b":　"c"}')).to eq('{"a":"b\":　\"c"}')
      end
    end

    context 'when the JSON cannot be repaired' do
      specify do
        expect { JSON.repair('') }.to \
          raise_error(JSON::JSONRepairError, 'Unexpected end of json string at index 0')
      end

      specify do
        expect { JSON.repair('{"a",') }.to \
          raise_error(JSON::JSONRepairError, 'Colon expected at index 4')
      end

      specify do
        expect { JSON.repair('{:2}') }.to \
          raise_error(JSON::JSONRepairError, 'Object key expected at index 1')
      end

      specify do
        expect { JSON.repair('{"a":2}{}') }.to \
          raise_error(JSON::JSONRepairError, 'Unexpected character "{" at index 7')
      end

      specify do
        expect { JSON.repair('{"a" ]') }.to \
          raise_error(JSON::JSONRepairError, 'Colon expected at index 5')
      end

      specify do
        expect { JSON.repair('{"a":2}foo') }.to \
          raise_error(JSON::JSONRepairError, 'Unexpected character "f" at index 7')
      end

      specify do
        expect { JSON.repair('foo [') }.to \
          raise_error(JSON::JSONRepairError, 'Unexpected character "[" at index 4')
      end

      specify do
        expect { JSON.repair('"\u26"') }.to \
          raise_error(JSON::JSONRepairError, 'Invalid unicode character "\\\\u26\"" at index 1')
      end

      specify do
        expect { JSON.repair('"\uZ000"') }.to \
          raise_error(JSON::JSONRepairError, 'Invalid unicode character "\\\\uZ000" at index 1')
      end

      specify do
        expect { JSON.repair("\"abc\u0000\"") }.to \
          raise_error(JSON::JSONRepairError, /\AInvalid character "\\u0000" at index 4\z/i)
      end

      specify do
        expect { JSON.repair("\"abc\u001F\"") }.to \
          raise_error(JSON::JSONRepairError, /\AInvalid character "\\u001f" at index 4\z/i)
      end

      # Guard branches in repair_doubled_colon: colon found, but the char
      # before it is not a quote (non-string value), or the char after the
      # colon is not a quote (non-string after colon).
      specify do
        expect { JSON.repair('{"a": 1: "c"}') }.to \
          raise_error(JSON::JSONRepairError, 'Object key expected at index 7')
      end

      specify do
        expect { JSON.repair('{"a": "b":1}') }.to \
          raise_error(JSON::JSONRepairError, 'Object key expected at index 9')
      end

      # doubled-colon guards: only the string-colon-string shape is
      # repaired (see repair_doubled_colon); these must keep raising
      specify do
        expect { JSON.repair('{"a": "b": 1}') }.to \
          raise_error(JSON::JSONRepairError, 'Object key expected at index 9')
      end

      specify do
        expect { JSON.repair('{"a": "b": true}') }.to \
          raise_error(JSON::JSONRepairError, 'Object key expected at index 9')
      end

      specify do
        expect { JSON.repair('{"a": 1: 2}') }.to \
          raise_error(JSON::JSONRepairError, 'Object key expected at index 7')
      end

      specify do
        expect { JSON.repair('{"a": {"x":"y"}: "c"}') }.to \
          raise_error(JSON::JSONRepairError, 'Object key expected at index 15')
      end

      specify do
        expect { JSON.repair('{"a": "b":}') }.to \
          raise_error(JSON::JSONRepairError, 'Object key expected at index 9')
      end

      specify do
        expect { JSON.repair('{"a": "b" /* note */ : "c"}') }.to \
          raise_error(JSON::JSONRepairError, 'Object key expected at index 21')
      end

      # doubled-colon guard: when the value string was itself salvaged by the
      # unescaped-quote repair (a stray word between two quoted strings glued
      # the spans together), merging across the following colon would compound
      # the damage into silent garbage — keep raising like upstream
      specify do
        expect { JSON.repair('{ "key": "value" COMMENT "key2": "value2" }') }.to \
          raise_error(JSON::JSONRepairError, 'Object key expected at index 31')
      end

      # the guard survives string concatenation: the salvaged first segment
      # keeps the flag set even though `+ "..."` segments re-enter parse_string
      specify do
        expect { JSON.repair('{"a": "b" x "c" + "d": "e"}') }.to \
          raise_error(JSON::JSONRepairError, 'Object key expected at index 21')
      end

      # stray junk word between object pairs: Go/Python json-repair silently
      # drop the word; upstream JS raises — we keep parity (see CHANGELOG.md,
      # 0.11.2)
      specify do
        expect { JSON.repair('{"value_1": true, COMMENT "value_2": "data"}') }.to \
          raise_error(JSON::JSONRepairError, 'Object key expected at index 35')
      end

      specify do
        expect { JSON.repair('{"a": b: "c"}') }.to \
          raise_error(JSON::JSONRepairError, 'Colon expected at index 12')
      end

      specify do
        # greedy merge engages, then bails at the non-string tail; the
        # raise discards all partial output
        expect { JSON.repair('{"x": "a": "b": 5}') }.to \
          raise_error(JSON::JSONRepairError, 'Object key expected at index 14')
      end

      describe '#position on the raised error' do
        def position_for(json)
          JSON.repair(json)
        rescue JSON::JSONRepairError => e
          e.position
        end

        it 'reports the index for unexpected-end (throw_unexpected_end)' do
          expect(position_for('')).to eq(0)
        end

        it 'reports the index for unexpected-character (throw_unexpected_character)' do
          expect(position_for('{"a":2}{}')).to eq(7)
        end

        it 'reports the index for object-key-expected (throw_object_key_expected)' do
          expect(position_for('{:2}')).to eq(1)
        end

        it 'reports the index for colon-expected (throw_colon_expected)' do
          expect(position_for('{"a" ]')).to eq(5)
        end

        it 'reports the index for invalid-unicode-character (throw_invalid_unicode_character)' do
          expect(position_for('"\u26"')).to eq(1)
        end

        it 'reports the index for invalid-character (throw_invalid_character)' do
          expect(position_for("\"abc\u001F\"")).to eq(4)
        end

        it 'is nil when JSONRepairError is constructed without a position' do
          expect(JSON::JSONRepairError.new('boom').position).to be_nil
        end

        it 'preserves the StandardError zero-arg construction contract' do
          expect { JSON::JSONRepairError.new }.not_to raise_error
          expect { raise JSON::JSONRepairError }.to raise_error(JSON::JSONRepairError)
        end

        it 'does not emit a malformed "at index N" message when message is nil' do
          err = JSON::JSONRepairError.new(nil, 5)
          expect(err.position).to eq(5)
          expect(err.message).to eq('JSON::JSONRepairError')
        end
      end
    end

    context 'when the repairer emits output stdlib cannot parse' do
      # No known input triggers this today; the stub stands in for a future
      # repairer bug so the JSONRepairError-only error contract holds even
      # if one slips in.
      it 'wraps the stdlib parser error in JSONRepairError' do
        repairer = instance_double(JSON::Repairer, repair: '{"a":')
        allow(JSON::Repairer).to receive(:new).and_return(repairer)

        expect { JSON.repair('{"a":') }.to raise_error(
          JSON::JSONRepairError, /repaired output is not valid JSON/
        )
      end
    end

    context 'with return_objects: true' do
      it 'returns a Hash for an object input' do
        expect(JSON.repair('{"a": 1}', return_objects: true)).to eq({ 'a' => 1 })
      end

      it 'returns an Array for an array input' do
        expect(JSON.repair('[1, 2, 3]', return_objects: true)).to eq([1, 2, 3])
      end

      it 'parses the repaired form, not the original broken input' do
        expect(JSON.repair("{a: 'b', c: [1, 2,]}", return_objects: true))
          .to eq({ 'a' => 'b', 'c' => [1, 2] })
      end

      it 'returns scalar values' do
        expect(JSON.repair('true', return_objects: true)).to be(true)
        expect(JSON.repair('null', return_objects: true)).to be_nil
        expect(JSON.repair('42', return_objects: true)).to eq(42)
        expect(JSON.repair('"hi"', return_objects: true)).to eq('hi')
        expect(JSON.repair('""', return_objects: true)).to eq('')
      end

      it 'handles deeply nested structures' do
        expect(JSON.repair('{"a":{"b":{"c":[1,2,[3,4]]}}}', return_objects: true))
          .to eq({ 'a' => { 'b' => { 'c' => [1, 2, [3, 4]] } } })
      end

      it 'composes with heavy repairs (markdown fence + unquoted keys + smart quotes)' do
        broken = "```json\n{name: “Alice”, age: 25}\n```"
        expect(JSON.repair(broken, return_objects: true))
          .to eq({ 'name' => 'Alice', 'age' => 25 })
      end

      it 'still raises JSONRepairError on unrecoverable input' do
        expect { JSON.repair('', return_objects: true) }.to \
          raise_error(JSON::JSONRepairError)
      end
    end

    context 'with return_objects: false (default)' do
      it 'returns the repaired string when omitted' do
        expect(JSON.repair('{a: 1}')).to eq('{"a":1}')
      end

      it 'returns the repaired string when explicitly false' do
        expect(JSON.repair('{a: 1}', return_objects: false)).to eq('{"a":1}')
      end
    end

    context 'with the stdlib JSON.parse fast path' do
      it 'returns canonical JSON for already-valid input without invoking the repairer' do
        expect(JSON::Repairer).not_to receive(:new)
        expect(JSON.repair('{"a": 1, "b": [2, 3]}')).to eq('{"a":1,"b":[2,3]}')
      end

      it 'collapses whitespace on the fast path' do
        expect(JSON::Repairer).not_to receive(:new)
        expect(JSON.repair("  { \"a\" : 1 } \t ")).to eq('{"a":1}')
      end

      it 'returns the parsed value on the fast path when return_objects: true' do
        expect(JSON::Repairer).not_to receive(:new)
        expect(JSON.repair('{"a": 1}', return_objects: true)).to eq({ 'a' => 1 })
      end

      it 'falls through to the repairer when stdlib JSON.parse raises' do
        expect(JSON.repair('{a: 1}')).to eq('{"a":1}')
      end

      it 'falls through for newline-delimited JSON at the root (stdlib rejects)' do
        expect(JSON.repair("{\"a\":1}\n{\"b\":2}")).to eq('[{"a":1},{"b":2}]')
      end

      it 'falls through for markdown-fenced JSON (stdlib rejects)' do
        expect(JSON.repair("```json\n{\"a\":1}\n```")).to eq('{"a":1}')
      end

      it 'falls through for empty input' do
        expect { JSON.repair('') }.to raise_error(JSON::JSONRepairError)
      end

      it 'collapses duplicate object keys to last-write-wins' do
        # The round-trip goes through a Ruby Hash, which only keeps one
        # value per key. Behavior is the same on the slow path because
        # the repaired string is itself parsed through Hash before being
        # re-serialized.
        expect(JSON.repair('{"a":1,"a":2,"b":3}')).to eq('{"a":2,"b":3}')
        expect(JSON.repair('{"a":1,"a":2,"b":3}', skip_json_loads: true)).to eq('{"a":2,"b":3}')
      end

      it 'forces the slow path when skip_json_loads: true' do
        # Negative number so the repairer's parse_number branch for the
        # digit-after-minus-sign path stays covered even though the fast
        # path would otherwise handle this input.
        input = '[-1, "a"]'
        expect(JSON::Repairer).to receive(:new).with(input).and_call_original
        expect(JSON.repair(input, skip_json_loads: true)).to eq('[-1,"a"]')
      end

      it 'uses the fast path when skip_json_loads: false (explicit default)' do
        expect(JSON::Repairer).not_to receive(:new)
        expect(JSON.repair('{"a": 1}', skip_json_loads: false)).to eq('{"a":1}')
      end

      it 'composes skip_json_loads: true with return_objects: true' do
        expect(JSON::Repairer).to receive(:new).and_call_original
        expect(JSON.repair('{"a": 1}', skip_json_loads: true, return_objects: true))
          .to eq({ 'a' => 1 })
      end
    end
  end

  describe '.repair_io' do
    it 'repairs JSON read from a StringIO' do
      io = StringIO.new('{a: 1, b: [2, 3,]}')
      expect(JSON.repair_io(io)).to eq('{"a":1,"b":[2,3]}')
    end

    it 'repairs JSON read from a File handle' do
      Tempfile.create(['broken', '.json']) do |tmp|
        tmp.write("```json\n{a: 1}\n```")
        tmp.rewind
        expect(JSON.repair_io(tmp)).to eq('{"a":1}')
      end
    end

    it 'forwards return_objects: to JSON.repair' do
      io = StringIO.new('{a: 1, b: [2, 3,]}')
      expect(JSON.repair_io(io, return_objects: true))
        .to eq({ 'a' => 1, 'b' => [2, 3] })
    end

    it 'forwards skip_json_loads: to JSON.repair' do
      io = StringIO.new('{"a": 1}')
      expect(JSON::Repairer).to receive(:new).and_call_original
      expect(JSON.repair_io(io, skip_json_loads: true)).to eq('{"a":1}')
    end

    it 'raises JSONRepairError for empty input' do
      expect { JSON.repair_io(StringIO.new('')) }.to \
        raise_error(JSON::JSONRepairError)
    end

    it 'treats a nil-returning #read the same as empty input' do
      io = Class.new { def read; end }.new
      expect { JSON.repair_io(io) }.to raise_error(JSON::JSONRepairError)
    end

    it 'does not close the IO' do
      io = StringIO.new('{"a": 1}')
      JSON.repair_io(io)
      expect(io.closed?).to be(false)
    end

    it 'consumes whatever the IO yields from #read (does not rewind)' do
      io = StringIO.new('{"a": 1}{"b": 2}')
      io.read(8)
      expect(JSON.repair_io(io)).to eq('{"b":2}')
    end
  end

  describe '.repair_file' do
    it 'repairs JSON read from a file path' do
      Tempfile.create(['broken', '.json']) do |tmp|
        tmp.write('{a: 1, b: [2, 3,]}')
        tmp.close
        expect(JSON.repair_file(tmp.path)).to eq('{"a":1,"b":[2,3]}')
      end
    end

    it 'forwards return_objects: to JSON.repair' do
      Tempfile.create(['broken', '.json']) do |tmp|
        tmp.write('{a: 1, b: [2, 3,]}')
        tmp.close
        expect(JSON.repair_file(tmp.path, return_objects: true))
          .to eq({ 'a' => 1, 'b' => [2, 3] })
      end
    end

    it 'forwards skip_json_loads: to JSON.repair' do
      Tempfile.create(['valid', '.json']) do |tmp|
        tmp.write('{"a": 1}')
        tmp.close
        expect(JSON::Repairer).to receive(:new).and_call_original
        expect(JSON.repair_file(tmp.path, skip_json_loads: true)).to eq('{"a":1}')
      end
    end

    it 'raises Errno::ENOENT for a missing file' do
      expect { JSON.repair_file('/nonexistent/path/does/not/exist.json') }.to \
        raise_error(Errno::ENOENT)
    end

    it 'accepts Pathname instances' do
      Tempfile.create(['broken', '.json']) do |tmp|
        tmp.write('{a: 1}')
        tmp.close
        expect(JSON.repair_file(Pathname.new(tmp.path))).to eq('{"a":1}')
      end
    end
  end
end
