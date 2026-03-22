import io
import sys
import types
import unittest
from pathlib import Path
from tempfile import NamedTemporaryFile
from unittest.mock import patch

from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))


fake_google = types.ModuleType("google")
fake_google_auth = types.ModuleType("google.auth")
fake_google_auth.default = lambda scopes=None: (object(), "test-project")


class FakeDefaultCredentialsError(Exception):
    pass


fake_google_auth_exceptions = types.ModuleType("google.auth.exceptions")
fake_google_auth_exceptions.DefaultCredentialsError = FakeDefaultCredentialsError


class FakeAPIError(Exception):
    def __init__(self, message="", status=None):
        super().__init__(message)
        self.message = message
        self.status = status


fake_google_genai_errors = types.ModuleType("google.genai.errors")
fake_google_genai_errors.APIError = FakeAPIError


class _AttrObject:
    def __init__(self, **kwargs):
        self.__dict__.update(kwargs)


class FakeHttpOptions(_AttrObject):
    pass


class FakeRawReferenceImage(_AttrObject):
    pass


class FakeImage(_AttrObject):
    pass


class FakeEditImageConfig(_AttrObject):
    pass


class FakeEditMode:
    EDIT_MODE_CONTROLLED_EDITING = "EDIT_MODE_CONTROLLED_EDITING"


fake_google_genai_types = types.ModuleType("google.genai.types")
fake_google_genai_types.HttpOptions = FakeHttpOptions
fake_google_genai_types.RawReferenceImage = FakeRawReferenceImage
fake_google_genai_types.Image = FakeImage
fake_google_genai_types.EditImageConfig = FakeEditImageConfig
fake_google_genai_types.EditMode = FakeEditMode


class FakeClient:
    def __init__(self, *args, **kwargs):
        self.args = args
        self.kwargs = kwargs


fake_google_genai = types.ModuleType("google.genai")
fake_google_genai.Client = FakeClient
fake_google_genai.errors = fake_google_genai_errors
fake_google_genai.types = fake_google_genai_types

fake_google.auth = fake_google_auth
fake_google.genai = fake_google_genai

sys.modules.setdefault("google", fake_google)
sys.modules.setdefault("google.auth", fake_google_auth)
sys.modules.setdefault("google.auth.exceptions", fake_google_auth_exceptions)
sys.modules.setdefault("google.genai", fake_google_genai)
sys.modules.setdefault("google.genai.errors", fake_google_genai_errors)
sys.modules.setdefault("google.genai.types", fake_google_genai_types)

fake_openai = types.ModuleType("openai")


class FakeAPIConnectionError(Exception):
    pass


class FakeAPIStatusError(Exception):
    def __init__(self, *args, response=None, status_code=None, **kwargs):
        super().__init__(*args)
        self.response = response
        self.status_code = status_code


class FakeAPITimeoutError(Exception):
    pass


class FakeOpenAI:
    def __init__(self, *args, **kwargs):
        self.args = args
        self.kwargs = kwargs


fake_openai.APIConnectionError = FakeAPIConnectionError
fake_openai.APIStatusError = FakeAPIStatusError
fake_openai.APITimeoutError = FakeAPITimeoutError
fake_openai.OpenAI = FakeOpenAI
sys.modules.setdefault("openai", fake_openai)

import vlm_service


class PromptTests(unittest.TestCase):
    def test_build_pet_avatar_prompt_includes_new_constraints(self):
        prompt = vlm_service._build_pet_avatar_prompt("cat")

        self.assertIn("严格为 1:1 正方形构图", prompt)
        self.assertIn("不需要严格复现参考图里的原始姿势", prompt)
        self.assertIn("PetPal App 现有视觉风格统一", prompt)
        self.assertIn("绝不能是写实摄影风", prompt)
        self.assertIn("身份一致性优先级高于风格统一", prompt)

    def test_build_pet_avatar_prompt_embeds_identity_summary(self):
        prompt = vlm_service._build_pet_avatar_prompt("cat", "毛色：银渐层；眼睛：绿色")

        self.assertIn("毛色：银渐层；眼睛：绿色", prompt)
        self.assertIn("请逐项吸收并体现在最终头像里", prompt)

    def test_build_pet_avatar_negative_prompt_blocks_unwanted_outputs(self):
        prompt = vlm_service._build_pet_avatar_negative_prompt()

        self.assertIn("写实照片感", prompt)
        self.assertIn("复杂真实场景背景", prompt)
        self.assertIn("多只宠物", prompt)
        self.assertIn("非正方形构图", prompt)


class ResizeHelperTests(unittest.TestCase):
    def _create_temp_image(self, size: tuple[int, int], image_format: str) -> Path:
        suffix = ".jpg" if image_format == "JPEG" else ".png"
        temp_file = NamedTemporaryFile(suffix=suffix, delete=False)
        temp_file.close()

        image = Image.new("RGB", size=size, color=(120, 180, 200))
        image.save(temp_file.name, format=image_format)
        return Path(temp_file.name)

    def test_load_pet_avatar_reference_image_downscales_large_image(self):
        image_path = self._create_temp_image((1600, 1200), "JPEG")
        self.addCleanup(image_path.unlink)

        image_bytes, mime_type = vlm_service._load_pet_avatar_reference_image(str(image_path))

        resized = Image.open(io.BytesIO(image_bytes))
        self.assertEqual(mime_type, "image/jpeg")
        self.assertEqual(max(resized.size), 1024)
        self.assertGreater(len(image_bytes), 0)

    def test_load_pet_avatar_reference_image_keeps_small_image_unchanged(self):
        image_path = self._create_temp_image((512, 512), "PNG")
        self.addCleanup(image_path.unlink)

        original_bytes = image_path.read_bytes()
        image_bytes, mime_type = vlm_service._load_pet_avatar_reference_image(str(image_path))

        self.assertEqual(mime_type, "image/png")
        self.assertEqual(image_bytes, original_bytes)


