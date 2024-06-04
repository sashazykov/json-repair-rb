# frozen_string_literal: true

RSpec.describe JSON do
  describe '.repair' do
    it 'parses a valid JSON' do
      expect(JSON.repair('{"a":2.3e100,"b":"str","c":null,"d":false,"e":[1,2,3]}')).to \
        eq('{"a":2.3e100,"b":"str","c":null,"d":false,"e":[1,2,3]}')
    end

    it 'parses whitespace' do
      expect(JSON.repair("  { \n } \t ")).to eq("  { \n } \t ")
    end

    it 'parses object' do
      expect(JSON.repair('{}')).to eq('{}')
      expect(JSON.repair('{  }')).to eq('{  }')
      expect(JSON.repair('{"a": {}}')).to eq('{"a": {}}')
      expect(JSON.repair('{"a": "b"}')).to eq('{"a": "b"}')
      expect(JSON.repair('{"a": 2}')).to eq('{"a": 2}')
    end

    it 'parses array' do
      expect(JSON.repair('[]')).to eq('[]')
      expect(JSON.repair('[  ]')).to eq('[  ]')
      expect(JSON.repair('[1,2,3]')).to eq('[1,2,3]')
      expect(JSON.repair('[ 1 , 2 , 3 ]')).to eq('[ 1 , 2 , 3 ]')
      expect(JSON.repair('[1,2,[3,4,5]]')).to eq('[1,2,[3,4,5]]')
      expect(JSON.repair('[{}]')).to eq('[{}]')
      expect(JSON.repair('{"a":[]}')).to eq('{"a":[]}')
      expect(JSON.repair('[1, "hi", true, false, null, {}, []]')).to eq('[1, "hi", true, false, null, {}, []]')
    end

    it 'parses number' do
      expect(JSON.repair('23')).to eq('23')
      expect(JSON.repair('0')).to eq('0')
      expect(JSON.repair('0e+2')).to eq('0e+2')
      expect(JSON.repair('0.0')).to eq('0.0')
      expect(JSON.repair('-0')).to eq('-0')
      expect(JSON.repair('2.3')).to eq('2.3')
      expect(JSON.repair('2300e3')).to eq('2300e3')
      expect(JSON.repair('2300e+3')).to eq('2300e+3')
      expect(JSON.repair('2300e-3')).to eq('2300e-3')
      expect(JSON.repair('-2')).to eq('-2')
      expect(JSON.repair('2e-3')).to eq('2e-3')
      expect(JSON.repair('2.3e-3')).to eq('2.3e-3')
    end

    it 'parses string' do
      expect(JSON.repair('"str"')).to eq('"str"')
      expect(JSON.repair('"\\"\\\\\\/\\b\\f\\n\\r\\t"')).to eq('"\\"\\\\\\/\\b\\f\\n\\r\\t"')
      expect(JSON.repair('"\\u260E"')).to eq('"\\u260E"')
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
      expect(JSON.repair('"\u2605"')).to eq('"\u2605"')
      expect(JSON.repair('"😀"')).to eq('"😀"')
      expect(JSON.repair('"\ud83d\ude00"')).to eq('"\ud83d\ude00"')
      expect(JSON.repair('"йнформация"')).to eq('"йнформация"')
    end

    it 'supports escaped unicode characters in a string' do
      expect(JSON.repair('"\u2605"')).to eq('"\u2605"')
      expect(JSON.repair('"\u2605A"')).to eq('"\u2605A"')
      expect(JSON.repair('"\ud83d\ude00"')).to eq('"\ud83d\ude00"')
      expect(JSON.repair('"\u0439\u043d\u0444\u043e\u0440\u043c\u0430\u0446\u0438\u044f"')).to \
        eq('"\u0439\u043d\u0444\u043e\u0440\u043c\u0430\u0446\u0438\u044f"')
    end

    it 'supports unicode characters in a key' do
      expect(JSON.repair('{"★":true}')).to eq('{"★":true}')
      expect(JSON.repair('{"\u2605":true}')).to eq('{"\u2605":true}')
      expect(JSON.repair('{"😀":true}')).to eq('{"😀":true}')
      expect(JSON.repair('{"\ud83d\ude00":true}')).to eq('{"\ud83d\ude00":true}')
    end

    it 'leaves string content untouched' do
      expect(JSON.repair('"[1,2,3,]"')).to eq('"[1,2,3,]"')
      expect(JSON.repair('"{a:2,}"')).to eq('"{a:2,}"')
      expect(JSON.repair('"{a:b}"')).to eq('"{a:b}"')
      expect(JSON.repair('"/* comment */"')).to eq('"/* comment */"')
    end

    it 'does not add extra items to an array' do
      expect(JSON.repair("[\n{},\n{}\n]")).to eq("[\n{},\n{}\n]")
    end

    context 'when repairing invalid JSON' do
      it 'adds missing quotes' do
        expect(JSON.repair('abc')).to eq('"abc"')
        expect(JSON.repair('hello   world')).to eq('"hello   world"')
        expect(JSON.repair("{\nmessage: hello world\n}")).to eq("{\n\"message\": \"hello world\"\n}")
        expect(JSON.repair('{a:2}')).to eq('{"a":2}')
        expect(JSON.repair('{a: 2}')).to eq('{"a": 2}')
        expect(JSON.repair('{2: 2}')).to eq('{"2": 2}')
        expect(JSON.repair('{true: 2}')).to eq('{"true": 2}')
        expect(JSON.repair("{\n  a: 2\n}")).to eq("{\n  \"a\": 2\n}")
        expect(JSON.repair('[a,b]')).to eq('["a","b"]')
        expect(JSON.repair("[\na,\nb\n]")).to eq("[\n\"a\",\n\"b\"\n]")
      end

      it 'adds missing end quote' do
        expect(JSON.repair('"abc')).to eq('"abc"')
        expect(JSON.repair("'abc")).to eq('"abc"')
        expect(JSON.repair("\u2018abc")).to eq('"abc"')
        expect(JSON.repair('"it\'s working')).to eq('"it\'s working"')
        expect(JSON.repair('["abc+/*comment*/"def"]')).to eq('["abcdef"]')
        expect(JSON.repair('["abc/*comment*/+"def"]')).to eq('["abcdef"]')
        expect(JSON.repair('["abc,/*comment*/"def"]')).to eq('["abc","def"]')
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
        expect(JSON.repair('2e')).to eq('2e0')
        expect(JSON.repair('2e+')).to eq('2e+0')
        expect(JSON.repair('2e-')).to eq('2e-0')
        expect(JSON.repair('{"foo":"bar\u20')).to eq('{"foo":"bar"}')
        expect(JSON.repair('"\\u')).to eq('""')
        expect(JSON.repair('"\\u2')).to eq('""')
        expect(JSON.repair('"\\u260')).to eq('""')
        expect(JSON.repair('"\\u2605')).to eq('"\\u2605"')
        expect(JSON.repair('{"s \\ud')).to eq('{"s": null}')
        expect(JSON.repair('{"message": "it\'s working')).to eq('{"message": "it\'s working"}')
        expect(JSON.repair('{"text":"Hello Sergey,I hop')).to eq('{"text":"Hello Sergey,I hop"}')
        expect(JSON.repair('{"message": "with, multiple, commma\'s, you see?')).to \
          eq('{"message": "with, multiple, commma\'s, you see?"}')
      end

      it 'repairs ellipsis in an array' do
        expect(JSON.repair('[1,2,3,...]')).to eq('[1,2,3]')
        expect(JSON.repair('[1, 2, 3, ... ]')).to eq('[1, 2, 3  ]')
        expect(JSON.repair('[1,2,3,/*comment1*/.../*comment2*/]')).to eq('[1,2,3]')
        expect(JSON.repair("[\n  1,\n  2,\n  3,\n  /*comment1*/  .../*comment2*/\n]")).to \
          eq("[\n  1,\n  2,\n  3\n    \n]")
        expect(JSON.repair('{"array":[1,2,3,...]}')).to eq('{"array":[1,2,3]}')
        expect(JSON.repair('[1,2,3,...,9]')).to eq('[1,2,3,9]')
        expect(JSON.repair('[...,7,8,9]')).to eq('[7,8,9]')
        expect(JSON.repair('[..., 7,8,9]')).to eq('[ 7,8,9]')
        expect(JSON.repair('[...]')).to eq('[]')
        expect(JSON.repair('[ ... ]')).to eq('[  ]')
      end

      it 'repairs ellipsis in an object' do
        expect(JSON.repair('{"a":2,"b":3,...}')).to eq('{"a":2,"b":3}')
        expect(JSON.repair('{"a":2,"b":3,/*comment1*/.../*comment2*/}')).to eq('{"a":2,"b":3}')
        expect(JSON.repair("{\n  \"a\":2,\n  \"b\":3,\n  /*comment1*/.../*comment2*/\n}")).to \
          eq("{\n  \"a\":2,\n  \"b\":3\n  \n}")
        expect(JSON.repair('{"a":2,"b":3, ... }')).to eq('{"a":2,"b":3  }')
        expect(JSON.repair('{"nested":{"a":2,"b":3, ... }}')).to eq('{"nested":{"a":2,"b":3  }}')
        expect(JSON.repair('{"a":2,"b":3,...,"z":26}')).to eq('{"a":2,"b":3,"z":26}')
        expect(JSON.repair('{"a":2,"b":3,...}')).to eq('{"a":2,"b":3}')
        expect(JSON.repair('{...}')).to eq('{}')
        expect(JSON.repair('{ ... }')).to eq('{  }')
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
        expect(JSON.repair("[\n\"abc,\n\"def\"\n]")).to eq("[\n\"abc\",\n\"def\"\n]")
        expect(JSON.repair("[\n\"abc,  \n\"def\"\n]")).to eq("[\n\"abc\",  \n\"def\"\n]")
        expect(JSON.repair("[\"abc]\n")).to eq("[\"abc\"]\n")
        expect(JSON.repair("[\"abc  ]\n")).to eq("[\"abc\"  ]\n")
        expect(JSON.repair("[\n[\n\"abc\n]\n]\n")).to eq("[\n[\n\"abc\"\n]\n]\n")
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
        expect(JSON.repair("'Double \" quote'")).to eq('"Double \\" quote"')
      end

      it 'does not crash when repairing quotes' do
        expect(JSON.repair("{pattern: '’'}")).to eq('{"pattern": "’"}')
      end

      it 'adds/remove escape characters' do
        expect(JSON.repair('"foo\'bar"')).to eq('"foo\'bar"')
        expect(JSON.repair('"foo\\"bar"')).to eq('"foo\\"bar"')
        expect(JSON.repair("'foo\"bar'")).to eq('"foo\\"bar"')
        expect(JSON.repair("'foo\\'bar'")).to eq('"foo\'bar"')
        expect(JSON.repair('"foo\\\'bar"')).to eq('"foo\'bar"')
        expect(JSON.repair('"\\a"')).to eq('"a"')
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
        expect(JSON.repair("\"hello\bworld\"")).to eq('"hello\bworld"')
        expect(JSON.repair("\"hello\fworld\"")).to eq('"hello\fworld"')
        expect(JSON.repair("\"hello\nworld\"")).to eq('"hello\nworld"')
        expect(JSON.repair("\"hello\rworld\"")).to eq('"hello\rworld"')
        expect(JSON.repair("\"hello\tworld\"")).to eq('"hello\tworld"')
        expect(JSON.repair("{\"key\nafter\": \"foo\"}")).to eq('{"key\nafter": "foo"}')

        expect(JSON.repair("[\"hello\nworld\"]")).to eq('["hello\nworld"]')
        expect(JSON.repair("[\"hello\nworld\"  ]")).to eq('["hello\nworld"  ]')
        expect(JSON.repair("[\"hello\nworld\"\n]")).to eq("[\"hello\\nworld\"\n]")
      end

      it 'escapes unescaped double quotes' do
        expect(JSON.repair('"The TV has a 24" screen"')).to eq('"The TV has a 24\\" screen"')
        expect(JSON.repair('{"key": "apple "bee" carrot"}')).to eq('{"key": "apple \\"bee\\" carrot"}')

        expect(JSON.repair('["a" 2]')).to eq('["a", 2]')
        expect(JSON.repair('["a" 2')).to eq('["a", 2]')
        expect(JSON.repair('["," 2')).to eq('[",", 2]')
      end

      it 'replaces special white space characters' do
        expect(JSON.repair("{\"a\":\u00a0\"foo\u00a0bar\"}")).to eq("{\"a\": \"foo\u00a0bar\"}")
        expect(JSON.repair("{\"a\":\u202F\"foo\"}")).to eq('{"a": "foo"}')
        expect(JSON.repair("{\"a\":\u205F\"foo\"}")).to eq('{"a": "foo"}')
        expect(JSON.repair("{\"a\":\u3000\"foo\"}")).to eq('{"a": "foo"}')
      end

      it 'replaces non normalized left/right quotes' do
        expect(JSON.repair("\u2018foo\u2019")).to eq('"foo"')
        expect(JSON.repair("\u201Cfoo\u201D")).to eq('"foo"')
        expect(JSON.repair("\u0060foo\u00B4")).to eq('"foo"')

        expect(JSON.repair("\u0060foo'")).to eq('"foo"')

        expect(JSON.repair("\u0060foo'")).to eq('"foo"')
      end

      it 'removes block comments' do
        expect(JSON.repair('/* foo */ {}')).to eq(' {}')
        expect(JSON.repair('{} /* foo */ ')).to eq('{}  ')
        expect(JSON.repair('{} /* foo ')).to eq('{} ')
        expect(JSON.repair("\n/* foo */\n{}")).to eq("\n\n{}")
        expect(JSON.repair('{"a":"foo",/*hello*/"b":"bar"}')).to eq('{"a":"foo","b":"bar"}')
        expect(JSON.repair('{"flag":/*boolean*/true}')).to eq('{"flag":true}')
      end

      it 'removes line comments' do
        expect(JSON.repair('{} // comment')).to eq('{} ')
        expect(JSON.repair("{\n\"a\":\"foo\",//hello\n\"b\":\"bar\"\n}")).to \
          eq("{\n\"a\":\"foo\",\n\"b\":\"bar\"\n}")
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
        expect(JSON.repair('/* foo bar */ callback_123 (  {}  )')).to eq('   {}  ')
        expect(JSON.repair('  /* foo bar */   callback_123({});  ')).to eq('     {}  ')
        expect(JSON.repair("\n/* foo\nbar */\ncallback_123 ({});\n\n")).to eq("\n\n{}\n\n")

        expect { JSON.repair('callback {}') }.to \
          raise_error(JSON::JSONRepairError, 'Unexpected character "{" at index 9')
      end

      it 'repairs escaped string contents' do
        expect(JSON.repair('\\"hello world\\"')).to eq('"hello world"')
        expect(JSON.repair('\\"hello world\\')).to eq('"hello world"')
        expect(JSON.repair('\\"hello \\\\"world\\\\"\\')).to eq('"hello \\"world\\""')
        expect(JSON.repair('[\\"hello \\\\"world\\\\"\\"]')).to eq('["hello \\"world\\""]')
        expect(JSON.repair('{\\"stringified\\": \\"hello \\\\"world\\\\"\\"}')).to \
          eq('{"stringified": "hello \\"world\\""}')

        # TODO: Check this case
        # expect(JSON.repair('[\\"hello\\, \\"world\\"]')).to eq('["hello","world"]')
        expect(JSON.repair('\\"hello"')).to eq('"hello"')
      end

      it 'strips a leading comma from an array' do
        expect(JSON.repair('[,1,2,3]')).to eq('[1,2,3]')
        expect(JSON.repair('[/* a */,/* b */1,2,3]')).to eq('[1,2,3]')
        expect(JSON.repair('[, 1,2,3]')).to eq('[ 1,2,3]')
        expect(JSON.repair('[ , 1,2,3]')).to eq('[  1,2,3]')
      end

      it 'strips a leading comma from an object' do
        expect(JSON.repair('{,"message": "hi"}')).to eq('{"message": "hi"}')
        expect(JSON.repair('{/* a */,/* b */"message": "hi"}')).to eq('{"message": "hi"}')
        expect(JSON.repair('{ ,"message": "hi"}')).to eq('{ "message": "hi"}')
        expect(JSON.repair('{, "message": "hi"}')).to eq('{ "message": "hi"}')
      end

      it 'strips trailing commas from an array' do
        expect(JSON.repair('[1,2,3,]')).to eq('[1,2,3]')
        expect(JSON.repair("[1,2,3,\n]")).to eq("[1,2,3\n]")
        expect(JSON.repair("[1,2,3,  \n  ]")).to eq("[1,2,3  \n  ]")
        expect(JSON.repair('[1,2,3,/*foo*/]')).to eq('[1,2,3]')
        expect(JSON.repair('{"array":[1,2,3,]}')).to eq('{"array":[1,2,3]}')
      end

      it 'strips trailing commas from an object' do
        expect(JSON.repair('{"a":2,}')).to eq('{"a":2}')
        expect(JSON.repair('{"a":2  ,  }')).to eq('{"a":2    }')
        expect(JSON.repair("{\"a\":2  , \n }")).to eq("{\"a\":2   \n }")
        expect(JSON.repair('{"a":2/*foo*/,/*foo*/}')).to eq('{"a":2}')
        expect(JSON.repair('{},')).to eq('{}')
      end

      it 'strips trailing comma at the end' do
        expect(JSON.repair('4,')).to eq('4')
        expect(JSON.repair('4 ,')).to eq('4 ')
        expect(JSON.repair('4 , ')).to eq('4  ')
        expect(JSON.repair('{"a":2},')).to eq('{"a":2}')
        expect(JSON.repair('[1,2,3],')).to eq('[1,2,3]')
      end

      it 'adds a missing closing brace for an object' do
        expect(JSON.repair('{')).to eq('{}')
        expect(JSON.repair('{"a":2')).to eq('{"a":2}')
        expect(JSON.repair('{"a":2,')).to eq('{"a":2}')
        expect(JSON.repair('{"a":{"b":2}')).to eq('{"a":{"b":2}}')
        expect(JSON.repair("{\n  \"a\":{\"b\":2\n}")).to eq("{\n  \"a\":{\"b\":2\n}}")
        expect(JSON.repair('[{"b":2]')).to eq('[{"b":2}]')
        expect(JSON.repair("[{\"b\":2\n]")).to eq("[{\"b\":2}\n]")
        expect(JSON.repair('[{"i":1{"i":2}]')).to eq('[{"i":1},{"i":2}]')
        expect(JSON.repair('[{"i":1,{"i":2}]')).to eq('[{"i":1},{"i":2}]')
      end

      it 'removes a redundant closing bracket for an object' do
        expect(JSON.repair('{"a": 1}}')).to eq('{"a": 1}')
        expect(JSON.repair('{"a": 1}}]}')).to eq('{"a": 1}')
        expect(JSON.repair('{"a": 1 }  }  ]  }  ')).to eq('{"a": 1 }        ')
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
        expect(JSON.repair("{\n\"values\":[1,2,3\n}")).to eq("{\n\"values\":[1,2,3]\n}")
        expect(JSON.repair("{\n\"values\":[1,2,3\n")).to eq("{\n\"values\":[1,2,3]}\n")
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

        expected_json = <<~EXPECTED_JSON
          {
              "_id" : "123",
              "isoDate" : "2012-12-19T06:01:17.171Z",
              "regularNumber" : 67,
              "long" : "2",
              "long2" : 2,
              "int" : "3",
              "int2" : 3,
              "decimal" : "4",
              "decimal2" : 4
          }
        EXPECTED_JSON

        expect(JSON.repair(mongo_document)).to eq(expected_json)
      end

      it 'does not match MongoDB-like functions in an unquoted string' do
        expect { JSON.repair('["This is C(2)", "This is F(3)]') }.to \
          raise_error(JSON::JSONRepairError, 'Unexpected character "(" at index 27')
        expect { JSON.repair('["This is C(2)", This is F(3)]') }.to \
          raise_error(JSON::JSONRepairError, 'Unexpected character "(" at index 26')

        # TODO: ideally, we should be able to repair an unquoted string containing ( and )
        # expect(JSON.repair('["This is C(2)", "This is F(3)]')).to \
        #   eq('["This is C(2)", "This is F(3)"]')
        # expect(JSON.repair('["This is C(2)", This is F(3)]')).to \
        #   eq('["This is C(2)", "This is F(3)"]')
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
        expect(JSON.repair('{foo: bar}')).to eq('{"foo": "bar"}')
        expect(JSON.repair('foo 2 bar')).to eq('"foo 2 bar"')
        expect(JSON.repair('{greeting: hello world}')).to \
          eq('{"greeting": "hello world"}')
        expect(JSON.repair("{greeting: hello world\nnext: \"line\"}")).to \
          eq("{\"greeting\": \"hello world\",\n\"next\": \"line\"}")
        expect(JSON.repair('{greeting: hello world!}')).to \
          eq('{"greeting": "hello world!"}')
      end

      it 'turns invalid numbers into strings' do
        expect(JSON.repair('ES2020')).to eq('"ES2020"')
        expect(JSON.repair('0.0.1')).to eq('"0.0.1"')
        expect(JSON.repair('746de9ad-d4ff-4c66-97d7-00a92ad46967')).to \
          eq('"746de9ad-d4ff-4c66-97d7-00a92ad46967"')
        expect(JSON.repair('234..5')).to eq('"234..5"')
        expect(JSON.repair('[0.0.1,2]')).to eq('["0.0.1",2]')
        expect(JSON.repair('[2 0.0.1 2]')).to eq('[2, "0.0.1 2"]')
        expect(JSON.repair('2e3.4')).to eq('"2e3.4"')
      end

      it 'repairs regular expressions' do
        expect(JSON.repair('{regex: /standalone-styles.css/}')).to \
          eq('{"regex": "/standalone-styles.css/"}')
      end

      it 'concatenates strings' do
        expect(JSON.repair('"hello" + " world"')).to eq('"hello world"')
        expect(JSON.repair("\"hello\" +\n \" world\"")).to eq('"hello world"')
        expect(JSON.repair('"a"+"b"+"c"')).to eq('"abc"')
        expect(JSON.repair('"hello" + /*comment*/ " world"')).to eq('"hello world"')
        expect(JSON.repair("{\n  \"greeting\": 'hello' +\n 'world'\n}")).to \
          eq("{\n  \"greeting\": \"helloworld\"\n}")
        expect(JSON.repair("\"hello +\n \" world\"")).to eq('"hello world"')
        expect(JSON.repair('"hello +')).to eq('"hello"')
        expect(JSON.repair('["hello +]')).to eq('["hello"]')
      end

      it 'repairs missing comma between array items' do
        expect(JSON.repair('{"array": [{}{}]}')).to eq('{"array": [{},{}]}')
        expect(JSON.repair('{"array": [{} {}]}')).to eq('{"array": [{}, {}]}')
        expect(JSON.repair("{\"array\": [{}\n{}]}")).to eq("{\"array\": [{},\n{}]}")
        expect(JSON.repair("{\"array\": [\n{}\n{}\n]}")).to eq("{\"array\": [\n{},\n{}\n]}")
        expect(JSON.repair("{\"array\": [\n1\n2\n]}")).to eq("{\"array\": [\n1,\n2\n]}")
        expect(JSON.repair("{\"array\": [\n\"a\"\n\"b\"\n]}")).to eq("{\"array\": [\n\"a\",\n\"b\"\n]}")
      end

      it 'repairs missing comma between object properties' do
        expect(JSON.repair("{\"a\":2\n\"b\":3\n}")).to eq("{\"a\":2,\n\"b\":3\n}")
        expect(JSON.repair("{\"a\":2\n\"b\":3\nc:4}")).to eq("{\"a\":2,\n\"b\":3,\n\"c\":4}")
      end

      it 'repairs numbers at the end' do
        expect(JSON.repair('{"a":2.')).to eq('{"a":2.0}')
        expect(JSON.repair('{"a":2e')).to eq('{"a":2e0}')
        expect(JSON.repair('{"a":2e-')).to eq('{"a":2e-0}')
        expect(JSON.repair('{"a":-')).to eq('{"a":-0}')
        expect(JSON.repair('[2e,')).to eq('[2e0]')
        expect(JSON.repair('[2e ')).to eq('[2e0] ')
        expect(JSON.repair('[-,')).to eq('[-0]')
      end

      it 'repairs missing colon between object key and value' do
        expect(JSON.repair('{"a" "b"}')).to eq('{"a": "b"}')
        expect(JSON.repair('{"a" 2}')).to eq('{"a": 2}')
        expect(JSON.repair('{"a" true}')).to eq('{"a": true}')
        expect(JSON.repair('{"a" false}')).to eq('{"a": false}')
        expect(JSON.repair('{"a" null}')).to eq('{"a": null}')
        expect(JSON.repair('{"a"2}')).to eq('{"a":2}')
        expect(JSON.repair("{\n\"a\" \"b\"\n}")).to eq("{\n\"a\": \"b\"\n}")
        expect(JSON.repair('{"a" \'b\'}')).to eq('{"a": "b"}')
        expect(JSON.repair("{'a' 'b'}")).to eq('{"a": "b"}')
        expect(JSON.repair('{“a” “b”}')).to eq('{"a": "b"}')
        expect(JSON.repair("{a 'b'}")).to eq('{"a": "b"}')
        expect(JSON.repair('{a “b”}')).to eq('{"a": "b"}')
      end

      it 'repairs missing a combination of comma, quotes and brackets' do
        expect(JSON.repair("{\"array\": [\na\nb\n]}")).to eq("{\"array\": [\n\"a\",\n\"b\"\n]}")
        expect(JSON.repair("1\n2")).to eq("[\n1,\n2\n]")
        expect(JSON.repair("[a,b\nc]")).to eq("[\"a\",\"b\",\n\"c\"]")
      end

      it 'repairs newline separated JSON (for example from MongoDB)' do
        text = "/* 1 */\n{}\n\n/* 2 */\n{}\n\n/* 3 */\n{}\n"

        expected = "[\n\n{},\n\n\n{},\n\n\n{}\n\n]"

        expect(JSON.repair(text)).to eq(expected)
      end

      it 'repairs newline separated JSON having commas' do
        text = "/* 1 */\n{},\n\n/* 2 */\n{},\n\n/* 3 */\n{}\n"

        expected = "[\n\n{},\n\n\n{},\n\n\n{}\n\n]"

        expect(JSON.repair(text)).to eq(expected)
      end

      it 'repairs newline separated JSON having commas and trailing comma' do
        text = "/* 1 */\n{},\n\n/* 2 */\n{},\n\n/* 3 */\n{},\n"

        expected = "[\n\n{},\n\n\n{},\n\n\n{}\n\n]"

        expect(JSON.repair(text)).to eq(expected)
      end

      it 'repairs a comma separated list with value' do
        expect(JSON.repair('1,2,3')).to eq("[\n1,2,3\n]")
        expect(JSON.repair('1,2,3,')).to eq("[\n1,2,3\n]")
        expect(JSON.repair("1\n2\n3")).to eq("[\n1,\n2,\n3\n]")
        expect(JSON.repair("a\nb")).to eq("[\n\"a\",\n\"b\"\n]")
      end

      it 'repairs a number with leading zero' do
        expect(JSON.repair('0789')).to eq('"0789"')
        expect(JSON.repair('000789')).to eq('"000789"')
        expect(JSON.repair('001.2')).to eq('"001.2"')
        expect(JSON.repair('002e3')).to eq('"002e3"')
        expect(JSON.repair('[0789]')).to eq('["0789"]')
        expect(JSON.repair('{value:0789}')).to eq('{"value":"0789"}')
      end
    end

    context 'when the JSON cannot be repaired' do
      specify do
        expect { JSON.repair('') }.to \
          raise_error(JSON::JSONRepairError, 'Unexpected end of json string')
      end

      specify do
        expect { JSON.repair('{"a",') }.to \
          raise_error(JSON::JSONRepairError, 'Colon expected')
      end

      specify do
        expect { JSON.repair('{:2}') }.to \
          raise_error(JSON::JSONRepairError, 'Object key expected')
      end

      specify do
        expect { JSON.repair('{"a":2}{}') }.to \
          raise_error(JSON::JSONRepairError, 'Unexpected character "{" at index 7')
      end

      specify do
        expect { JSON.repair('{"a" ]') }.to \
          raise_error(JSON::JSONRepairError, 'Colon expected')
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
    end
  end
end
