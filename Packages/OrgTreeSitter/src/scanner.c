#include <stdbool.h>
#include <stddef.h>
#include <string.h>
#include <tree_sitter/parser.h>

enum TokenType {
  END_OF_FILE,
  TODO_KEYWORD,
  DRAWER_BEGIN,
  FIXED_WIDTH_MARKER,
  HORIZONTAL_RULE_MARKER,
  EXAMPLE_BLOCK_BEGIN,
  EXAMPLE_BLOCK_END,
  EXPORT_BLOCK_BEGIN,
  EXPORT_BLOCK_END,
  COMMENT_BLOCK_BEGIN,
  COMMENT_BLOCK_END,
  VERSE_BLOCK_BEGIN,
  VERSE_BLOCK_END,
  CENTER_BLOCK_BEGIN,
  CENTER_BLOCK_END,
  DYNAMIC_BLOCK_BEGIN,
  DYNAMIC_BLOCK_END,
  SOURCE_BLOCK_BEGIN_MARKER,
  SOURCE_BLOCK_END,
  LATEX_BLOCK,
  LATEX_FRAGMENT,
};

static bool horizontal_space(int32_t c) { return c == ' ' || c == '\t'; }
static bool line_end(TSLexer *lexer) {
  return lexer->eof(lexer) || lexer->lookahead == '\r' || lexer->lookahead == '\n';
}

// Returns 1 for an opener, 2 for END, 3 for PROPERTIES, 4 for fixed width,
// or 0 for text.
// Leave the newline unconsumed, so the grammar owns source line boundaries.
static int drawer_delimiter(TSLexer *lexer) {
  while (horizontal_space(lexer->lookahead)) lexer->advance(lexer, false);
  if (lexer->lookahead != ':') return 0;
  lexer->advance(lexer, false);
  if (horizontal_space(lexer->lookahead)) {
    lexer->advance(lexer, false);
    return 4;
  }
  if (line_end(lexer)) return 4;
  char name[11] = {0};
  unsigned length = 0;
  while ((lexer->lookahead >= 'a' && lexer->lookahead <= 'z') ||
         (lexer->lookahead >= 'A' && lexer->lookahead <= 'Z') ||
         (lexer->lookahead >= '0' && lexer->lookahead <= '9') ||
         lexer->lookahead == '_' || lexer->lookahead == '-' ||
         lexer->lookahead >= 0x80) {
    int32_t c = lexer->lookahead;
    if (c >= 'a' && c <= 'z') c -= 'a' - 'A';
    if (length < sizeof(name) - 1) name[length] = c < 0x80 ? (char)c : '?';
    length++;
    lexer->advance(lexer, false);
  }
  if (!length || lexer->lookahead != ':') return 0;
  lexer->advance(lexer, false);
  while (horizontal_space(lexer->lookahead)) lexer->advance(lexer, false);
  if (!line_end(lexer)) return 0;
  if (length == 3 && strcmp(name, "END") == 0) return 2;
  if (length == 10 && strcmp(name, "PROPERTIES") == 0) return 3;
  return 1;
}

static bool scan_colon_line(TSLexer *lexer, const bool *valid_symbols) {
  int opening = drawer_delimiter(lexer);
  if (opening == 4 && valid_symbols[FIXED_WIDTH_MARKER]) {
    lexer->mark_end(lexer);
    lexer->result_symbol = FIXED_WIDTH_MARKER;
    return true;
  }
  if (opening != 1 || !valid_symbols[DRAWER_BEGIN]) return false;
  lexer->mark_end(lexer);
  while (!lexer->eof(lexer)) {
    if (lexer->lookahead == '\r') lexer->advance(lexer, false);
    if (lexer->lookahead == '\n') lexer->advance(lexer, false);
    if (lexer->lookahead == '*') {
      do { lexer->advance(lexer, false); } while (lexer->lookahead == '*');
      if (horizontal_space(lexer->lookahead)) return false;
    }
    int delimiter = drawer_delimiter(lexer);
    if (delimiter == 2) {
      lexer->result_symbol = DRAWER_BEGIN;
      return true;
    }
    if (delimiter == 1 || delimiter == 3) return false; // Drawers cannot nest.
    while (!line_end(lexer)) lexer->advance(lexer, false);
  }
  return false;
}

static bool scan_rule(TSLexer *lexer) {
  unsigned length = 0;
  while (lexer->lookahead == '-') {
    length++;
    lexer->advance(lexer, false);
  }
  while (horizontal_space(lexer->lookahead)) lexer->advance(lexer, false);
  if (length < 5 || !line_end(lexer)) return false;
  lexer->mark_end(lexer);
  lexer->result_symbol = HORIZONTAL_RULE_MARKER;
  return true;
}

