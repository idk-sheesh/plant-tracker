from __future__ import annotations

import unittest

from cloud_api.app import _calculate_vpd


class VpdReferenceTest(unittest.TestCase):
    def test_air_vpd_fao56_reference_vectors(self) -> None:
        cases = [
            (-10, 95, 0.014285549),
            (15, 80, 0.341069246),
            (25, 50, 1.583888859),
            (35, 25, 4.217010929),
            (20, 99.5, 0.011691406),
            (20, 0, 2.338281271),
            (20, 100, 0.0),
            (40, 5, 7.006832913),
        ]
        for temperature, humidity, expected in cases:
            with self.subTest(temperature=temperature, humidity=humidity):
                self.assertAlmostEqual(
                    _calculate_vpd(temperature, humidity), expected, delta=1e-8
                )
