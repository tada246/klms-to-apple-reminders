from __future__ import annotations
import requests
from datetime import datetime, timedelta, timezone

KLMS_BASE_URL = "https://lms.keio.jp"


class CanvasClient:
    def __init__(self, token: str):
        self.session = requests.Session()
        self.session.headers.update({
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
        })

    def _get(self, path: str, params: dict = None) -> list:
        """Fetch all pages from a Canvas API endpoint."""
        url = f"{KLMS_BASE_URL}/api/v1{path}"
        results = []
        while url:
            resp = self.session.get(url, params=params)
            resp.raise_for_status()
            data = resp.json()
            if isinstance(data, list):
                results.extend(data)
            else:
                return data
            # Canvas uses Link header for pagination
            url = self._next_page(resp.headers.get("Link", ""))
            params = None  # params only on first request
        return results

    def _next_page(self, link_header: str) -> str | None:
        for part in link_header.split(","):
            if 'rel="next"' in part:
                return part.split(";")[0].strip().strip("<>")
        return None

    def get_upcoming_assignments(self, days_ahead: int = 30) -> list[dict]:
        """Return upcoming assignments as a flat list."""
        now = datetime.now(timezone.utc)
        end = now + timedelta(days=days_ahead)
        items = self._get("/planner/items", params={
            "start_date": now.strftime("%Y-%m-%d"),
            "end_date": end.strftime("%Y-%m-%d"),
            "per_page": 100,
        })
        assignments = []
        for item in items:
            if item.get("plannable_type") not in ("assignment", "quiz"):
                continue
            plannable = item.get("plannable", {})
            due_at = plannable.get("due_at") or item.get("plannable_date")
            url = item.get("html_url", "")
            if url and url.startswith("/"):
                url = f"{KLMS_BASE_URL}{url}"
            assignments.append({
                "id": f"{item['plannable_type']}_{item['plannable_id']}",
                "title": plannable.get("title", "（タイトル不明）"),
                "course_name": item.get("context_name", ""),
                "due_at": due_at,
                "url": url,
                "submitted": item.get("submissions", {}).get("submitted", False),
            })
        return assignments
