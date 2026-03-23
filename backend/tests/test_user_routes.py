import sys
import unittest
from pathlib import Path
from unittest.mock import patch

from fastapi import HTTPException

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import routes.user as user_routes


class CreatePetRouteTests(unittest.TestCase):
    @patch("routes.user.execute_db", return_value=101)
    def test_allows_empty_photo_url_when_using_default_avatar(self, mock_execute_db):
        request = user_routes.CreatePetRequest(
            user_id=1,
            name="奶盖",
            species="cat",
            photo_url="",
            avatar_url="",
            uses_default_avatar=True,
            owner_alias="妈妈",
        )

        response = user_routes.create_pet(request)

        self.assertEqual(response["id"], 101)
        self.assertEqual(response["photo_url"], "")
        self.assertEqual(response["avatar_url"], "")
        mock_execute_db.assert_called_once()

    def test_rejects_empty_photo_url_when_not_using_default_avatar(self):
        request = user_routes.CreatePetRequest(
            user_id=1,
            name="奶盖",
            species="cat",
            photo_url="",
            avatar_url="",
            uses_default_avatar=False,
        )

        with self.assertRaises(HTTPException) as context:
            user_routes.create_pet(request)

        self.assertEqual(context.exception.status_code, 400)
        self.assertEqual(context.exception.detail, "请先上传宠物参考照片")

    @patch("routes.user.execute_db", return_value=202)
    def test_allows_empty_avatar_url_when_using_default_avatar(self, mock_execute_db):
        request = user_routes.CreatePetRequest(
            user_id=1,
            name="可乐",
            species="dog",
            photo_url="",
            avatar_url="",
            uses_default_avatar=True,
        )

        response = user_routes.create_pet(request)

        self.assertEqual(response["id"], 202)
        self.assertEqual(response["avatar_url"], "")
        mock_execute_db.assert_called_once()


class UpdatePetRouteTests(unittest.TestCase):
    @patch("routes.user.execute_db", return_value=0)
    @patch(
        "routes.user.query_db",
        side_effect=[
            {
                "id": 7,
                "name": "Fax",
                "species": "cat",
                "photo_url": "",
                "avatar_url": "",
                "owner_alias": "Boss",
                "language_style": "tsundere",
                "voice_type": "preset",
                "voice_key": "cat-soft",
                "voice_label": "奶呼噜",
            },
            {
                "id": 7,
                "name": "Fax",
                "species": "cat",
                "photo_url": "",
                "avatar_url": "",
                "owner_alias": "Boss",
                "language_style": "chatty",
                "voice_type": "preset",
                "voice_key": "cat-soft",
                "voice_label": "奶呼噜",
            },
        ],
    )
    def test_update_allows_empty_avatar_when_using_default_avatar(self, mock_query_db, mock_execute_db):
        request = user_routes.UpdatePetRequest(
            name="Fax",
            species="cat",
            photo_url="",
            avatar_url="",
            uses_default_avatar=True,
            language_style="chatty",
            owner_alias="Boss",
        )

        response = user_routes.update_pet(7, request)

        self.assertEqual(response["id"], 7)
        self.assertEqual(response["avatar_url"], "")
        self.assertEqual(response["language_style"], "chatty")
        mock_execute_db.assert_called_once()
        self.assertEqual(mock_query_db.call_count, 2)

    @patch(
        "routes.user.query_db",
        return_value={
            "id": 7,
            "name": "Fax",
            "species": "cat",
            "photo_url": "",
            "avatar_url": "",
            "owner_alias": "Boss",
            "language_style": "tsundere",
        },
    )
    def test_update_rejects_empty_photo_url_when_not_using_default_avatar(self, mock_query_db):
        request = user_routes.UpdatePetRequest(
            name="Fax",
            species="dog",
            photo_url="",
            avatar_url="",
            uses_default_avatar=False,
        )

        with self.assertRaises(HTTPException) as context:
            user_routes.update_pet(7, request)

        self.assertEqual(context.exception.status_code, 400)
        self.assertEqual(context.exception.detail, "请先上传宠物参考照片")
        mock_query_db.assert_called_once()

    @patch("routes.user.execute_db", return_value=0)
    @patch(
        "routes.user.query_db",
        side_effect=[
            {
                "id": 7,
                "name": "Fax",
                "species": "cat",
                "photo_url": "/old/photo.jpg",
                "avatar_url": "/old/avatar.jpg",
                "owner_alias": "Boss",
                "language_style": "tsundere",
                "voice_type": "preset",
                "voice_key": "cat-soft",
                "voice_label": "奶呼噜",
            },
            {
                "id": 7,
                "name": "Fax 2",
                "species": "dog",
                "photo_url": "/new/photo.jpg",
                "avatar_url": "/new/avatar.jpg",
                "owner_alias": "妈妈",
                "language_style": "loyal",
                "voice_type": "preset",
                "voice_key": "cat-soft",
                "voice_label": "奶呼噜",
            },
        ],
    )
    def test_update_returns_owner_alias_language_style_and_species(self, mock_query_db, mock_execute_db):
        request = user_routes.UpdatePetRequest(
            name="Fax 2",
            species="dog",
            photo_url="/new/photo.jpg",
            avatar_url="/new/avatar.jpg",
            uses_default_avatar=False,
            language_style="loyal",
            owner_alias="妈妈",
        )

        response = user_routes.update_pet(7, request)

        self.assertEqual(response["owner_alias"], "妈妈")
        self.assertEqual(response["language_style"], "loyal")
        self.assertEqual(response["species"], "dog")
        mock_execute_db.assert_called_once()
        self.assertEqual(mock_query_db.call_count, 2)


if __name__ == "__main__":
    unittest.main()
