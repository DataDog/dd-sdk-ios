import hashlib
import unittest
from capture_product import archive_members


def member(name, payload):
    header = (name + '/').ljust(16) + '0'.ljust(12) + '0'.ljust(6) + '0'.ljust(6) + '644'.ljust(8) + str(len(payload)).ljust(10) + '`\n'
    return header.encode() + payload + (b'\n' if len(payload) % 2 else b'')


class ArchiveMembershipTests(unittest.TestCase):
    def setUp(self):
        self.raw = b'!<arch>\n' + member('__.SYMDEF', b'index') + member('Source.o', b'object bytes')

    def test_actual_member_bytes_define_fingerprint(self):
        members, symbol = archive_members(self.raw)
        self.assertEqual(members, {'Source.o': hashlib.sha256(b'object bytes').hexdigest()})
        self.assertEqual(symbol['name'], '__.SYMDEF')
        changed, _ = archive_members(self.raw.replace(b'object bytes', b'foreignbytes'))
        self.assertNotEqual(changed, members)

    def test_duplicate_foreign_truncated_or_ambiguous_members_fail(self):
        invalid = [self.raw + member('Source.o', b'duplicate'), self.raw + member('Foreign.a', b'x'),
                   self.raw + member('../Source.o', b'x'), self.raw[:-1], self.raw[:30],
                   self.raw.replace(b'`\n', b'XX', 1), self.raw + member('__.SYMDEF', b'duplicate'),
                   b'!<arch>\n' + member('Source.o', b'no index')]
        for value in invalid:
            with self.subTest(length=len(value)), self.assertRaises((AssertionError, ValueError)):
                archive_members(value)


if __name__ == '__main__':unittest.main()
