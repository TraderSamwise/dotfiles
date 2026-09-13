const vscode = require('vscode');

// State for indent-aware vertical navigation.
let pending = null; // { line } empty line temporarily filled with indent whitespace
let navGoal = null; // remembered visual column, preserved across empty-line detours
let isAdjusting = false; // suppress our own selection changes from ending the sequence
let busy = false; // re-entrancy guard against key-repeat races

const K = vscode.TextEditorSelectionChangeKind;

function leadingWhitespace(text) {
  const m = text.match(/^[\t ]*/);
  return m ? m[0] : '';
}

function indentUnit(editor) {
  const o = editor.options;
  if (o.insertSpaces) return ' '.repeat(typeof o.tabSize === 'number' ? o.tabSize : 4);
  return '\t';
}

function stripStringsAndComments(line) {
  return line
    .replace(/\/\/.*$/, '')
    .replace(/'(?:\\.|[^'\\])*'/g, "''")
    .replace(/"(?:\\.|[^"\\])*"/g, '""')
    .replace(/`(?:\\.|[^`\\])*`/g, '``');
}

function netBrackets(line) {
  let n = 0;
  for (const ch of stripStringsAndComments(line)) {
    if (ch === '{' || ch === '(' || ch === '[') n++;
    else if (ch === '}' || ch === ')' || ch === ']') n--;
  }
  return n;
}

function stripPy(line) {
  return line
    .replace(/'(?:\\.|[^'\\])*'/g, "''")
    .replace(/"(?:\\.|[^"\\])*"/g, '""')
    .replace(/#.*$/, '');
}

// Python indent for a blank line: colon opens a block, brackets/backslash/trailing
// operators continue, return/pass/etc dedent, otherwise hold the current level.
function computeIndentPython(editor, lineNumber) {
  const doc = editor.document;
  let p = -1;
  for (let i = lineNumber - 1; i >= 0; i--) {
    if (doc.lineAt(i).text.trim().length) { p = i; break; }
  }
  if (p < 0) return '';
  const prevText = doc.lineAt(p).text;
  const unit = indentUnit(editor);
  if (prevText.trim().startsWith('#')) return leadingWhitespace(prevText);
  const s = stripPy(prevText).trimEnd();
  if (/[\{\(\[]$/.test(s)) return leadingWhitespace(prevText) + unit;
  let b = p;
  while (b - 1 >= 0 && doc.lineAt(b - 1).text.trim().length) b--;
  let depth = 0;
  for (let i = b; i <= p; i++) {
    for (const ch of stripPy(doc.lineAt(i).text)) {
      if (ch === '{' || ch === '(' || ch === '[') depth++;
      else if (ch === '}' || ch === ')' || ch === ']') depth--;
    }
  }
  if (depth > 0) return leadingWhitespace(prevText); // inside an open bracket
  if (s.endsWith(':') || s.endsWith('\\')) return leadingWhitespace(prevText) + unit;
  if (/^(return|pass|break|continue|raise)\b/.test(s.trimStart())) {
    const cur = leadingWhitespace(prevText);
    return cur.length >= unit.length ? cur.slice(0, cur.length - unit.length) : '';
  }
  if (/[-+*/%<>=&|^]$/.test(s)) return leadingWhitespace(prevText) + unit; // continued expression
  return leadingWhitespace(prevText);
}

function computeIndent(editor, lineNumber) {
  if (editor.document.languageId === 'python') return computeIndentPython(editor, lineNumber);
  return computeIndentCLike(editor, lineNumber);
}

// Indent for a blank line: aligned to siblings when inside an open bracket,
// else the continuation indent if the statement above is still running, else
// the base indent of the completed statement.
function computeIndentCLike(editor, lineNumber) {
  const doc = editor.document;
  let p = -1;
  for (let i = lineNumber - 1; i >= 0; i--) {
    if (doc.lineAt(i).text.trim().length) { p = i; break; }
  }
  if (p < 0) return '';
  const prevText = doc.lineAt(p).text;
  const prevTrim = prevText.trim();
  // Block-comment line (`* ...`, `*/`): align to the `/*` opener, not to inner punctuation.
  if (/^\*/.test(prevTrim)) {
    let c = p;
    while (c > 0 && !doc.lineAt(c).text.includes('/*')) c--;
    return leadingWhitespace(doc.lineAt(c).text);
  }
  if (prevTrim.startsWith('//')) return leadingWhitespace(prevText);
  const prevStripped = stripStringsAndComments(prevText).trimEnd();
  // A line ending in an opener (incl. `} else {`, `} catch {`) always indents one level in.
  if (/[\{\(\[]$/.test(prevStripped)) return leadingWhitespace(prevText) + indentUnit(editor);
  let b = p;
  while (b - 1 >= 0 && doc.lineAt(b - 1).text.trim().length) b--;
  let depth = 0;
  for (let i = b; i <= p; i++) depth += netBrackets(doc.lineAt(i).text);
  if (depth > 0) return leadingWhitespace(prevText); // inside an open bracket: align to sibling
  // A closed block `}` stays at the brace's own level.
  if (prevStripped.endsWith('}')) return leadingWhitespace(prevText);
  // A completed statement `;` dedents to where the statement actually started,
  // walking back over continuation lines (chains, operator-continued lines).
  if (prevStripped.endsWith(';')) {
    let s = p;
    while (s > 0) {
      const aboveStripped = stripStringsAndComments(doc.lineAt(s - 1).text).trimEnd();
      if (!aboveStripped.length || /[;}]$/.test(aboveStripped)) break;
      const curIsCont = /^[.?:)\]]/.test(doc.lineAt(s).text.trim());
      const aboveOpensCont = /(=>|&&|\|\||[-+*/%?:,<>=&|^([{])$/.test(aboveStripped);
      if (!curIsCont && !aboveOpensCont) break;
      s--;
    }
    return leadingWhitespace(doc.lineAt(s).text);
  }
  // Unterminated: trailing operator -> indent in; otherwise keep the continuation level.
  // (`*` and `/` excluded: almost always comment syntax, not multiply/divide.)
  const continues = /(=>|&&|\|\||[-+%?:.,<>=&|^])$/.test(prevStripped);
  return leadingWhitespace(prevText) + (continues ? indentUnit(editor) : '');
}

async function removeIndentFrom(editor, line) {
  if (!editor || line < 0 || line >= editor.document.lineCount) return;
  const text = editor.document.lineAt(line).text;
  if (text.length && text.trim().length === 0) {
    await editor.edit(
      (b) => b.delete(new vscode.Range(line, 0, line, text.length)),
      { undoStopBefore: false, undoStopAfter: false }
    );
  }
}

function endSequence(editor) {
  const p = pending;
  pending = null;
  navGoal = null;
  if (p) {
    isAdjusting = true;
    Promise.resolve(removeIndentFrom(editor, p.line)).finally(() => { isAdjusting = false; });
  }
}

async function verticalIndentAware(direction) {
  const editor = vscode.window.activeTextEditor;
  if (!editor) return;
  const move = direction === 'up' ? 'cursorUp' : 'cursorDown';
  if (busy || editor.selections.length !== 1) {
    pending = null; navGoal = null;
    await vscode.commands.executeCommand(move);
    return;
  }
  busy = true;
  isAdjusting = true;
  try {
    if (navGoal === null) navGoal = editor.selection.active.character;
    if (pending) { await removeIndentFrom(editor, pending.line); pending = null; }
    await vscode.commands.executeCommand(move);

    const pos = editor.selection.active;
    const text = editor.document.lineAt(pos.line).text;
    if (text.length === 0) {
      const indent = computeIndent(editor, pos.line);
      if (indent) {
        await editor.edit(
          (b) => b.insert(new vscode.Position(pos.line, 0), indent),
          { undoStopBefore: false, undoStopAfter: false }
        );
        const end = new vscode.Position(pos.line, indent.length);
        editor.selection = new vscode.Selection(end, end);
        pending = { line: pos.line };
      }
    } else {
      const col = Math.min(navGoal, text.length);
      const at = new vscode.Position(pos.line, col);
      editor.selection = new vscode.Selection(at, at);
    }
  } finally {
    isAdjusting = false;
    busy = false;
  }
}

// Insert a newline, then indent the new line with our own (continuation-aware)
// logic instead of VS Code's native on-Enter auto-indent.
async function smartEnter() {
  const editor = vscode.window.activeTextEditor;
  if (!editor) { await vscode.commands.executeCommand('default:type', { text: '\n' }); return; }
  pending = null; navGoal = null;
  if (editor.selections.length !== 1) {
    await vscode.commands.executeCommand('default:type', { text: '\n' });
    return;
  }
  // Python only: Enter on a blank line respects the caret's current indent (a
  // manual dedent means "close the block") instead of re-indenting to the body
  // above. JS/TS keeps the normal continuation-aware behavior.
  const origPos = editor.selection.active;
  const origText = editor.document.lineAt(origPos.line).text;
  const preserveBlank = editor.document.languageId === 'python' && origText.trim().length === 0;
  const keepIndent = origText.slice(0, origPos.character);
  isAdjusting = true;
  try {
    await vscode.commands.executeCommand('default:type', { text: '\n' });
    const pos = editor.selection.active;
    const lineText = editor.document.lineAt(pos.line).text;
    const desired = preserveBlank ? keepIndent : computeIndent(editor, pos.line);
    const currentWs = leadingWhitespace(lineText);
    if (currentWs !== desired) {
      await editor.edit(
        (b) => b.replace(new vscode.Range(pos.line, 0, pos.line, currentWs.length), desired),
        { undoStopBefore: false, undoStopAfter: false }
      );
    }
    const at = new vscode.Position(pos.line, desired.length);
    editor.selection = new vscode.Selection(at, at);
  } finally {
    isAdjusting = false;
  }
}

// On a blank line, Tab snaps to the computed (nearest-continuation) indent for
// fast recovery after a manual dedent; otherwise falls through to normal Tab.
async function smartTab() {
  const editor = vscode.window.activeTextEditor;
  if (!editor || editor.selections.length !== 1 || !editor.selection.isEmpty) {
    return vscode.commands.executeCommand('tab');
  }
  const pos = editor.selection.active;
  const line = editor.document.lineAt(pos.line);
  if (line.text.trim().length === 0) {
    const target = computeIndent(editor, pos.line);
    if (target.length > pos.character) {
      isAdjusting = true;
      try {
        await editor.edit(
          (b) => b.replace(new vscode.Range(pos.line, 0, pos.line, line.text.length), target),
          { undoStopBefore: false, undoStopAfter: false }
        );
        const at = new vscode.Position(pos.line, target.length);
        editor.selection = new vscode.Selection(at, at);
      } finally { isAdjusting = false; }
      return;
    }
  }
  return vscode.commands.executeCommand('tab');
}

function activate(context) {
  context.subscriptions.push(
    vscode.commands.registerCommand('sam.smartEnter', smartEnter),
    vscode.commands.registerCommand('sam.smartTab', smartTab),
    vscode.commands.registerCommand('sam.commentAndMoveDownUnlessEmpty', async () => {
      const editor = vscode.window.activeTextEditor;
      if (!editor) return;
      const wasEmpty = editor.document
        .lineAt(editor.selection.active.line)
        .isEmptyOrWhitespace;
      await vscode.commands.executeCommand('editor.action.commentLine');
      if (!wasEmpty) await verticalIndentAware('down');
    }),
    vscode.commands.registerCommand('sam.cursorUpIndentAware', () => verticalIndentAware('up')),
    vscode.commands.registerCommand('sam.cursorDownIndentAware', () => verticalIndentAware('down')),
    vscode.window.onDidChangeTextEditorSelection((e) => {
      if (isAdjusting) return;
      if (e.kind === K.Keyboard || e.kind === K.Mouse) endSequence(e.textEditor);
    }),
    vscode.window.onDidChangeActiveTextEditor(() => { pending = null; navGoal = null; }),
    // Format-on-save strips whitespace from blank lines; if the caret is left on
    // a now-empty line, re-apply the indent so typing continues at the right spot.
    vscode.workspace.onDidSaveTextDocument((doc) => {
      if (doc.languageId !== 'python') return;
      const editor = vscode.window.activeTextEditor;
      if (!editor || editor.document !== doc) return;
      if (editor.selections.length !== 1 || !editor.selection.isEmpty) return;
      const pos = editor.selection.active;
      if (editor.document.lineAt(pos.line).text.length !== 0) return;
      const indent = computeIndent(editor, pos.line);
      if (!indent) return;
      isAdjusting = true;
      editor
        .edit((b) => b.insert(new vscode.Position(pos.line, 0), indent), { undoStopBefore: false, undoStopAfter: false })
        .then(() => {
          const end = new vscode.Position(pos.line, indent.length);
          editor.selection = new vscode.Selection(end, end);
          pending = { line: pos.line };
        })
        .finally(() => { isAdjusting = false; });
    })
  );
}

function deactivate() {}

module.exports = { activate, deactivate };