// Validate the entire delimiter line. Prefixes such as BEGIN_EXAMPLE_extra
// or -----ordinary must remain text rather than produce spurious containers.
static bool scan_block_boundary(TSLexer *lexer, const bool *valid_symbols) {
  lexer->advance(lexer, false); // #
  if (lexer->lookahead != '+') return false;
  lexer->advance(lexer, false);
  char word[24] = {0};
  unsigned length = 0;
  while (!line_end(lexer) && !horizontal_space(lexer->lookahead)) {
    int32_t c = lexer->lookahead;
    if (c >= 'a' && c <= 'z') c -= 'a' - 'A';
    if (length >= sizeof(word) - 1 || c >= 0x80) return false;
    word[length++] = (char)c;
    lexer->advance(lexer, false);
  }
  static const char *const names[] = {
    "BEGIN_EXAMPLE", "END_EXAMPLE", "BEGIN_EXPORT", "END_EXPORT",
    "BEGIN_COMMENT", "END_COMMENT", "BEGIN_VERSE", "END_VERSE",
    "BEGIN_CENTER", "END_CENTER", "BEGIN:", "END:",
    "BEGIN_SRC", "END_SRC",
  };
  for (unsigned index = 0; index < sizeof(names) / sizeof(names[0]); index++) {
    unsigned symbol = EXAMPLE_BLOCK_BEGIN + index;
    if (!valid_symbols[symbol] || strcmp(word, names[index]) != 0) continue;
    // Source openers have structured language/argument fields in the grammar.
    // Leave their whitespace and arguments unconsumed, but include indentation
    // in the marker. The exact word match also rejects BEGIN_SRC_extra.
    if (symbol == SOURCE_BLOCK_BEGIN_MARKER) {
      lexer->mark_end(lexer);
      lexer->result_symbol = symbol;
      return true;
    }
    while (horizontal_space(lexer->lookahead)) lexer->advance(lexer, false);
    if (index % 2 == 0) {
      if (symbol == DYNAMIC_BLOCK_BEGIN && line_end(lexer)) return false;
      while (!line_end(lexer)) lexer->advance(lexer, false);
    } else if (!line_end(lexer)) {
      return false;
    }
    lexer->mark_end(lexer);
    lexer->result_symbol = symbol;
    return true;
  }
  return false;
}

// Consume a complete formula as one token so Org markup and blank lines in
// TeX never become separate Org nodes. Failed/incomplete openers remain text.
static bool scan_latex(TSLexer *lexer, const bool *valid_symbols) {
  bool dollar = lexer->lookahead == '$';
  bool display = false;
  char closing = 0;
  char environment[16] = {0};
  if (dollar) {
    lexer->advance(lexer, false);
    display = lexer->lookahead == '$';
    if (display) lexer->advance(lexer, false);
    else if (lexer->lookahead == ' ' || lexer->lookahead == '\t' || line_end(lexer)) return false;
    closing = '$';
  } else {
    lexer->advance(lexer, false); // backslash
    if (lexer->lookahead == '(' || lexer->lookahead == '[') {
      display = lexer->lookahead == '[';
      closing = display ? ']' : ')';
      lexer->advance(lexer, false);
    } else {
      const char *begin = "begin{";
      for (unsigned i = 0; begin[i]; i++) {
        if (lexer->lookahead != begin[i]) return false;
        lexer->advance(lexer, false);
      }
      unsigned length = 0;
      while (lexer->lookahead != '}') {
        if (line_end(lexer) || length >= sizeof(environment) - 1) return false;
        environment[length++] = (char)lexer->lookahead;
        lexer->advance(lexer, false);
      }
      lexer->advance(lexer, false);
      static const char *const names[] = {
        "equation", "equation*", "displaymath", "align", "align*", "aligned",
        "alignat", "alignat*", "alignedat", "gather", "gather*", "multline",
        "multline*", "eqnarray", "eqnarray*", "cases", "array", "matrix",
        "pmatrix", "bmatrix", "Bmatrix", "vmatrix", "Vmatrix",
      };
      bool allowed = false;
      for (unsigned i = 0; i < sizeof(names) / sizeof(names[0]); i++) {
        if (strcmp(environment, names[i]) == 0) allowed = true;
      }
      if (!allowed) return false;
      display = true;
    }
  }
  unsigned symbol = display ? LATEX_BLOCK : LATEX_FRAGMENT;
  if (!valid_symbols[symbol]) return false;
  unsigned depth = 1;
  bool closed = false;
  while (!lexer->eof(lexer)) {
    // Dollar fragments are single-line; explicit TeX delimiters may span lines.
    if (dollar && !display && line_end(lexer)) return false;
    if (lexer->lookahead == '\\') {
      lexer->advance(lexer, false);
      if (!dollar && closing && lexer->lookahead == closing) {
        lexer->advance(lexer, false);
        closed = true;
        break;
      }
      if (environment[0] && (lexer->lookahead == 'b' || lexer->lookahead == 'e')) {
        bool opening = lexer->lookahead == 'b';
        const char *word = opening ? "begin{" : "end{";
        unsigned i = 0;
        while (word[i] && lexer->lookahead == word[i]) {
          lexer->advance(lexer, false);
          i++;
        }
        if (word[i]) continue;
        i = 0;
        while (environment[i] && lexer->lookahead == environment[i]) {
          lexer->advance(lexer, false);
          i++;
        }
        if (environment[i] || lexer->lookahead != '}') continue;
        lexer->advance(lexer, false);
        if (opening) depth++;
        else if (--depth == 0) { closed = true; break; }
        continue;
      }
      // An escaped delimiter (or backslash) cannot end/open a formula.
      if (!lexer->eof(lexer)) lexer->advance(lexer, false);
    } else if (dollar && lexer->lookahead == '$') {
      lexer->advance(lexer, false);
      if (display) {
        if (lexer->lookahead != '$') continue;
        lexer->advance(lexer, false);
      } else {
        lexer->mark_end(lexer);
        if ((lexer->lookahead >= '0' && lexer->lookahead <= '9') || lexer->lookahead == '$') return false;
      }
      closed = true;
      break;
    } else {
      lexer->advance(lexer, false);
    }
    if (lexer->eof(lexer)) return false;
  }
  if (!closed) return false;
  lexer->mark_end(lexer);
  lexer->result_symbol = symbol;
  return true;
}

