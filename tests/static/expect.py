#!/usr/bin/env python3
"""Whether a reject fixture failed exactly as it says it must.

Taken from quire's tests/static/expect.py (quire#585), for the
fixtures of arith, array and process, which are packages of their own
(src/bin/<name>.bats) rather than
snippets put into a module. A reject fixture's `expect` names the proof or
check its source breaks:

    function <the function of <name>.bats the error is in>
    line <the line of <name>.bats patsopt reports it at>
    <patsopt's error, as it says it: its message after "error(N): " and
     the lines it adds (the case left out, the terms that differ, ...)>

and, when patsopt reports one mistake at more than one place (a linear
variable no longer available is reported where it is used and again where
its function ends), the same again for each place:

    line <n>
    <the error at that line>

`bats build` of the fixture must fail with exactly that: patsopt's errors
all in <name>.bats, each at the line of its group, in the function, in the
order given, and their text, line for line, that text. Nothing else fails.
A substring that another error could also hold is not enough. An expect
that is missing, empty or not in this form fails the fixture, so a
fixture cannot pass without saying what it breaks.

An error of bats's own that has a position ("error: template 'alloc' has
no implementation ... " and a line ` --> src/bin/<name>.bats: 191(line=5,
offs=11) -- ...`) is an error like patsopt's, its message the text after
"error: ". An "error:" of bats without a position is never expected.

patsopt numbers its variables as it goes (S2EVar(16274->...), S2EVar(5473),
handed$6116(-1), l$3885(9554)), so a change anywhere before the snippet
renumbers them: those numbers, and only those, are compared as "_".

usage: tests/static/expect.py <fixture dir> <bats build log>
"""
import glob
import os
import re
import sys

HEADER = re.compile(
    r'^(?P<path>\S+\.bats): \d+\(line=(?P<line>\d+), offs=\d+\) -- '
    r'\d+\(line=\d+, offs=\d+\): error\(\d+\): (?P<message>.*)$')
# bats's own error, its position on the next line
BATS_ERROR = re.compile(r'^error: (?P<message>.*)$')
BATS_WRAPPER = 'patsopt error:'
BATS_POSITION = re.compile(
    r'^\s*--> (?P<path>\S+\.bats): \d+\(line=(?P<line>\d+), offs=\d+\) -- ')
# What ends an error's added lines: patsopt's summary, its exit, bats's
# own lines
AFTER = re.compile(r'^(typechecking has failed|exit\(ATS\)|patsopt\(|error:|warning:|built |check |fetched |wrote |\S+\.bats: \d+\(line=\d+, offs=\d+\) -- \d+\(line=\d+, offs=\d+\): warning)')
# (a warning of patsopt's with a position ends an error's lines too: it
# holds the machine's path and is not part of the error)
DECLARATION = re.compile(
    r'^(?:fn|fun|fnx|prfn|prfun|implement|val|var|and)\s+'
    r'(?:\{[^}]*\}\s*)*(?P<name>[A-Za-z_][A-Za-z0-9_]*)')


NUMBERS = [
    (re.compile(r'S2EVar\(\d+->'), 'S2EVar(_->'),
    (re.compile(r'S2EVar\(\d+\)'), 'S2EVar(_)'),
    # a dynamic variable: [handed$6116(-1)], a static one: l$3885(9554),
    # v$9365$9366(15573)
    (re.compile(r'\$\d+(?:\$\d+)*(?:\(-?\d+\))?'), '$_'),
    # a static variable: S2Evar(count(11804)); a constant, S2Eintinf(2),
    # keeps its number
    (re.compile(r'S2Evar\(([A-Za-z_][A-Za-z0-9_]*)\(\d+\)\)'), r'S2Evar(\1(_))'),
    # a static variable an existential binds: S2Eexi(out_cells_after(14593); ;
    # S2Eexi(chaining(14594); ...); its name is kept and compared
    (re.compile(r'S2Eexi\(([A-Za-z_][A-Za-z0-9_]*)\(\d+\)'), r'S2Eexi(\1(_)'),
]


