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
      NON_BREAKING_SPACE = "\u00a0" # 0xa0
      EN_QUAD = "\u2000" # 0x2000
      HAIR_SPACE = "\u200a" # 0x200a
      NARROW_NO_BREAK_SPACE = "\u202f" # 0x202f
      MEDIUM_MATHEMATICAL_SPACE = "\u205f" # 0x205f
      IDEOGRAPHIC_SPACE = "\u3000" # 0x3000
      DOUBLE_QUOTE_LEFT = "\u201c" # 0x201c
      DOUBLE_QUOTE_RIGHT = "\u201d" # 0x201d
      QUOTE_LEFT = "\u2018" # 0x2018
      QUOTE_RIGHT = "\u2019" # 0x2019
      GRAVE_ACCENT = '`' # 0x0060
      ACUTE_ACCENT = "\u00b4" # 0x00b4

      REGEX_DELIMITER = %r{^[,:\[\]/{}()\n+]+$}
      REGEX_START_OF_VALUE = /^[\[{\w-]$/

      # Functions to check character chars
      def hex?(char)
        (char >= ZERO && char <= NINE) ||
          (char >= UPPERCASE_A && char <= UPPERCASE_F) ||
          (char >= LOWERCASE_A && char <= LOWERCASE_F)
      end

      def digit?(char)
        char && char >= ZERO && char <= NINE
      end

      def valid_string_character?(char)
        char.ord >= 0x20 && char.ord <= 0x10ffff
      end

      def delimiter?(char)
        REGEX_DELIMITER.match?(char)
      end

      def delimiter_except_slash?(char)
        delimiter?(char) && char != SLASH
      end

      def start_of_value?(char)
        REGEX_START_OF_VALUE.match?(char) || (char && quote?(char))
      end

      def control_character?(char)
        [NEWLINE, RETURN, TAB, BACKSPACE, FORM_FEED].include?(char)
      end

      def whitespace?(char)
        [SPACE, NEWLINE, TAB, RETURN].include?(char)
      end

      def special_whitespace?(char)
        [
          NON_BREAKING_SPACE, NARROW_NO_BREAK_SPACE, MEDIUM_MATHEMATICAL_SPACE, IDEOGRAPHIC_SPACE
        ].include?(char) ||
          (char >= EN_QUAD && char <= HAIR_SPACE)
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
        [DOUBLE_QUOTE, DOUBLE_QUOTE_LEFT, DOUBLE_QUOTE_RIGHT].include?(char)
      end

      def single_quote_like?(char)
        [QUOTE, QUOTE_LEFT, QUOTE_RIGHT, GRAVE_ACCENT, ACUTE_ACCENT].include?(char)
      end

      # Strip last occurrence of text_to_strip from text
      def strip_last_occurrence(text, text_to_strip, strip_remaining_text: false)
        index = text.rindex(text_to_strip)
        return text unless index

        remaining_text = strip_remaining_text ? '' : text[index + 1..]
        text[0...index] + remaining_text
      end

      def insert_before_last_whitespace(text, text_to_insert)
        index = text.length

        return text + text_to_insert unless whitespace?(text[index - 1])

        index -= 1 while whitespace?(text[index - 1])

        text[0...index] + text_to_insert + text[index..]
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
          @output += value
          @index += name.length
          true
        else
          false
        end
      end

      def remove_at_index(text, start, count)
        text[0...start] + text[start + count..]
      end

      def function_name?(text)
        /^\w+$/.match?(text)
      end

      def ends_with_comma_or_newline?(text)
        /[,\n][ \t\r]*$/.match?(text)
      end
    end
  end
end
