import sys
import tempfile
import unittest
from pathlib import Path

from fastapi import FastAPI
from fastapi.testclient import TestClient

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from range_static_files import RangeAwareStaticFiles


class RangeAwareStaticFilesTests(unittest.TestCase):
    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory()
        self.file_path = Path(self.temp_dir.name) / "sample.mp4"
        self.file_path.write_bytes(b"0123456789")

        app = FastAPI()
        app.mount("/media", RangeAwareStaticFiles(directory=self.temp_dir.name), name="media")
        self.client = TestClient(app)

    def tearDown(self):
        self.temp_dir.cleanup()

    def test_returns_full_file_without_range(self):
        response = self.client.get("/media/sample.mp4")

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.content, b"0123456789")
        self.assertEqual(response.headers["accept-ranges"], "bytes")
        self.assertEqual(response.headers["content-length"], "10")

    def test_returns_partial_content_for_byte_range(self):
        response = self.client.get(
            "/media/sample.mp4",
            headers={"Range": "bytes=2-5"},
        )

        self.assertEqual(response.status_code, 206)
        self.assertEqual(response.content, b"2345")
        self.assertEqual(response.headers["accept-ranges"], "bytes")
        self.assertEqual(response.headers["content-range"], "bytes 2-5/10")
        self.assertEqual(response.headers["content-length"], "4")

    def test_returns_suffix_range(self):
        response = self.client.get(
            "/media/sample.mp4",
            headers={"Range": "bytes=-3"},
        )

        self.assertEqual(response.status_code, 206)
        self.assertEqual(response.content, b"789")
        self.assertEqual(response.headers["content-range"], "bytes 7-9/10")

    def test_rejects_invalid_range(self):
        response = self.client.get(
            "/media/sample.mp4",
            headers={"Range": "bytes=99-120"},
        )

        self.assertEqual(response.status_code, 416)
        self.assertEqual(response.headers["content-range"], "bytes */10")


if __name__ == "__main__":
    unittest.main()
