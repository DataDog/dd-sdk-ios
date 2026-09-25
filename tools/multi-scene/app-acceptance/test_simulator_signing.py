"""Fail closed when the frozen build command no longer has the reviewed shape."""
import ast
import unittest

from simulator_signing import enable_signing


class SimulatorSigningControls(unittest.TestCase):
    def test_only_the_signing_flag_changes(self):
        before = "def main(arm):\n    guard(arm)\n    cmd=['xcodebuild','CODE_SIGNING_ALLOWED=NO']\n    execute(cmd)\n    verify()\n"
        actual = enable_signing(before)
        expected = ast.parse(before.replace('CODE_SIGNING_ALLOWED=NO', 'CODE_SIGNING_ALLOWED=YES'))
        self.assertEqual(ast.dump(actual), ast.dump(expected))

    def test_missing_duplicate_or_foreign_entry_fails_before_build(self):
        for source in ["def main(arm):\n    pass\n",
                       "def main(arm):\n    cmd=['CODE_SIGNING_ALLOWED=NO','CODE_SIGNING_ALLOWED=NO']\n",
                       "def other(arm):\n    cmd=['CODE_SIGNING_ALLOWED=NO']\n"]:
            with self.subTest(source=source), self.assertRaises(AssertionError):
                enable_signing(source)


if __name__ == '__main__':
    unittest.main()
