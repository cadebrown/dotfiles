import unittest

from merge_ranges import merge_ranges


class MergeRangesTests(unittest.TestCase):
    def test_overlap(self):
        self.assertEqual(merge_ranges([(1, 4), (3, 7)]), [(1, 7)])

    def test_disjoint(self):
        self.assertEqual(merge_ranges([(1, 4), (8, 9)]), [(1, 4), (8, 9)])


if __name__ == "__main__":
    unittest.main()
