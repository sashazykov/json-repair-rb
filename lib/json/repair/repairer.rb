# frozen_string_literal: true

require_relative 'string_utils'

module JSON
  module Repair
    class Repairer
      include StringUtils

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

      def initialize(json)
        @json = json
        @index = 0
        @output = ''
      end

      def repair
        processed = parse_value

        throw_unexpected_end unless processed

        processed_comma = parse_character(COMMA)
        parse_whitespace_and_skip_comments if processed_comma

        if start_of_value?(@json[@index]) && ends_with_comma_or_newline?(@output)
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
        while @json[@index] == CLOSING_BRACE || @json[@index] == CLOSING_BRACKET
          @index += 1
          parse_whitespace_and_skip_comments
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
        process = parse_object || parse_array || parse_string || parse_number || parse_keywords || parse_unquoted_string
        parse_whitespace_and_skip_comments

        process
      end

      def parse_whitespace
        whitespace = ''
        while @json[@index] && (whitespace?(@json[@index]) || special_whitespace?(@json[@index]))
          whitespace += whitespace?(@json[@index]) ? @json[@index] : ' '

          @index += 1
        end

        unless whitespace.empty?
          @output += whitespace
          return true
        end

        false
      end

      def parse_comment
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
        else
          false
        end
      end

      # Parse an object like '{"key": "value"}'
      def parse_object
        return false unless @json[@index] == OPENING_BRACE

        @output += '{'
        @index += 1
        parse_whitespace_and_skip_comments

        # repair: skip leading comma like in {, message: "hi"}
        parse_whitespace_and_skip_comments if skip_character(COMMA)

        initial = true
        while @index < @json.length && @json[@index] != CLOSING_BRACE
          processed_comma = true
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

          processed_key = parse_string || parse_unquoted_string
          unless processed_key
            if @json[@index] == CLOSING_BRACE || @json[@index] == OPENING_BRACE ||
               @json[@index] == CLOSING_BRACKET || @json[@index] == OPENING_BRACKET ||
               @json[@index].nil?
              # repair trailing comma
              @output = strip_last_occurrence(@output, ',')
            else
              throw_object_key_expected
            end
            break
          end

          parse_whitespace_and_skip_comments
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
              @output += 'null'
            else
              throw_colon_expected
            end
          end
        end

        if @json[@index] == CLOSING_BRACE
          @output += '}'
          @index += 1
        else
          # repair missing end bracket
          @output = insert_before_last_whitespace(@output, '}')
        end

        true
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
      #   and fixing the string by inserting a quote there.
      def parse_string(stop_at_delimiter: false)
        if @json[@index] == BACKSLASH
          # repair: remove the first escape character
          @index += 1
          skip_escape_chars = true
        end

        if quote?(@json[@index])
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

          str = '"'
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
              @output += str

              return true
            elsif is_end_quote.call(@json[@index])
              # end quote
              i_quote = @index
              o_quote = str.length
              str += '"'
              @index += 1
              @output += str

              parse_whitespace_and_skip_comments

              if stop_at_delimiter ||
                 @index >= @json.length ||
                 delimiter?(@json[@index]) ||
                 quote?(@json[@index]) ||
                 digit?(@json[@index])
                # The quote is followed by the end of the text, a delimiter, or a next value
                parse_concatenated_string

                return true
              end

              if delimiter?(@json[prev_non_whitespace_index(i_quote - 1)])
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
            elsif stop_at_delimiter && delimiter?(@json[@index])
              # we're in the mode to stop the string at the first delimiter
              # because there is an end quote missing

              # repair missing quote
              str = insert_before_last_whitespace(str, '"')
              @output += str

              parse_concatenated_string

              return true
            elsif @json[@index] == BACKSLASH
              # handle escaped content like \n or \u2605
              char = @json[@index + 1]
              escape_char = ESCAPE_CHARACTERS[char]
              if escape_char
                str += @json[@index, 2]
                @index += 2
              elsif char == 'u'
                j = 2
                j += 1 while j < 6 && @json[@index + j] && hex?(@json[@index + j])
                if j == 6
                  str += @json[@index, 6]
                  @index += 6
                elsif @index + j >= @json.length
                  # repair invalid or truncated unicode char at the end of the text
                  # by removing the unicode char and ending the string here
                  @index = @json.length
                else
                  throw_invalid_unicode_character
                end
              else
                # repair invalid escape character: remove it
                str += char
                @index += 2
              end
            else
              # handle regular characters
              char = @json[@index]

              if char == DOUBLE_QUOTE && @json[@index - 1] != BACKSLASH
                # repair unescaped double quote
                str += "\\#{char}"
              elsif control_character?(char)
                # unescaped control character
                str += CONTROL_CHARACTERS[char]
              else
                throw_invalid_character(char) unless valid_string_character?(char)
                str += char
              end

              @index += 1
            end

            if skip_escape_chars
              # repair: skipped escape character (nothing to do)
              skip_escape_character
            end
          end
        end

        false
      end

      # Repair an unquoted string by adding quotes around it
      # Repair a MongoDB function call like NumberLong("2")
      # Repair a JSONP function call like callback({...});
      def parse_unquoted_string
        start = @index
        @index += 1 while @index < @json.length && !delimiter_except_slash?(@json[@index]) && !quote?(@json[@index])
        return if @index <= start

        if @json[@index] == '(' && function_name?(@json[start...@index].strip)
          # Repair a MongoDB function call like NumberLong("2")
          # Repair a JSONP function call like callback({...});
          @index += 1

          parse_value

          if @json[@index] == ')'
            # Repair: skip close bracket of function call
            @index += 1
            # Repair: skip semicolon after JSONP call
            @index += 1 if @json[@index] == ';'
          end
        else
          # Repair unquoted string
          # Also, repair undefined into null

          # First, go back to prevent getting trailing whitespaces in the string
          @index -= 1 while whitespace?(@json[@index - 1]) && @index.positive?

          symbol = @json[start...@index]
          @output += symbol == 'undefined' ? 'null' : symbol.inspect

          if @json[@index] == '"'
            # We had a missing start quote, but now we encountered the end quote, so we can skip that one
            @index += 1
          end
        end

        true
      end

      def parse_character(char)
        if @json[@index] == char
          @output += @json[@index]
          @index += 1
          true
        else
          false
        end
      end

      def parse_whitespace_and_skip_comments
        start = @index

        changed = parse_whitespace
        loop do
          changed = parse_comment
          changed = parse_whitespace if changed
          break unless changed
        end

        @index > start
      end

      # Parse a number like 2.4 or 2.4e6
      def parse_number
        start = @index
        if @json[@index] == '-'
          @index += 1
          if at_end_of_number?
            repair_number_ending_with_numeric_symbol(start)
            return true
          end
          unless digit?(@json[@index])
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

        if @json[@index] && @json[@index].downcase == 'e'
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
          num = @json[start...@index]
          has_invalid_leading_zero = num.match?(/^0\d/)

          @output += has_invalid_leading_zero ? "\"#{num}\"" : num
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
          @output += '['
          @index += 1
          parse_whitespace_and_skip_comments

          # repair: skip leading comma like in [,1,2,3]
          parse_whitespace_and_skip_comments if skip_character(COMMA)

          initial = true
          while @index < @json.length && @json[@index] != CLOSING_BRACKET
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

            # repair trailing comma
            @output = strip_last_occurrence(@output, ',')
            break
          end

          if @json[@index] == CLOSING_BRACKET
            @output += ']'
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

        parse_whitespace_and_skip_comments
        while @json[@index] == PLUS
          processed = true
          @index += 1
          parse_whitespace_and_skip_comments

          # repair: remove the end quote of the first string
          @output = strip_last_occurrence(@output, '"', strip_remaining_text: true)
          start = @output.length
          parsed_str = parse_string
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
        @output += "#{@json[start...@index]}0"
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

          processed_value = parse_value
        end

        unless processed_value
          # repair: remove trailing comma
          @output = strip_last_occurrence(@output, ',')
        end

        # repair: wrap the output inside array brackets
        @output = "[\n#{@output}\n]"
      end

      def skip_escape_character
        skip_character(BACKSLASH)
      end

      def throw_invalid_character(char)
        raise JSONRepairError, "Invalid character #{char.inspect} at index #{@index}"
      end

      def throw_unexpected_character
        raise JSONRepairError, "Unexpected character #{@json[@index].inspect} at index #{@index}"
      end

      def throw_unexpected_end
        raise JSONRepairError, 'Unexpected end of json string'
      end

      def throw_object_key_expected
        raise JSONRepairError, 'Object key expected'
      end

      def throw_colon_expected
        raise JSONRepairError, 'Colon expected'
      end

      def throw_invalid_unicode_character
        chars = @json[@index, 6]
        raise JSONRepairError, "Invalid unicode character #{chars.inspect} at index #{@index}"
      end
    end
  end
end