class IdentityExtractionTests(unittest.TestCase):
    def test_extract_pet_avatar_identity_summary_parses_json_code_block(self):
        fake_response = _AttrObject(
            choices=[
                _AttrObject(
                    message=_AttrObject(
                        content=(
                            "```json\n"
                            '{"coat_colors":["银灰","白色"],"pattern":"额头有浅色M纹","eye_details":"绿色偏圆眼","ear_shape":"直立三角耳","face_shape":"圆脸","nose_muzzle":"粉鼻头、口鼻区偏白","fur_texture":"短毛偏蓬松","distinctive_traits":["下巴白毛"],"accessories":"","summary":"银灰白相间、绿眼、圆脸粉鼻的猫"}'
                            "\n```"
                        )
                    )
                )
            ]
        )

        with patch("vlm_service._run_dashscope_completion", return_value=fake_response), patch(
            "vlm_service.DASHSCOPE_API_KEY",
            "test-key",
        ):
            summary = vlm_service._extract_pet_avatar_identity_summary(
                b"reference-bytes",
                "image/jpeg",
                "cat",
            )

        self.assertIn("毛色：银灰、白色", summary)
        self.assertIn("花纹：额头有浅色M纹", summary)
        self.assertIn("整体识别摘要：银灰白相间、绿眼、圆脸粉鼻的猫", summary)

    def test_extract_pet_avatar_identity_summary_skips_without_dashscope_key(self):
        with patch("vlm_service.DASHSCOPE_API_KEY", ""):
            summary = vlm_service._extract_pet_avatar_identity_summary(
                b"reference-bytes",
                "image/jpeg",
                "cat",
            )

        self.assertEqual(summary, "")


class GeneratePetAvatarTests(unittest.TestCase):
    def test_generate_pet_avatar_uses_fast_square_config(self):
        class FakeModels:
            def __init__(self):
                self.last_kwargs = None

            def edit_image(self, **kwargs):
                self.last_kwargs = kwargs
                generated = _AttrObject(
                    image=_AttrObject(image_bytes=b"generated-avatar", mime_type="image/png")
                )
                return _AttrObject(generated_images=[generated])

        class FakeImageClient:
            def __init__(self):
                self.models = FakeModels()
                self.closed = False

            def close(self):
                self.closed = True

        fake_client = FakeImageClient()

        with patch("vlm_service.get_image_client", return_value=fake_client), patch(
            "vlm_service._load_pet_avatar_reference_image",
            return_value=(b"reference-bytes", "image/jpeg"),
        ), patch(
            "vlm_service._extract_pet_avatar_identity_summary",
            return_value="毛色：奶油白；眼睛：琥珀色",
        ):
            image_bytes, mime_type = vlm_service.generate_pet_avatar("/tmp/pet.jpg", "dog")

        self.assertEqual(image_bytes, b"generated-avatar")
        self.assertEqual(mime_type, "image/png")
        self.assertTrue(fake_client.closed)

        self.assertEqual(
            fake_client.models.last_kwargs["prompt"],
            vlm_service._build_pet_avatar_prompt("dog", "毛色：奶油白；眼睛：琥珀色"),
        )
        config = fake_client.models.last_kwargs["config"]
        self.assertEqual(config.aspect_ratio, "1:1")
        self.assertEqual(config.base_steps, 35)
        self.assertEqual(config.negative_prompt, vlm_service._build_pet_avatar_negative_prompt())

    def test_generate_pet_avatar_falls_back_when_identity_extraction_fails(self):
        class FakeModels:
            def __init__(self):
                self.last_kwargs = None

            def edit_image(self, **kwargs):
                self.last_kwargs = kwargs
                generated = _AttrObject(
                    image=_AttrObject(image_bytes=b"generated-avatar", mime_type="image/png")
                )
                return _AttrObject(generated_images=[generated])

        class FakeImageClient:
            def __init__(self):
                self.models = FakeModels()

            def close(self):
                return None

        fake_client = FakeImageClient()

        with patch("vlm_service.get_image_client", return_value=fake_client), patch(
            "vlm_service._load_pet_avatar_reference_image",
            return_value=(b"reference-bytes", "image/jpeg"),
        ), patch(
            "vlm_service._extract_pet_avatar_identity_summary",
            side_effect=RuntimeError("vlm failed"),
        ):
            vlm_service.generate_pet_avatar("/tmp/pet.jpg", "cat")

        self.assertEqual(
            fake_client.models.last_kwargs["prompt"],
            vlm_service._build_pet_avatar_prompt("cat", ""),
        )


if __name__ == "__main__":
    unittest.main()
