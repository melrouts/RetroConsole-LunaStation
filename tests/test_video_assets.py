import importlib.util
import math
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("video_assets", ROOT / "scripts/video_assets.py")
assets = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(assets)


class VideoAssetsTest(unittest.TestCase):
    def test_every_rotation_rotates_hull_window_and_flame_together(self):
        atlas = assets.sprite_atlas()
        self.assertEqual(len(atlas), 32*32*32)
        areas = []
        for angle in range(32):
            image = atlas[angle*1024:(angle+1)*1024]
            areas.append(sum(pixel in (1, 2) for pixel in image))
            for value, expected_distance in ((2, -4.5), (3, 8)):
                points = [(index % 32 - 16, index // 32 - 16)
                          for index, pixel in enumerate(image) if pixel == value]
                self.assertGreater(len(points), 5)
                cx = sum(x for x, _ in points)/len(points)
                cy = sum(y for _, y in points)/len(points)
                sine, cosine = math.sin(angle*math.tau/32), math.cos(angle*math.tau/32)
                self.assertAlmostEqual(cx*cosine + cy*sine, 0, delta=0.8)
                self.assertAlmostEqual(-cx*sine + cy*cosine, expected_distance, delta=1.5)
            self.assertTrue(all(pixel == 0 for pixel in image[:32] + image[-32:]))
        self.assertLess(max(areas) - min(areas), 25)

    def test_planet_has_transparent_surround_ocean_continents_clouds_and_shadow(self):
        image = assets.earth_art()
        self.assertEqual(len(image), 128*128)
        self.assertEqual(image[0], 0)
        self.assertEqual(image[-1], 0)
        for material in range(13):
            self.assertGreater(image.count(material), 20, material)
        self.assertEqual(image, assets.earth_art())


if __name__ == "__main__":
    unittest.main()
