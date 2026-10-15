const { execFileSync } = require('node:child_process');
const { readFileSync, writeFileSync, rmSync } = require('node:fs');

// Use the package's pinned CLI even when a different version is on PATH.
execFileSync(process.execPath, [require.resolve('tree-sitter-cli/cli.js'), 'generate', '--abi', '15'], {
  stdio: 'inherit',
});
rmSync('src/node-types.json', { force: true });
const grammar = JSON.parse(readFileSync('src/grammar.json', 'utf8'));
// Schema annotations and empty optional sections are not generator inputs.
delete grammar.$schema;
for (const key of Object.keys(grammar)) {
  const value = grammar[key];
  if (value && typeof value === 'object' && Object.keys(value).length === 0) delete grammar[key];
}
writeFileSync('src/grammar.json', JSON.stringify(grammar, null, 2) + '\n');
