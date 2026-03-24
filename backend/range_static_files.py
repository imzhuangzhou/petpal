import os
import re
from typing import Iterator, Union
from mimetypes import guess_type

from starlette.datastructures import Headers
from starlette.responses import FileResponse, Response, StreamingResponse
from starlette.staticfiles import StaticFiles


_SINGLE_RANGE_PATTERN = re.compile(r"^bytes=(\d*)-(\d*)$")


def _iter_file_range(path: str, start: int, end: int, chunk_size: int = 64 * 1024) -> Iterator[bytes]:
    with open(path, "rb") as file:
        file.seek(start)
        remaining = end - start + 1

        while remaining > 0:
            chunk = file.read(min(chunk_size, remaining))
            if not chunk:
                break

            remaining -= len(chunk)
            yield chunk


def _parse_range_header(range_header: str, file_size: int) -> tuple[int, int]:
    match = _SINGLE_RANGE_PATTERN.match(range_header.strip())
    if match is None:
        raise ValueError("只支持单段 bytes Range 请求。")

    start_token, end_token = match.groups()
    if not start_token and not end_token:
        raise ValueError("Range 请求缺少起止位置。")

    if not start_token:
        suffix_length = int(end_token)
        if suffix_length <= 0:
            raise ValueError("Range 请求长度无效。")

        suffix_length = min(suffix_length, file_size)
        return file_size - suffix_length, file_size - 1

    start = int(start_token)
    end = int(end_token) if end_token else file_size - 1

    if start >= file_size:
        raise ValueError("Range 起点超出文件大小。")

    end = min(end, file_size - 1)
    if end < start:
        raise ValueError("Range 终点早于起点。")

    return start, end


class RangeAwareStaticFiles(StaticFiles):
    def file_response(
        self,
        full_path: Union[os.PathLike, str],
        stat_result: os.stat_result,
        scope,
        status_code: int = 200,
    ):
        request_headers = Headers(scope=scope)
        range_header = request_headers.get("range")

        if not range_header:
            response = super().file_response(full_path, stat_result, scope, status_code=status_code)
            response.headers.setdefault("accept-ranges", "bytes")
            return response

        file_size = stat_result.st_size
        base_response = FileResponse(full_path, stat_result=stat_result)
        media_type = guess_type(full_path)[0] or "application/octet-stream"

        try:
            start, end = _parse_range_header(range_header, file_size)
        except ValueError:
            return Response(
                status_code=416,
                headers={
                    "accept-ranges": "bytes",
                    "content-range": f"bytes */{file_size}",
                },
            )

        partial_length = end - start + 1
        headers = {
            "accept-ranges": "bytes",
            "content-length": str(partial_length),
            "content-range": f"bytes {start}-{end}/{file_size}",
            "content-type": media_type,
            "etag": base_response.headers["etag"],
            "last-modified": base_response.headers["last-modified"],
        }

        if scope["method"].upper() == "HEAD":
            return Response(status_code=206, headers=headers)

        return StreamingResponse(
            _iter_file_range(os.fspath(full_path), start, end),
            status_code=206,
            headers=headers,
            media_type=media_type,
        )