def unnumbered(text):
    """text with patsopt's variable numbers as "_"."""
    for pattern, replacement in NUMBERS:
        text = pattern.sub(replacement, text)
    return text


def errors(log):
    """The errors in the log: (path or None, line, text lines)."""
    found = []
    current = None
    pending = None  # a bats error waiting for its position
    for line in log.splitlines():
        header = HEADER.match(line)
        position = BATS_POSITION.match(line)
        bats = BATS_ERROR.match(line)
        if header:
            if pending is not None:
                found.append((None, 0, [pending]))
                pending = None
            current = (header['path'], int(header['line']), [header['message']])
            found.append(current)
        elif position and pending is not None:
            found.append((position['path'], int(position['line']), [pending]))
            pending = None
            current = None
        elif bats and bats['message'] != BATS_WRAPPER:
            if pending is not None:
                found.append((None, 0, [pending]))
            pending = bats['message']
            current = None
        elif current is not None and not AFTER.match(line) and line.strip():
            current[2].append(line)
        else:
            current = None
    if pending is not None:
        found.append((None, 0, [pending]))
    return found


def enclosing(source_lines, line):
    """The name of the source's top-level declaration that holds line
    (1-based), or None."""
    name = None
    for text in source_lines[:line]:
        declared = DECLARATION.match(text)
        if declared:
            name = declared['name']
    return name


def parse(expect):
    """(function, [(line, text lines)]) of an expect, or a problem."""
    if len(expect) < 3 or not expect[0].startswith('function ') or not expect[1].startswith('line '):
        return None, 'its expect is not "function <name>", "line <n>", then the error'
    function = expect[0][len('function '):].strip()
    if not function:
        return None, 'its expect names no function'
    groups = []
    for text in expect[1:]:
        at = re.fullmatch(r'line (\d+)', text)
        if at:
            groups.append((int(at[1]), []))
        else:
            groups[-1][1].append(text)
    for line, text in groups:
        if not text or not any(x.strip() for x in text):
            return None, f'its expect gives no error for line {line}'
    return (function, groups), None


def main(fixture, log_path):
    try:
        with open(os.path.join(fixture, 'expect')) as expect_file:
            expect = expect_file.read().rstrip('\n').split('\n')
    except OSError:
        return 'it has no expect'
    if not ''.join(expect).strip():
        return 'its expect is empty'
    parsed, problem = parse(expect)
    if problem:
        return problem
    function, groups = parsed
    sources = glob.glob(os.path.join(fixture, 'src', 'bin', '*.bats'))
    if len(sources) != 1:
        return 'it does not have exactly one src/bin/*.bats'
    module = 'src/bin/' + os.path.basename(sources[0])
    with open(sources[0]) as source_file:
        source = source_file.read().split('\n')
    with open(log_path, errors='replace') as log_file:
        log = log_file.read()
    for line, _ in groups:
        if enclosing(source, line) != function:
            return f'line {line} of its source is not in {function}'
    found = errors(log)
    if not found:
        return 'no error of patsopt\'s'
    got = []
    lines = []
    for path, at, text in found:
        if path is None:
            return f'an error has no position: {text[0]}'
        if not (path == module or path.endswith('/' + module)):
            return f'an error is in {path}, not {module}: {text[0]}'
        got += [f'line {at}'] + text if not lines or lines[-1] != at else text
        lines.append(at)
    want = []
    for line, text in groups:
        want += [f'line {line}'] + text
    if [unnumbered(x) for x in got] != [unnumbered(x) for x in want]:
        return 'its error is not the one expected:\n' + '\n'.join(got)
    return None


if __name__ == '__main__':
    problem = main(sys.argv[1], sys.argv[2])
    if problem:
        print(problem)
        sys.exit(1)
