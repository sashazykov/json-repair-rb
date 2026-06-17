# frozen_string_literal: true

require_relative 'repair/string_utils'

module JSON
  class Repairer
    include Repair::StringUtils

    CONTROL_CHARACTERS = {
      "\b" => '\b',
      "\f" => '\f',
      "\n" => '\n',
      "\r" => '\r',
      "\t" => '\t'
    }.freeze

    ESCAPE_CHARACTERS = {
      '"' => '"',
      '\\' => '\\',
      '/' => '/',
      'b' => "\b",
      'f' => "\f",
      'n' => "\n",
      'r' => "\r",
      't' => "\t"
    }.freeze

    MARKDOWN_OPEN_BLOCKS = ['```', '[```', '{```'].freeze
    MARKDOWN_CLOSE_BLOCKS = ['```', '```]', '```}'].freeze

    def initialize(json)
      @json = json
      @index = 0
      @output = +''
      @repaired_unescaped_quote = false
    end

    def repair
      parse_markdown_code_block(MARKDOWN_OPEN_BLOCKS)

      # repair: skip a Markdown list marker before the root value
      # (and any comments before it, which parse_value would otherwise
      # only consume after the marker check has already failed)
      parse_whitespace_and_skip_comments
      skip_markdown_list_marker

      processed = parse_value

      throw_unexpected_end unless processed

      parse_markdown_code_block(MARKDOWN_CLOSE_BLOCKS)

      processed_comma = parse_character(COMMA)
      parse_whitespace_and_skip_comments if processed_comma

      if (start_of_value?(@json[@index]) || markdown_list_marker_length) &&
         ends_with_comma_or_newline?(@output)
        # start of a new value after end of the root level object: looks like
        # newline delimited JSON -> turn into a root level array
        unless processed_comma
          # repair missing comma
          @output = insert_before_last_whitespace(@output, ',')
        end

        parse_newline_delimited_json
      elsif processed_comma
        # repair: remove trailing comma
        @output = strip_last_occurrence(@output, ',')
      end

      # repair redundant end quotes
      while [CLOSING_BRACE, CLOSING_BRACKET].include?(@json[@index])
        @index += 1
        parse_whitespace_and_skip_comments(value_expected: false)
      end

      if @index >= @json.length
        # reached the end of the document properly
        return @output
      end

      throw_unexpected_character
    end

    private

    def parse_value
      parse_whitespace_and_skip_comments
      process = parse_object ||
                parse_array ||
                parse_string ||
                parse_number ||
                parse_keywords ||
                parse_unquoted_string(false) ||
                parse_regex
      parse_whitespace_and_skip_comments(value_expected: false)

      process
    end

    def parse_whitespace_and_skip_comments(skip_newline: true, value_expected: true)
      start = @index

      changed = parse_whitespace(skip_newline: skip_newline)
      loop do
        changed = parse_comment(value_expected: value_expected)
        changed = parse_whitespace(skip_newline: skip_newline) if changed
        break unless changed
      end

      @index > start
    end

    def parse_whitespace(skip_newline: true)
      whitespace = +''
      while @json[@index] && (
        (skip_newline ? whitespace?(@json[@index]) : whitespace_except_newline?(@json[@index])) ||
        special_whitespace?(@json[@index])
      )
        ws = skip_newline ? whitespace?(@json[@index]) : whitespace_except_newline?(@json[@index])
        whitespace << (ws ? @json[@index] : ' ')

        @index += 1
      end

      unless whitespace.empty?
        @output << whitespace
        return true
      end

      false
    end

    def parse_comment(value_expected: true)
      if @json[@index] == '/' && @json[@index + 1] == '*'
        # Block comment
        @index += 2
        @index += 1 until @json[@index].nil? || (@json[@index] == '*' && @json[@index + 1] == '/')
        @index += 2
        true
      elsif @json[@index] == '/' && @json[@index + 1] == '/'
        # Line comment
        @index += 2
        @index += 1 until @json[@index].nil? || @json[@index] == "\n"
        true
      elsif @json[@index] == '#' && hash_comment?(value_expected)
        # Hash line comment, like in Python, YAML, or Hjson (divergence
        # from upstream, which raises on `#` as of v3.14.0)
        @index += 1
        @index += 1 until @json[@index].nil? || @json[@index] == "\n"
        true
      else
        false
      end
    end

    # Decide whether the `#` at @index starts a line comment or an
    # unquoted value like {"color": #ff0000}, {#tag: 1}, or a root
    # #hashtag (which Python's json_repair eats as comments, losing
    # data). Where no value or key is expected an unquoted token would
    # be junk anyway, so `#` is always a comment, exactly like `//`.
    # Where one is expected, scan the rest of the line: a structural
    # delimiter (`,` `}` `]` `:`) before any whitespace means the token
    # reads as a value in context; whitespace (including the newline
    # itself) first means comment prose; reaching EOF without a newline
    # keeps the token a value, so truncated input like {"a": #tag is
    # repaired, not dropped. Divergence from upstream, as above.
    def hash_comment?(value_expected)
      return true unless value_expected

      i = @index + 1
      while (char = @json[i])
        return true if whitespace_or_special?(char)
        return false if [COMMA, COLON, CLOSING_BRACE, CLOSING_BRACKET].include?(char)

        i += 1
      end

      false
    end

    # Find and skip over a Markdown fenced code block:
    #     ``` ... ```
    # or
    #     ```json ... ```
    def parse_markdown_code_block(blocks)
      return false unless skip_markdown_code_block(blocks)

      if function_name_char_start?(@json[@index])
        # strip the optional language specifier like "json"
        @index += 1 while @index < @json.length && function_name_char?(@json[@index])
      end

      parse_whitespace_and_skip_comments

      true
    end

    def skip_markdown_code_block(blocks)
      parse_whitespace(skip_newline: true)

      blocks.each do |block|
        if @json[@index, block.length] == block
          @index += block.length
          return true
        end
      end

      false
    end

    # Look ahead from @index for a Markdown list marker like "- ", "* ",
    # "+ ", or "12. " that precedes a value. Returns the marker's length,
    # or nil when there is no marker. Only consulted at the top level —
    # the root value and each newline-delimited value — never inside
    # nested structures. A marker must be followed by same-line
    # whitespace and a value, so "-5", a trailing "- ", and "-\n{...}"
    # keep their number readings. Ordered markers are capped at nine
    # digits (the CommonMark limit) so long truncated decimals are not
    # mistaken for markers. Divergence from upstream (no Markdown list
    # handling as of v3.14.0): LLMs frequently emit JSON values as
    # Markdown list items.
    def markdown_list_marker_length
      j = @index

      if [MINUS, ASTERISK, PLUS].include?(@json[j])
        j += 1
      elsif digit?(@json[j])
        j += 1 while digit?(@json[j]) && j - @index < 9
        return nil unless [DOT, CLOSE_PARENTHESIS].include?(@json[j])

        j += 1
      else
        return nil
      end

      marker_length = j - @index
      return nil unless same_line_whitespace?(@json[j])

      j += 1 while same_line_whitespace?(@json[j])
      # a leading-dot number like ".5" is also a value here: parse_number
      # repairs it to "0.5" even though start_of_value? does not match it
      return nil unless start_of_value?(@json[j]) || @json[j] == DOT

      marker_length
    end

    # Repair a value behind a Markdown list marker, like "- {"a":1}",
    # by skipping the marker. See markdown_list_marker_length.
    def skip_markdown_list_marker
      length = markdown_list_marker_length
      return false unless length

      @index += length
      true
    end

    # Parse an object like '{"key": "value"}'
    def parse_object
      return false unless @json[@index] == OPENING_BRACE

      @output << '{'
      @index += 1
      parse_whitespace_and_skip_comments

      # repair: skip leading comma like in {, message: "hi"}
      parse_whitespace_and_skip_comments if skip_character(COMMA)

      initial = true
      while @index < @json.length && @json[@index] != CLOSING_BRACE
        first_pair = initial
        if initial
          initial = false
        else
          processed_comma = parse_character(COMMA)
          unless processed_comma
            # repair missing comma
            @output = insert_before_last_whitespace(@output, ',')
          end
          parse_whitespace_and_skip_comments
        end

        skip_ellipsis

        processed_key = parse_string || parse_unquoted_string(true)
        unless processed_key
          if @json[@index] == CLOSING_BRACE || @json[@index] == OPENING_BRACE ||
             @json[@index] == CLOSING_BRACKET || @json[@index] == OPENING_BRACKET ||
             @json[@index].nil?
            # repair trailing comma — but only the one this object's own loop
            # emitted or inserted; on the first pair the buffer's last
            # comma belongs to the enclosing container, like in [{{] or
            # {"a": 1, "b": {] (divergence from upstream, which strips
            # the parent's comma and emits invalid JSON like [{}{}])
            @output = strip_last_occurrence(@output, ',') unless first_pair
          else
            throw_object_key_expected
          end
          break
        end

        parse_whitespace_and_skip_comments(value_expected: false)
        processed_colon = parse_character(COLON)
        truncated_text = @index >= @json.length
        unless processed_colon
          if start_of_value?(@json[@index]) || truncated_text
            # repair missing colon
            @output = insert_before_last_whitespace(@output, ':')
          else
            throw_colon_expected
          end
        end

        processed_value = parse_value
        unless processed_value
          if processed_colon || truncated_text
            # repair missing object value
            @output << 'null'
          # :nocov:
          else
            # Unreachable through JSON.repair: if we got here, the colon-repair
            # branch above ran, which required start_of_value? to be true. Every
            # char that satisfies start_of_value? (see REGEX_START_OF_VALUE plus
            # quote chars) is consumable by some parse_* method, so parse_value
            # cannot return false in this state. Preserved for parity with the
            # upstream JS parser; if a future change to REGEX_START_OF_VALUE or
            # parse_unquoted_string invalidates that invariant, this branch
            # becomes live and the :nocov: will hide it.
            throw_colon_expected
          end
          # :nocov:
        end

        # repair: an object string value with unescaped quotes around a
        # colon, like {"a": "b": "c"}. Skipped when this pair already
        # needed a repair that makes the merge compound garbage: a
        # missing colon (the "key" was a stray junk word, like
        # {"v1": true, COMMENT "v2": "data"}) or a value glued together
        # by the unescaped-quote repair (like
        # {"k": "v" COMMENT "k2": "v2"}); both keep raising, matching
        # upstream
        repair_doubled_colon if processed_value && processed_colon && !@repaired_unescaped_quote
      end

      if @json[@index] == CLOSING_BRACE
        @output << '}'
        @index += 1
      else
        # repair missing end bracket
        @output = insert_before_last_whitespace(@output, '}')
      end

      true
    end

    # Repair an object value with unescaped quotes around a colon, like
    # {"a": "b": "c"}, by merging it all into one string value: 'b": "c'
    # (the unescaped-quotes reading of the input). Greedy: keeps merging
    # while another `: "..."` follows. Only the string-colon-string
    # shape is repaired; anything else falls through to the regular
    # error paths. The call site additionally requires the pair's colon
    # to be present in the input and the value string to have parsed
    # without the unescaped-quote repair (@repaired_unescaped_quote) —
    # when either repair already fired, the pair was malformed in a way
    # this merge would compound, not fix. Divergence from upstream
    # (which raises "Object key expected" as of v3.14.0), matching the
    # Go and Python json-repair libraries on the canonical case.
    def repair_doubled_colon
      loop do
        colon = @index
        # :nocov: kept for symmetry with the start_quote scan below; unreachable
        # because @index never rests on whitespace here. On first entry,
        # parse_value ends with parse_whitespace_and_skip_comments. On greedy
        # re-entry, every parse_string exit leaves @index off-whitespace: the
        # EOF path (nil is not whitespace), the stop_at_index path (a
        # prev_non_whitespace_index position), and the end-quote path (ends in
        # parse_concatenated_string, whose leading whitespace skip consumes
        # newlines too). If a future parse_value/parse_string change breaks
        # that, this scan becomes live and the :nocov: will hide it.
        colon += 1 while whitespace_or_special?(@json[colon])
        # :nocov:
        return unless @json[colon] == COLON

        # scan past special whitespace too (unlike prev_non_whitespace_index):
        # parse_whitespace treats NBSP and friends as whitespace, so this
        # repair should as well. The value's last character (at worst the
        # object's opening brace) always stops the scan before index 0.
        end_quote = colon - 1
        end_quote -= 1 while whitespace_or_special?(@json[end_quote])
        return unless quote?(@json[end_quote])

        start_quote = colon + 1
        start_quote += 1 while whitespace_or_special?(@json[start_quote])
        return unless quote?(@json[start_quote])

        # repair: replace the end quote already emitted (plus any copied
        # trailing whitespace) with the literal input span from that end
        # quote through the next start quote, escaped as string content
        @output = strip_last_occurrence(@output, '"', strip_remaining_text: true)
        @json[end_quote..start_quote].each_char do |char|
          @output << (char == DOUBLE_QUOTE ? '\"' : CONTROL_CHARACTERS.fetch(char, char))
        end

        # let parse_string consume the rest of the merged string, then
        # drop the start quote it emits (already emitted escaped above)
        @index = start_quote
        start = @output.length
        parse_string
        @output = remove_at_index(@output, start, 1)
      end
    end

    def skip_character(char)
      if @json[@index] == char
        @index += 1
        true
      else
        false
      end
    end

    # Skip ellipsis like "[1,2,3,...]" or "[1,2,3,...,9]" or "[...,7,8,9]"
    # or a similar construct in objects.
    def skip_ellipsis
      parse_whitespace_and_skip_comments

      if @json[@index] == DOT &&
         @json[@index + 1] == DOT &&
         @json[@index + 2] == DOT
        # repair: remove the ellipsis (three dots) and optionally a comma
        @index += 3
        parse_whitespace_and_skip_comments
        skip_character(COMMA)
      end
    end

    # Parse a string enclosed by double quotes "...". Can contain escaped quotes
    # Repair strings enclosed in single quotes or special quotes
    # Repair an escaped string
    #
    # The function can run in two stages:
    # - First, it assumes the string has a valid end quote
    # - If it turns out that the string does not have a valid end quote followed
    #   by a delimiter (which should be the case), the function runs again in a
    #   more conservative way, stopping the string at the first next delimiter
    #   and fixing the string by inserting a quote there, or stopping at a
    #   stop index detected in the first iteration.
    def parse_string(stop_at_delimiter: false, stop_at_index: -1)
      # fresh parse (the backtracking re-invocations below rebuild the
      # string from scratch, so they reset too); see repair_doubled_colon
      @repaired_unescaped_quote = false
      skip_escape_chars = @json[@index] == BACKSLASH
      if skip_escape_chars
        # repair: remove the first escape character
        @index += 1
      end

      return false unless quote?(@json[@index])

      # double quotes are correct JSON,
      # single quotes come from JavaScript for example, we assume it will have a correct single end quote too
      # otherwise, we will match any double-quote-like start with a double-quote-like end,
      # or any single-quote-like start with a single-quote-like end
      is_end_quote = if double_quote?(@json[@index])
                       method(:double_quote?)
                     elsif single_quote?(@json[@index])
                       method(:single_quote?)
                     elsif single_quote_like?(@json[@index])
                       method(:single_quote_like?)
                     else
                       method(:double_quote_like?)
                     end

      i_before = @index
      o_before = @output.length

      str = +'"'
      @index += 1

      loop do
        if @index >= @json.length
          # end of text, we are missing an end quote

          i_prev = prev_non_whitespace_index(@index - 1)
          if !stop_at_delimiter && delimiter?(@json[i_prev])
            # if the text ends with a delimiter, like ["hello],
            # so the missing end quote should be inserted before this delimiter
            # retry parsing the string, stopping at the first next delimiter
            @index = i_before
            @output = @output[0...o_before]

            return parse_string(stop_at_delimiter: true)
          end

          # repair missing quote
          str = insert_before_last_whitespace(str, '"')
          @output << str

          return true
        end

        # >= with a sentinel guard, not ==. Divergence from upstream (which
        # compares with == as of v3.14.0): a multi-character advance below
        # can step over the stop index, and resuming the comma-path retry
        # from beyond it would re-fire that retry with identical arguments
        # forever. The invalid-escape repair below avoids the only known
        # overshoot; this is the backstop guaranteeing termination.
        if stop_at_index >= 0 && @index >= stop_at_index
          # use the stop index detected in the first iteration, and repair end quote
          str = insert_before_last_whitespace(str, '"')
          @output << str

          return true
        end

        if is_end_quote.call(@json[@index])
          # end quote
          # let us check what is before and after the quote to verify whether this is a legit end quote
          i_quote = @index
          o_quote = str.length
          str << '"'
          @index += 1
          @output << str

          parse_whitespace_and_skip_comments(skip_newline: false, value_expected: false)

          if stop_at_delimiter ||
             @index >= @json.length ||
             delimiter?(@json[@index]) ||
             quote?(@json[@index]) ||
             digit?(@json[@index])
            # The quote is followed by the end of the text, a delimiter, or a next value
            parse_concatenated_string

            return true
          end

          i_prev_char = prev_non_whitespace_index(i_quote - 1)
          prev_char = @json[i_prev_char]

          if prev_char == ','
            # A comma followed by a quote, like '{"a":"b,c,"d":"e"}'.
            # We assume that the quote is a start quote, and that the end quote
            # should have been located right before the comma but is missing.
            @index = i_before
            @output = @output[0...o_before]

            return parse_string(stop_at_delimiter: false, stop_at_index: i_prev_char)
          end

          if delimiter?(prev_char)
            # This is not the right end quote: it is preceded by a delimiter,
            # and NOT followed by a delimiter. So, there is an end quote missing
            # parse the string again and then stop at the first next delimiter
            @index = i_before
            @output = @output[...o_before]

            return parse_string(stop_at_delimiter: true)
          end

          # revert to right after the quote but before any whitespace, and continue parsing the string
          @output = @output[...o_before]
          @index = i_quote + 1

          # repair unescaped quote
          str = "#{str[...o_quote]}\\#{str[o_quote..]}"
          @repaired_unescaped_quote = true
        elsif stop_at_delimiter && unquoted_string_delimiter?(@json[@index])
          # we're in the mode to stop the string at the first delimiter
          # because there is an end quote missing

          # test start of an url like "https://..." (this would be parsed as a comment)
          if @json[@index - 1] == ':' &&
             REGEX_URL_START.match?(@json[(i_before + 1)..(@index + 1)] || '')
            while @index < @json.length && REGEX_URL_CHAR.match?(@json[@index])
              str << @json[@index]
              @index += 1
            end
          end

          # repair missing quote
          str = insert_before_last_whitespace(str, '"')
          @output << str

          parse_concatenated_string

          return true
        elsif @json[@index] == BACKSLASH
          # handle escaped content like \n or ★
          # nil at EOF: '' mirrors JS charAt, making the invalid-escape
          # repair below a no-op that ends the string
          char = @json[@index + 1] || ''
          escape_char = ESCAPE_CHARACTERS[char]
          if escape_char
            str << @json[@index, 2]
            @index += 2
          elsif char == 'u'
            j = 2
            j += 1 while j < 6 && @json[@index + j] && hex?(@json[@index + j])
            if j == 6
              str << @json[@index, 6]
              @index += 6
            elsif @index + j >= @json.length
              # repair invalid or truncated unicode char at the end of the text
              # by removing the unicode char and ending the string here
              @index = @json.length
            else
              throw_invalid_unicode_character
            end
          elsif char == "\n"
            # repair a backslash escaped newline (like in Bash scripts)
            str << '\n'
            @index += 2
          elsif @index + 1 == stop_at_index
            # repair invalid escape character: remove it — but the escaped
            # character is the delimiter the comma-path retry said to stop
            # at, so drop only the backslash and let the stop check above
            # fire there, keeping the delimiter a delimiter. Divergence
            # from upstream, which consumes both characters, jumps the stop
            # index, and crashes ("Maximum call stack size exceeded" on
            # inputs like `["y"\, "z"]` as of v3.14.0).
            @index += 1
          else
            # repair invalid escape character: remove it
            str << char
            @index += 2
          end
        else
          # handle regular characters
          char = @json[@index]

          if char == DOUBLE_QUOTE && @json[@index - 1] != BACKSLASH
            # repair unescaped double quote
            str << "\\#{char}"
          elsif control_character?(char)
            # unescaped control character
            str << CONTROL_CHARACTERS[char]
          else
            throw_invalid_character(char) unless valid_string_character?(char)
            str << char
          end
          @index += 1
        end

        if skip_escape_chars
          # repair: skipped escape character (nothing to do)
          skip_escape_character
        end
      end
    end

    # Repair an unquoted string by adding quotes around it
    # Repair a MongoDB function call like NumberLong("2")
    # Repair a JSONP function call like callback({...});
    def parse_unquoted_string(is_key)
      # NOTE: that the symbol can end with whitespaces: we stop at the next delimiter
      # also, note that we allow strings to contain a slash / in order to support repairing regular expressions
      start = @index

      if function_name_char_start?(@json[@index])
        @index += 1 while @index < @json.length && function_name_char?(@json[@index])

        j = @index
        j += 1 while whitespace?(@json[j])

        if @json[j] == '('
          # repair a MongoDB function call like NumberLong("2")
          # repair a JSONP function call like callback({...});
          @index = j + 1

          parse_value

          if @json[@index] == ')'
            # Repair: skip close bracket of function call
            @index += 1
            # Repair: skip semicolon after JSONP call
            @index += 1 if @json[@index] == ';'
          end

          return true
        end
      end

      while @index < @json.length &&
            !unquoted_string_delimiter?(@json[@index]) &&
            !quote?(@json[@index]) &&
            (!is_key || @json[@index] != ':')
        @index += 1
      end

      # test start of an url like "https://..." (this would be parsed as a comment)
      if @json[@index - 1] == ':' &&
         REGEX_URL_START.match?(@json[start...(@index + 2)] || '')
        @index += 1 while @index < @json.length && REGEX_URL_CHAR.match?(@json[@index])
      end

      return false if @index <= start

      # Repair unquoted string
      # Also, repair undefined into null

      # First, go back to prevent getting trailing whitespaces in the string
      @index -= 1 while @index.positive? && whitespace?(@json[@index - 1])

      symbol = @json[start...@index]
      @output << (symbol == 'undefined' ? 'null' : symbol.inspect)

      if @json[@index] == '"'
        # We had a missing start quote, but now we encountered the end quote, so we can skip that one
        @index += 1
      end

      true
    end

    # Parse a regular expression literal like /foo/ or /foo\/bar/
    def parse_regex
      return false unless @json[@index] == '/'

      start = @index
      @index += 1

      @index += 1 while @index < @json.length && (@json[@index] != '/' || @json[@index - 1] == BACKSLASH)
      @index += 1

      @output << @json[start...@index].inspect

      true
    end

    def parse_character(char)
      if @json[@index] == char
        @output << @json[@index]
        @index += 1
        true
      else
        false
      end
    end

    # Parse a number like 2.4 or 2.4e6
    def parse_number
      start = @index

      # Divergence from upstream: accept and discard a leading "+". JSON5
      # permits an explicit plus; JSON does not, so "+1.23" -> "1.23" and
      # "{"a": +5}" -> {"a":5}. The "+" must be followed by a digit or a
      # leading dot (mirroring the "-" branch below); otherwise this is not
      # a number and we backtrack to the "+" so a bare "+" still raises.
      # `start` stays on the "+", so the reset paths restore @index cleanly
      # and the @index > start exponent guard below still implies a digit
      # was consumed; the two emission sites drop the leading "+" before
      # quoting. Upstream leaves "+1.23" unrepaired.
      if @json[@index] == PLUS
        @index += 1
        unless digit?(@json[@index]) || @json[@index] == DOT
          @index = start
          return false
        end
      end

      if @json[@index] == '-'
        @index += 1
        if at_end_of_number?
          repair_number_ending_with_numeric_symbol(start)
          return true
        end
        # also accept a dot so "-.5" continues into the fraction branch
        # below (divergence from upstream, which leaves "-.5" unrepaired)
        unless digit?(@json[@index]) || @json[@index] == DOT
          @index = start
          return false
        end
      end

      # Note that in JSON leading zeros like "00789" are not allowed.
      # We will allow all leading zeros here though and at the end of parse_number
      # check against trailing zeros and repair that if needed.
      # Leading zeros can have meaning, so we should not clear them.
      @index += 1 while digit?(@json[@index])

      if @json[@index] == '.'
        @index += 1
        if at_end_of_number?
          repair_number_ending_with_numeric_symbol(start)
          return true
        end
        unless digit?(@json[@index])
          @index = start
          return false
        end
        @index += 1 while digit?(@json[@index])
      end

      # Divergence from upstream: only enter the exponent branch when a
      # mantissa was consumed — at this point @index > start implies at
      # least one digit (the '-' and '.' paths reset otherwise). Upstream
      # accepts a bare "e"/"E" here and emits invalid JSON like `e0` or
      # raw `e5`; declining lets the token fall through to
      # parse_unquoted_string, matching how "-e5" already becomes "-e5".
      if @index > start && @json[@index] && @json[@index].downcase == 'e'
        @index += 1
        @index += 1 if ['-', '+'].include?(@json[@index])
        if at_end_of_number?
          repair_number_ending_with_numeric_symbol(start)
          return true
        end
        unless digit?(@json[@index])
          @index = start
          return false
        end
        @index += 1 while digit?(@json[@index])
      end

      # if we're not at the end of the number by this point, allow this to be parsed as another type
      unless at_end_of_number?
        @index = start
        return false
      end

      if @index > start
        # repair a number with leading zeros like "00789"
        # drop a leading "+" first (see the PLUS branch above), so "+05"
        # quotes like "05" and "+1.23" emits as "1.23"
        num = @json[start...@index].delete_prefix(PLUS)
        # the optional sign quotes "-05" like "05" (divergence from
        # upstream, whose unsigned check lets "-05" through unrepaired)
        has_invalid_leading_zero = num.match?(/^-?0\d/)

        @output << (has_invalid_leading_zero ? "\"#{num}\"" : repair_leading_dot_number(num))
        return true
      end

      false
    end

    def at_end_of_number?
      @index >= @json.length || delimiter?(@json[@index]) || whitespace?(@json[@index])
    end

    # Parse an array like '["item1", "item2", ...]'
    def parse_array
      if @json[@index] == OPENING_BRACKET
        @output << '['
        @index += 1
        parse_whitespace_and_skip_comments

        # repair: skip leading comma like in [,1,2,3]
        parse_whitespace_and_skip_comments if skip_character(COMMA)

        initial = true
        while @index < @json.length && @json[@index] != CLOSING_BRACKET
          first_item = initial
          if initial
            initial = false
          else
            processed_comma = parse_character(COMMA)
            # repair missing comma
            @output = insert_before_last_whitespace(@output, ',') unless processed_comma
          end

          skip_ellipsis

          processed_value = parse_value
          next if processed_value

          # repair trailing comma — but only the one this array's own loop
          # emitted or inserted; on the first item the buffer's last
          # comma belongs to the enclosing container, like in [1,[}] or
          # {"a": 1, "b": [} (divergence from upstream, which strips
          # the parent's comma and emits invalid JSON like [1[]])
          @output = strip_last_occurrence(@output, ',') unless first_item
          break
        end

        if @json[@index] == CLOSING_BRACKET
          @output << ']'
          @index += 1
        else
          # repair missing closing array bracket
          @output = insert_before_last_whitespace(@output, ']')
        end

        true
      else
        false
      end
    end

    def prev_non_whitespace_index(start)
      prev = start
      prev -= 1 while prev.positive? && whitespace?(@json[prev])
      prev
    end

    # Repair concatenated strings like "hello" + "world", change this into "helloworld"
    def parse_concatenated_string
      processed = false

      parse_whitespace_and_skip_comments(value_expected: false)
      while @json[@index] == PLUS
        processed = true
        @index += 1
        parse_whitespace_and_skip_comments(value_expected: false)

        # repair: remove the end quote of the first string
        @output = strip_last_occurrence(@output, '"', strip_remaining_text: true)
        start = @output.length
        # the segments form one logical string value: keep the doubled-colon
        # guard's flag set when an earlier segment needed the unescaped-quote
        # repair (parse_string resets it on entry)
        repaired_earlier_segment = @repaired_unescaped_quote
        parsed_str = parse_string
        @repaired_unescaped_quote ||= repaired_earlier_segment
        @output = if parsed_str
                    # repair: remove the start quote of the second string
                    remove_at_index(@output, start, 1)
                  else
                    # repair: remove the '+' because it is not followed by a string
                    insert_before_last_whitespace(@output, '"')
                  end
      end

      processed
    end

    def repair_number_ending_with_numeric_symbol(start)
      # repair numbers cut off at the end
      # this will only be called when we end after a '.', '-', or 'e' and does not
      # change the number more than it needs to make it valid JSON
      # delete_prefix drops a leading "+" (see the PLUS branch in parse_number)
      num = "#{@json[start...@index]}0".delete_prefix(PLUS)
      # quote a padded token that has an invalid leading zero, like "05e" ->
      # "05e0", applying the same rule as the end of parse_number (divergence
      # from upstream, which emits the invalid number raw)
      @output << (num.match?(/^-?0\d/) ? "\"#{num}\"" : repair_leading_dot_number(num))
    end

    # Repair a number missing its digit before the decimal point, like ".5"
    # or "-.5", into "0.5" / "-0.5". Divergence from upstream, which emits
    # the invalid leading-dot number unchanged. The guard keeps the common
    # case (a number that needs no repair) allocation-free; `sub` copies
    # its receiver even when the pattern does not match.
    def repair_leading_dot_number(num)
      return num unless num.start_with?('.', '-.')

      num.sub(/\A(?<sign>-?)\./, '\k<sign>0.')
    end

    # Parse and repair Newline Delimited JSON (NDJSON):
    # multiple JSON objects separated by a newline character
    def parse_newline_delimited_json
      # repair NDJSON
      initial = true
      processed_value = true
      while processed_value
        if initial
          initial = false
        else
          # parse optional comma, insert when missing
          processed_comma = parse_character(COMMA)
          unless processed_comma
            # repair: add missing comma
            @output = insert_before_last_whitespace(@output, ',')
          end
        end

        # repair: skip a Markdown list marker before the next value
        parse_whitespace_and_skip_comments
        skip_markdown_list_marker

        processed_value = parse_value
      end

      # repair: remove trailing comma
      # (the `while processed_value` loop above only exits when processed_value
      # is falsy, so the upstream JS `if (!processedValue)` guard is redundant)
      @output = strip_last_occurrence(@output, ',')

      # repair: wrap the output inside array brackets
      @output = "[\n#{@output}\n]"
    end

    def skip_escape_character
      skip_character(BACKSLASH)
    end

    def throw_invalid_character(char)
      raise JSONRepairError.new("Invalid character #{char.inspect}", @index)
    end

    def throw_unexpected_character
      raise JSONRepairError.new("Unexpected character #{@json[@index].inspect}", @index)
    end

    def throw_unexpected_end
      raise JSONRepairError.new('Unexpected end of json string', @index)
    end

    def throw_object_key_expected
      raise JSONRepairError.new('Object key expected', @index)
    end

    def throw_colon_expected
      raise JSONRepairError.new('Colon expected', @index)
    end

    def throw_invalid_unicode_character
      chars = @json[@index, 6]
      raise JSONRepairError.new("Invalid unicode character #{chars.inspect}", @index)
    end
  end
end
