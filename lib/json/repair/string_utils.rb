# frozen_string_literal: true

module JSON
  module Repair
    module StringUtils
      # Constants for character chars
      BACKSLASH = '\\' # 0x5c
      SLASH = '/' # 0x2f
      ASTERISK = '*' # 0x2a
      OPENING_BRACE = '{' # 0x7b
      CLOSING_BRACE = '}' # 0x7d
      OPENING_BRACKET = '[' # 0x5b
      CLOSING_BRACKET = ']' # 0x5d
      OPEN_PARENTHESIS = '(' # 0x28
      CLOSE_PARENTHESIS = ')' # 0x29
      SPACE = ' ' # 0x20
      NEWLINE = "\n" # 0xa
      TAB = "\t" # 0x9
      RETURN = "\r" # 0xd
      BACKSPACE = "\b" # 0x08
      FORM_FEED = "\f" # 0x0c
      DOUBLE_QUOTE = '"' # 0x0022
      PLUS = '+' # 0x2b
      MINUS = '-' # 0x2d
      QUOTE = "'" # 0x27
      ZERO = '0' # 0x30
      NINE = '9' # 0x39
      COMMA = ',' # 0x2c
      DOT = '.' # 0x2e
      COLON = ':' # 0x3a
      SEMICOLON = ';' # 0x3b
      UPPERCASE_A = 'A' # 0x41
      LOWERCASE_A = 'a' # 0x61
      UPPERCASE_E = 'E' # 0x45
      LOWERCASE_E = 'e' # 0x65
      UPPERCASE_F = 'F' # 0x46
      LOWERCASE_F = 'f' # 0x66
      NON_BREAKING_SPACE = ' ' # 0xa0
      MONGOLIAN_VOWEL_SEPARATOR = '᠎' # 0x180e
      EN_QUAD = ' ' # 0x2000
      ZERO_WIDTH_SPACE = '​' # 0x200b
      NARROW_NO_BREAK_SPACE = ' ' # 0x202f
      MEDIUM_MATHEMATICAL_SPACE = ' ' # 0x205f
      IDEOGRAPHIC_SPACE = '　' # 0x3000
      ZERO_WIDTH_NO_BREAK_SPACE = '﻿' # 0xfeff
      DOUBLE_QUOTE_LEFT = '“' # 0x201c
      DOUBLE_QUOTE_RIGHT = '”' # 0x201d
      QUOTE_LEFT = '‘' # 0x2018
      QUOTE_RIGHT = '’' # 0x2019
      GRAVE_ACCENT = '`' # 0x0060
      ACUTE_ACCENT = '´' # 0x00b4

      REGEX_DELIMITER = %r{^[,:\[\]/{}()\n+]+$}
      REGEX_UNQUOTED_STRING_DELIMITER = %r{^[,\[\]/{}\n+]+$}
      REGEX_START_OF_VALUE = /^[\[{\w-]$/
      # matches "https://" and other schemas
      REGEX_URL_START = %r{^(http|https|ftp|mailto|file|data|irc)://$}
      # matches all valid URL characters EXCEPT "[", "]", and "," (important JSON delimiters)
      REGEX_URL_CHAR = %r{^[A-Za-z0-9\-._~:/?#@!$&'()*+;=]$}

      # Functions to check character chars
      def hex?(char)
        !char.nil? &&
          ((char >= ZERO && char <= NINE) ||
           (char >= UPPERCASE_A && char <= UPPERCASE_F) ||
           (char >= LOWERCASE_A && char <= LOWERCASE_F))
      end

      def digit?(char)
        !char.nil? && char >= ZERO && char <= NINE
      end

      def valid_string_character?(char)
        char.ord >= 0x20 && char.ord <= 0x10ffff
      end

      def delimiter?(char)
        !char.nil? && REGEX_DELIMITER.match?(char)
      end

      def unquoted_string_delimiter?(char)
        !char.nil? && REGEX_UNQUOTED_STRING_DELIMITER.match?(char)
      end

      REGEX_FUNCTION_NAME_CHAR_START = /\A[a-zA-Z_$]\z/
      REGEX_FUNCTION_NAME_CHAR = /\A[a-zA-Z0-9_$]\z/

      def function_name_char_start?(char)
        !char.nil? && REGEX_FUNCTION_NAME_CHAR_START.match?(char)
      end

      def function_name_char?(char)
        !char.nil? && REGEX_FUNCTION_NAME_CHAR.match?(char)
      end

      def start_of_value?(char)
        !char.nil? && (REGEX_START_OF_VALUE.match?(char) || quote?(char))
      end

      def control_character?(char)
        !char.nil? && [NEWLINE, RETURN, TAB, BACKSPACE, FORM_FEED].include?(char)
      end

      def whitespace?(char)
        !char.nil? && [SPACE, NEWLINE, TAB, RETURN].include?(char)
      end

      def whitespace_except_newline?(char)
        !char.nil? && [SPACE, TAB, RETURN].include?(char)
      end

      def special_whitespace?(char)
        return false unless char

        [
          NON_BREAKING_SPACE,
          MONGOLIAN_VOWEL_SEPARATOR,
          NARROW_NO_BREAK_SPACE,
          MEDIUM_MATHEMATICAL_SPACE,
          IDEOGRAPHIC_SPACE,
          ZERO_WIDTH_NO_BREAK_SPACE
        ].include?(char) ||
          (char >= EN_QUAD && char <= ZERO_WIDTH_SPACE)
      end

      def same_line_whitespace?(char)
        whitespace_except_newline?(char) || special_whitespace?(char)
      end

      def whitespace_or_special?(char)
        whitespace?(char) || special_whitespace?(char)
      end

      def quote?(char)
        double_quote_like?(char) || single_quote_like?(char)
      end

      def double_quote?(char)
        char == DOUBLE_QUOTE
      end

      def single_quote?(char)
        char == QUOTE
      end

      def double_quote_like?(char)
        !char.nil? && [DOUBLE_QUOTE, DOUBLE_QUOTE_LEFT, DOUBLE_QUOTE_RIGHT].include?(char)
      end

      def single_quote_like?(char)
        !char.nil? && [QUOTE, QUOTE_LEFT, QUOTE_RIGHT, GRAVE_ACCENT, ACUTE_ACCENT].include?(char)
      end

      # Strip last occurrence of text_to_strip from text.
      #
      # `|| ''` on the slices below (and in `insert_before_last_whitespace` /
      # `remove_at_index`) is for steep's nil-narrowing: `String#[range]` is
      # typed `String?`, but every call site here keeps indices within
      # `0..text.length`, so the slices never actually return `nil`.
      def strip_last_occurrence(text, text_to_strip, strip_remaining_text: false)
        index = text.rindex(text_to_strip)
        return text unless index

        remaining_text = strip_remaining_text ? '' : (text[index + 1..] || '')
        (text[0...index] || '') + remaining_text
      end

      def insert_before_last_whitespace(text, text_to_insert)
        index = text.length

        return text + text_to_insert unless whitespace?(text[index - 1])

        index -= 1 while whitespace?(text[index - 1])

        (text[0...index] || '') + text_to_insert + (text[index..] || '')
      end

      # Parse keywords true, false, null
      # Repair Python keywords True, False, None
      # Repair Ruby keyword nil
      def parse_keywords
        parse_keyword('true', 'true') ||
          parse_keyword('false', 'false') ||
          parse_keyword('null', 'null') ||
          # Repair Python keywords True, False, None
          parse_keyword('True', 'true') ||
          parse_keyword('False', 'false') ||
          parse_keyword('None', 'null') ||
          # Repair Ruby keyword nil
          parse_keyword('nil', 'null')
      end

      def parse_keyword(name, value)
        if @json[@index, name.length] == name
          @output << value
          @index += name.length
          true
        else
          false
        end
      end

      def remove_at_index(text, start, count)
        (text[0...start] || '') + (text[start + count..] || '')
      end

      def ends_with_comma_or_newline?(text)
        /[,\n][ \t\r]*$/.match?(text)
      end
    end
  end
end
