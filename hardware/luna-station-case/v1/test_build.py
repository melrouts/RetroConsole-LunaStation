import unittest

import trimesh

from build import check_print_layout


def plate_scene(plate):
    shapes = {
        "lid": (("lid", (188, 120), (128, 90)),
                ("text", (58, 25), (100, 90)),
                ("accent", (175.6, 107.6), (128, 90))),
        "base": (("bottom", (188, 120), (128, 70)),
                 ("base_text", (58.2, 40.9), (94, 77)),
                 ("base_accent", (175.6, 107.6), (128, 70)),
                 ("bridge", (57.6, 79.2), (60, 196))),
        "fit_test": (("fit_test", (198, 120), (128, 128)),),
    }
    scene = trimesh.Scene()
    for name, (width, depth), (x, y) in shapes[plate]:
        mesh = trimesh.creation.box(extents=(width, depth, 1))
        mesh.apply_translation((x, y, 0.5))
        scene.add_geometry(mesh, node_name=name, geom_name=name)
    return scene


class PrintLayoutTests(unittest.TestCase):
    def test_split_plates_fit(self):
        for plate in ("lid", "base", "fit_test"):
            with self.subTest(plate=plate):
                result = check_print_layout(plate_scene(plate), plate)
                self.assertEqual(result["margin_mm"], 6)

    def test_original_lid_placement_is_rejected(self):
        scene = plate_scene("lid")
        scene.apply_translation((-28, -26, 0))
        with self.assertRaises(RuntimeError):
            check_print_layout(scene, "lid")

    def test_exclusion_inside_bed_is_rejected(self):
        scene = plate_scene("lid")
        scene.apply_translation((-28, -18, 0))
        with self.assertRaisesRegex(RuntimeError, "exclusion area"):
            check_print_layout(scene, "lid")

    def test_brim_over_bed_edge_is_rejected(self):
        scene = plate_scene("lid")
        scene.apply_translation((30, 0, 0))
        with self.assertRaisesRegex(RuntimeError, "bed with 6 mm margin"):
            check_print_layout(scene, "lid")

    def test_tower_space_is_kept_clear(self):
        scene = plate_scene("lid")
        scene.apply_translation((0, 40, 0))
        with self.assertRaisesRegex(RuntimeError, "tower space"):
            check_print_layout(scene, "lid")

    def test_base_brims_do_not_overlap(self):
        scene = plate_scene("base")
        scene.geometry["bridge"].apply_translation((0, -15, 0))
        with self.assertRaisesRegex(RuntimeError, "brim envelopes overlap"):
            check_print_layout(scene, "base")

    def test_base_tower_space_is_kept_clear(self):
        scene = plate_scene("base")
        scene.geometry["bridge"].apply_translation((70, 0, 0))
        with self.assertRaisesRegex(RuntimeError, "tower space"):
            check_print_layout(scene, "base")

    def test_fit_test_stays_clear_of_exclusion(self):
        scene = plate_scene("fit_test")
        scene.apply_translation((-19, -58, 0))
        with self.assertRaisesRegex(RuntimeError, "exclusion area"):
            check_print_layout(scene, "fit_test")

    def test_missing_inlay_is_rejected(self):
        scene = plate_scene("lid")
        scene.delete_geometry("text")
        with self.assertRaisesRegex(RuntimeError, "incomplete"):
            check_print_layout(scene, "lid")

    def test_inlay_must_start_on_bed(self):
        scene = plate_scene("lid")
        scene.geometry["text"].apply_translation((0, 0, 1))
        with self.assertRaisesRegex(RuntimeError, "print orientation"):
            check_print_layout(scene, "lid")


if __name__ == "__main__":
    unittest.main()
