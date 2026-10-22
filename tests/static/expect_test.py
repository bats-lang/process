#!/usr/bin/env python3
"""Tests of expect.py (quire#585): a reject fixture passes only when it
failed exactly as its expect says. Each case below is a fixture and a log
of `bats build`, and expect.py must pass the good one and fail every other:
no expect, an empty one, one not in the form, a wrong error, a wrong line,
a wrong function, a second error, an error in another file, and an error
of bats's without a position.
"""
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import expect  # noqa: E402

SOURCE = """#use array as A

fn first (): void = ()

fn second {l:agz} (x: int): void =
  ()

implement main0 () = ()
"""
UNSOLVED = ('/w/src/bin/main.bats: 100(line=6, offs=3) -- 101(line=6, offs=4): '
            'error(3): unsolved constraint: C3NSTRprop(C3TKmain(); S2Eeqeq(S2Eintinf(1); S2Eintinf(0)))\n')
TAIL = ('typechecking has failed: there are some unsolved constraints: please inspect the above reported error message(s) for information.\n'
        'exit(ATS): uncaught exception: FatalErrorExn(1025)\n')
LOG = 'fetched array v1\nerror: patsopt error:\n' + UNSOLVED + TAIL
GOOD = ('function second\nline 6\n'
        'unsolved constraint: C3NSTRprop(C3TKmain(); S2Eeqeq(S2Eintinf(1); S2Eintinf(0)))\n')


class Expect(unittest.TestCase):
    def run_case(self, expected, log, source=SOURCE):
        with tempfile.TemporaryDirectory() as tmp:
            os.makedirs(os.path.join(tmp, 'src', 'bin'))
            with open(os.path.join(tmp, 'src', 'bin', 'main.bats'), 'w') as f:
                f.write(source)
            if expected is not None:
                with open(os.path.join(tmp, 'expect'), 'w') as f:
                    f.write(expected)
            with open(os.path.join(tmp, 'log'), 'w') as f:
                f.write(log)
            return expect.main(tmp, os.path.join(tmp, 'log'))

    def test_good(self):
        self.assertIsNone(self.run_case(GOOD, LOG))

    def test_numbers_are_not_compared(self):
        log = LOG.replace('S2Eintinf(1); S2Eintinf(0)', 'S2Evar(l$3885(9554)); S2Evar(l$3888(9557))')
        want = GOOD.replace('S2Eintinf(1); S2Eintinf(0)', 'S2Evar(l$1(2)); S2Evar(l$3(4))')
        self.assertIsNone(self.run_case(want, log))

    def test_existential_numbers_are_not_compared(self):
        # patsopt numbers the variables an existential binds (S2Eexi(c(14593)))
        log = LOG.replace('S2Eeqeq(S2Eintinf(1); S2Eintinf(0))', 'S2Eexi(c(14593); ; S2Eeqeq(S2Eintinf(1); S2Eintinf(0)))')
        want = GOOD.replace('S2Eeqeq(S2Eintinf(1); S2Eintinf(0))', 'S2Eexi(c(14465); ; S2Eeqeq(S2Eintinf(1); S2Eintinf(0)))')
        self.assertIsNone(self.run_case(want, log))

    def test_existential_name_is_compared(self):
        log = LOG.replace('S2Eeqeq(S2Eintinf(1); S2Eintinf(0))', 'S2Eexi(c(14593); ; S2Eeqeq(S2Eintinf(1); S2Eintinf(0)))')
        want = GOOD.replace('S2Eeqeq(S2Eintinf(1); S2Eintinf(0))', 'S2Eexi(d(14465); ; S2Eeqeq(S2Eintinf(1); S2Eintinf(0)))')
        self.assertIn('not the one expected', self.run_case(want, log))

    def test_no_expect(self):
        self.assertEqual(self.run_case(None, LOG), 'it has no expect')

    def test_empty_expect(self):
        self.assertEqual(self.run_case('', LOG), 'its expect is empty')
        self.assertEqual(self.run_case('\n\n', LOG), 'its expect is empty')

    def test_old_substring_expect(self):
        # what the fixtures held before: a substring any unsolved constraint has
        self.assertIn('not "function', self.run_case('unsolved constraint\n', LOG))

    def test_no_error_text(self):
        self.assertIsNotNone(self.run_case('function second\nline 6\n', LOG))
        self.assertIn('gives no error', self.run_case('function second\nline 6\nline 7\nx\n', LOG))

    def test_wrong_error(self):
        other = GOOD.replace('S2Eintinf(0)', 'S2Eintinf(2)')
        self.assertIn('not the one expected', self.run_case(other, LOG))

    def test_another_unsolved_constraint(self):
        log = LOG.replace('S2Eeqeq(S2Eintinf(1)', 'S2Eapp(S2Ecst(<); S2Eintinf(1)')
        self.assertIn('not the one expected', self.run_case(GOOD, log))

    def test_wrong_line(self):
        self.assertIn('not the one expected', self.run_case(GOOD.replace('line 6', 'line 5'), LOG))

    def test_wrong_function(self):
        self.assertEqual(self.run_case(GOOD.replace('second', 'first'), LOG),
                         'line 6 of its source is not in first')

    def test_second_error(self):
        log = LOG.replace(TAIL, UNSOLVED.replace('line=6', 'line=8') + TAIL)
        self.assertIsNotNone(self.run_case(GOOD, log))

    def test_other_file(self):
        log = LOG.replace('/w/src/bin/main.bats', '/w/src/lib.bats')
        self.assertIn('not src/bin/main.bats', self.run_case(GOOD, log))

    def test_no_error(self):
        self.assertEqual(self.run_case(GOOD, 'fetched array v1\n'), "no error of patsopt's")

    def test_bats_error_without_position(self):
        log = LOG.replace('error: patsopt error:', 'error: patsopt error:\nerror: lock does not match')
        self.assertIn('has no position', self.run_case(GOOD, log) or '')

    def test_bats_error_with_position(self):
        log = "error: template 'alloc' has no implementation\n --> src/bin/main.bats: 5(line=6, offs=1) -- 9(line=6, offs=5)\n"
        want = "function second\nline 6\ntemplate 'alloc' has no implementation\n"
        self.assertIsNone(self.run_case(want, log))
        self.assertIsNotNone(self.run_case(want.replace("'alloc'", "'free'"), log))


if __name__ == '__main__':
    unittest.main(verbosity=1)
