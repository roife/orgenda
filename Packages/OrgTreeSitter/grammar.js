/**
 * A line-oriented Org grammar for editor and structured-document use.
 *
 * The grammar keeps block recognition and inline recognition as separate
 * hidden supertypes.  That mirrors the useful architectural boundary in
 * tree-sitter-markdown while keeping a single language/parser, which makes
 * embedding on Apple platforms substantially simpler.
 */

const PREC = {
  structural: 12,
  headingMetadata: 9,
  inlineMarkup: 6,
  fallback: -2,
};

module.exports = grammar({
  name: 'org',

  extras: _ => [],

  externals: $ => [
    $._eof,
    $.todo_keyword,
    $.drawer_begin,
    $.fixed_width_marker,
    $.horizontal_rule_marker,
    $.example_block_begin,
    $.example_block_end,
    $.export_block_begin,
    $.export_block_end,
    $.comment_block_begin,
    $.comment_block_end,
    $.verse_block_begin,
    $.verse_block_end,
    $.center_block_begin,
    $.center_block_end,
    $.dynamic_block_begin,
    $.dynamic_block_end,
    $._source_block_begin_marker,
    $.source_block_end,
  ],

  supertypes: $ => [
    $._block,
    $._inline,
  ],

  rules: {
    document: $ => repeat($._block),

    // ---------------------------------------------------------------------
    // Block layer
    // ---------------------------------------------------------------------

    _block: $ => choice(
      $.blank_line,
      $.source_block,
      $.quote_block,
      $.property_drawer,
      $.drawer,
      $.clock,
      $.example_block,
      $.export_block,
      $.comment_block,
      $.verse_block,
      $.center_block,
      $.dynamic_block,
      $.fixed_width,
      $.horizontal_rule,
      $.heading,
      $.planning,
      $.list,
      $.table,
      $.footnote_definition,
      $.comment,
      $.keyword,
      $.paragraph,
    ),

    blank_line: $ => $._newline,

    heading: $ => prec.right(seq(
      field('marker', $.heading_marker),
      optional(field('todo', $.todo_keyword)),
      optional(field('priority', $.priority)),
      optional(field('title', $.heading_title)),
      optional(field('tags', $.tag_list)),
      $._line_end,
    )),

    heading_marker: _ => token(prec(PREC.structural, /\*+[ \t]+/)),

    priority: _ => token(prec(PREC.headingMetadata, /\[#(?:[A-Z]|[0-5]?[0-9]|6[0-4])\][ \t]*/)),

    heading_title: $ => prec.right(repeat1($._inline)),

    tag_list: _ => token(prec(
      PREC.headingMetadata,
      /:[A-Za-z0-9_@#%]+(?::[A-Za-z0-9_@#%]+)*:[ \t]*/,
    )),

    planning: $ => prec.right(seq(
      optional(field('indent', $.planning_indent)),
      repeat1(field('entry', $.planning_entry)),
      $._line_end,
    )),

    planning_indent: _ => token(prec(PREC.structural, /[ \t]+/)),

    planning_entry: $ => prec.right(seq(
      field('keyword', $.planning_keyword),
      $.whitespace,
      field('value', choice($.timestamp_range, $.timestamp)),
      optional($.whitespace),
    )),

    planning_keyword: _ => token(prec(PREC.structural, choice(
      'SCHEDULED:',
      'DEADLINE:',
      'CLOSED:',
    ))),

    property_drawer: $ => prec.right(seq(
      $.property_drawer_begin,
      $._newline,
      repeat(choice($.property, $.blank_line)),
      $.property_drawer_end,
      $._line_end,
    )),

    property_drawer_begin: _ => token(prec(
      PREC.structural,
      /[ \t]*:[Pp][Rr][Oo][Pp][Ee][Rr][Tt][Ii][Ee][Ss]:[ \t]*/,
    )),

    property_drawer_end: _ => token(prec(
      PREC.structural,
      /[ \t]*:[Ee][Nn][Dd]:[ \t]*/,
    )),

    property: $ => prec.right(seq(
      token(prec(PREC.structural, /[ \t]*:/)),
      field('name', $.property_name),
      token.immediate(':'),
      optional(field('value', $.property_value)),
      $._line_end,
    )),

    property_name: _ => token.immediate(/[A-Za-z0-9_@#%+.-]+/),
    property_value: $ => prec.right(repeat1($._inline)),

    // The scanner validates a matching :END: before a heading/another drawer.
    // An unfinished drawer therefore stays editable text, not a container that
    // swallows the rest of the document while the user is typing.
    drawer: $ => seq(
      field('begin', $.drawer_begin),
      $._newline,
      repeat($._drawer_element),
      field('end', $.drawer_end),
      $._line_end,
    ),
    drawer_end: _ => token(prec(PREC.structural, /[ \t]*:[Ee][Nn][Dd]:[ \t]*/)),
    _drawer_element: $ => choice(
      $.blank_line, $.clock, $.list, $.table, $.paragraph,
      $.source_block, $.quote_block, $.example_block, $.export_block,
      $.comment_block, $.verse_block, $.center_block, $.dynamic_block,
      $.fixed_width, $.horizontal_rule, $.comment, $.keyword,
      $.footnote_definition,
    ),

    clock: $ => prec.right(seq(
      field('keyword', $.clock_keyword),
      choice(
        seq(field('value', $.inactive_timestamp), optional(seq(
          token.immediate('--'), field('end', $.inactive_timestamp),
          optional($.whitespace), field('duration', $.clock_duration),
        ))),
        field('duration', $.clock_duration),
      ),
      optional($.whitespace),
      $._line_end,
    )),
    clock_keyword: _ => token(prec(PREC.structural, /[ \t]*[Cc][Ll][Oo][Cc][Kk]:[ \t]+/)),
    clock_duration: _ => token(/=>[ \t]*[0-9]+:[0-9]{2}/),

    fixed_width: $ => prec.right(repeat1($.fixed_width_line)),
    fixed_width_line: $ => seq(
      field('marker', $.fixed_width_marker),
      optional(field('content', $.fixed_width_content)),
      $._line_end,
    ),
    fixed_width_content: _ => token.immediate(/[^\r\n]+/),
    horizontal_rule: $ => seq($.horizontal_rule_marker, $._line_end),

    list: $ => prec.right(repeat1($.list_item)),

    list_item: $ => prec.right(seq(
      field('marker', choice(
        $.unordered_list_marker,
        $.ordered_list_marker,
      )),
      optional(field('counter', $.list_counter)),
      optional(field('checkbox', $.checkbox)),
      optional(field('tag', $.description_tag)),
      optional(field('content', $.list_item_content)),
      $._line_end,
    )),

    unordered_list_marker: _ => token(prec(
      PREC.structural,
      choice(
        /[ \t]*[-+][ \t]+/,
        /[ \t]+\*[ \t]+/,
      ),
    )),

    ordered_list_marker: _ => token(prec(
      PREC.structural,
      /[ \t]*[0-9]+[.)][ \t]+/,
    )),

    checkbox: _ => token(prec(PREC.headingMetadata, /\[[ Xx-]\][ \t]*/)),
    list_counter: _ => token(prec(PREC.headingMetadata, /\[@(?:[0-9]+|[A-Za-z])\][ \t]*/)),
    description_tag: _ => token(prec(PREC.inlineMarkup + 1, /[^\r\n]+[ \t]+::[ \t]+/)),
    list_item_content: $ => prec.right(repeat1($._inline)),

    table: $ => prec.right(repeat1(choice($.table_separator, $.table_row))),

    table_separator: $ => seq(
      token(prec(
        PREC.structural,
        /\|[ \t]*[-+]+(?:[ \t]*\|[ \t]*[-+]+)*[ \t]*\|?[ \t]*/,
      )),
      $._line_end,
    ),

    table_row: $ => prec.right(seq(
      $.table_pipe,
      optional($.table_cell),
      repeat(seq($.table_pipe, optional($.table_cell))),
      $._line_end,
    )),

    table_pipe: _ => token(prec(PREC.structural, '|')),
    table_cell: $ => prec.right(repeat1($._table_inline)),
    _table_inline: $ => choice(
      $._extended_inline,
      $.link,
      $.footnote_reference,
      $.timestamp_range,
      $.timestamp,
      $.bold,
      $.italic,
      $.underline,
      $.strikethrough,
      $.code,
      $.verbatim,
      $.whitespace,
      $.plain_text,
      $.table_symbol,
    ),
    table_symbol: _ => token(prec(PREC.fallback, /[*\/_+~=\[\]<>{@("]/)),

    quote_block: $ => prec.right(seq(
      field('begin', $.quote_block_begin),
      $._newline,
      repeat(choice($.quote_line, $.blank_line)),
      field('end', $.quote_block_end),
      $._line_end,
    )),

    quote_block_begin: _ => token(prec(
      PREC.structural,
      /#\+[Bb][Ee][Gg][Ii][Nn]_[Qq][Uu][Oo][Tt][Ee][ \t]*/,
    )),
    quote_block_end: _ => token(prec(
      PREC.structural,
      /#\+[Ee][Nn][Dd]_[Qq][Uu][Oo][Tt][Ee][ \t]*/,
    )),
    quote_line: $ => prec.right(seq(repeat1($._inline), $._line_end)),

    source_block: $ => prec.right(seq(
      field('begin', $.source_block_begin),
      $._newline,
      repeat(choice($.source_line, $.blank_line)),
      field('end', $.source_block_end),
      $._line_end,
    )),

    source_block_begin: $ => seq(
      alias($._source_block_begin_marker, $.block_keyword),
      optional(seq(
        $.whitespace,
        field('language', $.source_language),
      )),
      optional(seq(
        $.whitespace,
        field('arguments', $.block_arguments),
      )),
      optional($.whitespace),
    ),

    source_language: _ => token(prec(3, /[A-Za-z0-9_+.-]+/)),
    block_arguments: _ => token(prec(-1, /[^\r\n]+/)),

    source_line: $ => prec.right(seq(
      field('content', $.source_content),
      $._line_end,
    )),
    source_content: _ => token(prec(PREC.fallback, /[^\r\n]+/)),

    example_block: $ => delimitedBlock($, 'example', $.source_line),
    export_block: $ => delimitedBlock($, 'export', $.source_line),
    comment_block: $ => delimitedBlock($, 'comment', $.source_line),
    verse_block: $ => delimitedBlock($, 'verse', $.quote_line),
    center_block: $ => delimitedBlock($, 'center', $.quote_line),

    dynamic_block: $ => seq(
      field('begin', $.dynamic_block_begin), $._newline,
      repeat(choice($.table, $.list, $.paragraph, $.blank_line, $.keyword)),
      field('end', $.dynamic_block_end), $._line_end,
    ),

    footnote_definition: $ => prec.right(seq(
      field('marker', $.footnote_definition_marker),
      optional(field('content', $.footnote_definition_content)),
      $._line_end,
    )),
    footnote_definition_marker: _ => token(prec(
      PREC.structural,
      /\[fn:[A-Za-z0-9_-]+\][ \t]+/,
    )),
    footnote_definition_content: $ => prec.right(repeat1($._inline)),

    comment: $ => prec.right(seq(
      field('marker', $.comment_marker),
      optional(field('text', $.comment_text)),
      $._line_end,
    )),
    comment_marker: _ => token(prec(PREC.structural, choice(
      /#[ \t]+/,
      /#\+[Cc][Oo][Mm][Mm][Ee][Nn][Tt]:[ \t]*/,
    ))),
    comment_text: _ => token.immediate(/[^\r\n]+/),

    keyword: $ => prec.right(seq(
      field('name', $.keyword_name),
      optional($.whitespace),
      optional(field('value', $.keyword_value)),
      $._line_end,
    )),
    keyword_name: _ => token(prec(
      PREC.structural,
      /#\+[A-Za-z0-9_]+:/,
    )),
    keyword_value: _ => token.immediate(/[^\r\n]+/),

    paragraph: $ => prec.right(seq(
      repeat1($._inline),
      $._line_end,
    )),

    // ---------------------------------------------------------------------
    // Inline layer
    // ---------------------------------------------------------------------

    _inline: $ => choice(
      $._extended_inline,
      $.link,
      $.footnote_reference,
      $.timestamp_range,
      $.timestamp,
      $.bold,
      $.italic,
      $.underline,
      $.strikethrough,
      $.code,
      $.verbatim,
      $.whitespace,
      $.plain_text,
      $.inline_symbol,
    ),

    _extended_inline: $ => choice(
      $.statistics_cookie, $.target, $.radio_target, $.macro,
      $.export_snippet, $.angle_link, $.plain_link, $.inline_footnote,
    ),
    statistics_cookie: _ => token(prec(PREC.inlineMarkup, /\[(?:[0-9]*%|[0-9]*\/[0-9]*)\]/)),
    target: _ => token(prec(PREC.inlineMarkup, /<<[^<> \t\r\n](?:[^<>\r\n]*[^<> \t\r\n])?>>/)),
    radio_target: _ => token(prec(PREC.inlineMarkup, /<<<[^<> \t\r\n](?:[^<>\r\n]*[^<> \t\r\n])?>>>/)),
    macro: _ => token(prec(PREC.inlineMarkup, /\{\{\{[A-Za-z][A-Za-z0-9_-]*(?:\([^}\r\n]*\))?\}\}\}/)),
    export_snippet: _ => token(prec(PREC.inlineMarkup, /@@[A-Za-z0-9-]+:[^@\r\n]*@@/)),
    angle_link: _ => token(prec(PREC.inlineMarkup, /<[A-Za-z][A-Za-z0-9+.-]*:[^<>\r\n]+>/)),
    plain_link: _ => {
      // Consume the URL before its slashes/underscores can become emphasis.
      // Balanced parentheses belong to the URL; sentence punctuation does not.
      const character = /[^\s<>\[\]()|"]/;
      const endCharacter = /[^\s<>\[\]()|".,;:!?]/;
      const parentheses = seq('(', repeat(choice(
        character, seq('(', repeat(character), ')'),
      )), ')');
      return token(prec(PREC.inlineMarkup, seq(
        choice(
          seq(/[A-Za-z][A-Za-z0-9+.-]*/, '://'),
          /[Mm][Aa][Ii][Ll][Tt][Oo]:/,
        ),
        repeat(choice(character, parentheses)),
        choice(endCharacter, parentheses),
      )));
    },
    inline_footnote: _ => token(prec(PREC.inlineMarkup, /\[fn:[A-Za-z0-9_-]*:[^\[\]\r\n]*\]/)),

    link: $ => seq(
      '[[',
      field('target', $.link_target),
      choice(
        ']]',
        seq(
          '][',
          optional(field('description', $.link_description)),
          ']]',
        ),
      ),
    ),
    link_target: _ => token.immediate(/[^\]\r\n]+/),
    link_description: _ => token.immediate(/[^\]\r\n]+/),

    footnote_reference: $ => seq(
      '[fn:',
      field('label', $.footnote_label),
      token.immediate(']'),
    ),
    footnote_label: _ => token.immediate(/[A-Za-z0-9_-]+/),

    timestamp_range: $ => seq(
      field('start', $.timestamp),
      token.immediate('--'),
      field('end', $.timestamp),
    ),
    timestamp: $ => choice($.active_timestamp, $.inactive_timestamp),
    active_timestamp: _ => token(prec(
      PREC.inlineMarkup,
      /<[0-9]{4}-[0-9]{2}-[0-9]{2}(?:[ \t]+[^>\r\n]+)?>/,
    )),
    inactive_timestamp: _ => token(prec(
      PREC.inlineMarkup,
      /\[[0-9]{4}-[0-9]{2}-[0-9]{2}(?:[ \t]+[^\]\r\n]+)?\]/,
    )),

    bold: _ => token(prec(
      PREC.inlineMarkup,
      /\*[^ \t\r\n*](?:[^*\r\n]*[^ \t\r\n*])?\*/,
    )),
    italic: _ => token(prec(
      PREC.inlineMarkup,
      /\/[^ \t\r\n/](?:[^/\r\n]*[^ \t\r\n/])?\//,
    )),
    underline: _ => token(prec(
      PREC.inlineMarkup,
      /_[^ \t\r\n_](?:[^_\r\n]*[^ \t\r\n_])?_/, 
    )),
    strikethrough: _ => token(prec(
      PREC.inlineMarkup,
      /\+[^ \t\r\n+](?:[^+\r\n]*[^ \t\r\n+])?\+/,
    )),
    code: _ => token(prec(PREC.inlineMarkup, /~[^~\r\n]+~/)),
    verbatim: _ => token(prec(PREC.inlineMarkup, /=[^=\r\n]+=/)),

    whitespace: _ => /[ \t]+/,
    plain_text: _ => token(prec(
      PREC.fallback,
      /[^ \t\r\n*\/_+~=\[\]<>|{@("]+/,
    )),
    inline_symbol: _ => token(prec(PREC.fallback, /[*\/_+~=\[\]<>|{@("]/)),

    _line_end: $ => choice($._newline, $._eof),
    _newline: _ => /\r?\n/,
  },
});

function delimitedBlock($, name, line) {
  return seq(
    field('begin', $[`${name}_block_begin`]), $._newline,
    repeat(choice(line, $.blank_line)),
    field('end', $[`${name}_block_end`]), $._line_end,
  );
}
