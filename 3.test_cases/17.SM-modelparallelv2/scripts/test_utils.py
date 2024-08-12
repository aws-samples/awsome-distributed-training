"""Unit test for utils.py."""

from typing import Any, Dict, Optional
import unittest

import numpy as np
from parameterized import parameterized
import utils


class TestUtils(unittest.TestCase):
    """Unit test for the Utils class."""

    @parameterized.expand((
        (
            None,
            None,
        ),
        (
            np.array([]),
            None,
        ),
        (
            np.array([1.,]),
            {
                "data": np.array([1.,]),
                "data_sorted": np.array([1.,]),
                "len": 1,
                # Stats.
                "max": 1.,
                "mean": 1.,
                "median": 1.,
                "min": 1.,
                "std": 0.,
            },
        ),
        (
            np.array([9., 1.]),
            {
                "data": np.array([9., 1.]),
                "data_sorted": np.array([1., 9.]),
                "len": 2,
                # Stats.
                "max": 9.,
                "max2": 1.,
                "mean": 5.,
                "median": 5.,
                "min": 1.,
                "min2": 9.,
                "std": 4,
            },
        ),
        (
            np.array([3., 1., 8.]),
            {
                "data": np.array([3., 1., 8.]),
                "data_sorted": np.array([1., 3., 8.]),
                "len": 3,
                # Stats.
                "max": 8.,
                "max2": 3.,
                "max3": 1.,
                "mean": 4.,
                "median": 3.,
                "min": 1.,
                "min2": 3.,
                "min3": 8.,
                "std": 2.943920288775949,
            },
        ),
        # Actual NCCL tests E2E.
        (
            utils.parse_nccl_test_log("./scripts/FILE-DOES-NOT-EXIST.txt"),
            None,
        ),
        (
            utils.parse_nccl_test_log("./scripts/nccl_test_ns02.txt"),
            {
                "data": np.array([29.8872, 28.9057]),
                "data_sorted": np.array([28.9057, 29.8872]),
                "len": 2,
                # Stats.
                "max": 29.8872,
                "max2": 28.9057,
                "mean": 29.39645,
                "median": 29.39645,
                "min": 28.9057,
                "min2": 29.8872,
                "std": 0.49075000000000024,
            },
        ),
        (
            utils.parse_nccl_test_log("./scripts/nccl_test_ns04.txt"),
            {
                "data": np.array([3.68419, 3.67744, 3.67917, 3.6783]),
                "data_sorted": np.array([3.67744, 3.6783, 3.67917, 3.68419]),
                "len": 4,
                # Stats.
                "max": 3.68419,
                "max2": 3.67917,
                "max3": 3.6783,
                "max4": 3.67744,
                "mean": 3.6797750000000002,
                "median": 3.678735,
                "min": 3.67744,
                "min2": 3.6783,
                "min3": 3.67917,
                "min4": 3.68419,
                "std": 0.002621359380169051,
            },
        ),
    ))
    def test_get_nccl_test_report(
        self,
        bandwidth: Optional[np.ndarray],
        expected_report: Optional[Dict[str, Any]],
    ):
        """Unit test for get_nccl_test_report."""
        report = utils.get_nccl_test_report(bandwidth)

        if expected_report is None:
            self.assertIsNone(report)
            return

        for key in ("data", "data_sorted"):
            np.testing.assert_allclose(report.pop(key), expected_report.pop(key))
        self.assertEqual(report, expected_report)


if __name__ == "__main__":
    unittest.main()