static bool is_todo_keyword(const char *word, size_t length) {
  static const char *const keywords[] = {
    "TODO",
    "NEXT",
    "WAIT",
    "SOMEDAY",
    "URGENT",
    "DONE",
    "CANCELED",
  };

  for (size_t index = 0; index < sizeof(keywords) / sizeof(keywords[0]); index++) {
    if (strlen(keywords[index]) == length &&
        memcmp(keywords[index], word, length) == 0) {
      return true;
    }
  }
  return false;
}

void *tree_sitter_org_external_scanner_create(void) {
  return NULL;
}

void tree_sitter_org_external_scanner_destroy(void *payload) {
  (void)payload;
}

unsigned tree_sitter_org_external_scanner_serialize(
  void *payload,
  char *buffer
) {
  (void)payload;
  (void)buffer;
  return 0;
}

void tree_sitter_org_external_scanner_deserialize(
  void *payload,
  const char *buffer,
  unsigned length
) {
  (void)payload;
  (void)buffer;
  (void)length;
}

bool tree_sitter_org_external_scanner_scan(
  void *payload,
  TSLexer *lexer,
  const bool *valid_symbols
) {
  (void)payload;

  if (valid_symbols[END_OF_FILE] && lexer->eof(lexer)) {
    lexer->mark_end(lexer);
    lexer->result_symbol = END_OF_FILE;
    return true;
  }

  if (valid_symbols[LATEX_BLOCK] || valid_symbols[LATEX_FRAGMENT]) {
    if (lexer->lookahead == '$' || lexer->lookahead == '\\') {
      return scan_latex(lexer, valid_symbols);
    }
  }

  if (lexer->get_column(lexer) == 0) {
    while (horizontal_space(lexer->lookahead)) lexer->advance(lexer, false);
    if (valid_symbols[LATEX_BLOCK] && (lexer->lookahead == '$' || lexer->lookahead == '\\')) {
      return scan_latex(lexer, valid_symbols);
    }
    if (lexer->lookahead == ':' &&
        (valid_symbols[DRAWER_BEGIN] || valid_symbols[FIXED_WIDTH_MARKER])) {
      return scan_colon_line(lexer, valid_symbols);
    }
    if (lexer->lookahead == '-' && valid_symbols[HORIZONTAL_RULE_MARKER]) {
      return scan_rule(lexer);
    }
    if (lexer->lookahead == '#') return scan_block_boundary(lexer, valid_symbols);
  }

  if (valid_symbols[TODO_KEYWORD]) {
    char word[16];
    size_t length = 0;

    while (lexer->lookahead >= 'A' && lexer->lookahead <= 'Z') {
      if (length < sizeof(word)) {
        word[length] = (char)lexer->lookahead;
      }
      length++;
      lexer->advance(lexer, false);
    }

    bool has_boundary = horizontal_space(lexer->lookahead) || line_end(lexer);
    if (length <= sizeof(word) && has_boundary && is_todo_keyword(word, length)) {
      while (horizontal_space(lexer->lookahead)) {
        lexer->advance(lexer, false);
      }
      lexer->mark_end(lexer);
      lexer->result_symbol = TODO_KEYWORD;
      return true;
    }
  }

  return false;
}
