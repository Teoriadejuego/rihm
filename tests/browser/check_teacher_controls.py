"""Local-only authenticated UI check. Never clicks the real publication action."""
from pathlib import Path
import re
import sys
import time

from playwright.sync_api import sync_playwright, expect

ROOT = Path(__file__).resolve().parents[2]


def main():
    # The values are used only in the local login form, never printed or saved.
    private = (ROOT / "config" / "hosting.Renviron").read_text(encoding="utf-8")
    settings = {
        key: value.strip().strip('"\x27')
        for key, value in re.findall(r"^([A-Z_]+)=(.*)$", private, re.M)
    }
    with sync_playwright() as playwright:
        browser = playwright.chromium.launch(headless=True)
        page = browser.new_page(viewport={"width": 1440, "height": 1000})
        errors = []
        page.on("pageerror", lambda error: errors.append(type(error).__name__))
        page.goto("http://127.0.0.1:8124/", wait_until="networkidle")
        page.wait_for_function("window.Shiny && Shiny.shinyapp && Shiny.shinyapp.$socket.readyState === 1")
        page.locator("#teacher_login-user_id").fill(settings["TEACHER_USERNAME"])
        page.locator("#teacher_login-user_pwd").fill(settings["TEACHER_PASSWORD"])
        page.locator("#teacher_login-user_pwd").press("Tab")
        page.wait_for_timeout(500)
        page.locator("#teacher_login-go_auth").click()
        page.locator('a[data-value="Project"]').wait_for(timeout=15000)
        page.locator('a[data-value="Update"]').click()
        update = page.locator("#update_publish")
        expect(update).to_be_disabled()
        expect(page.locator("#cooldown_status")).to_contain_text("Next real update in")
        print("COOLDOWN_DISABLED_PASS", flush=True)

        # A read operation must also block real updates and other operations.
        page.locator('a[data-value="Latest group"]').click()
        refresh = page.locator("#refresh_latest")
        expect(refresh).to_be_enabled(timeout=45000)
        refresh.click()
        page.wait_for_function("document.getElementById('refresh_latest').disabled === true")
        expect(update).to_be_disabled()
        expect(page.locator("#load_demo")).to_be_disabled()
        expect(refresh).to_be_enabled(timeout=45000)
        print("BUSY_READ_DISABLE_PASS", flush=True)

        # Exercise the server-to-browser exit-fullscreen message.
        page.locator('a[data-value="Teach"]').click()
        page.locator("#start_presentation").click()
        page.wait_for_function("document.fullscreenElement?.id === 'presentationStage'")
        page.evaluate("Shiny.setInputValue('stop_presentation', 1, {priority:'event'})")
        page.wait_for_function("document.fullscreenElement === null")
        print("SERVER_FULLSCREEN_EXIT_PASS", flush=True)

        page.locator('a[data-value="Update"]').click()
        deadline = time.monotonic() + 210
        while time.monotonic() < deadline:
            if "cooldown has ended" in page.locator("#cooldown_status").inner_text():
                break
            expect(update).to_be_disabled()
            page.wait_for_timeout(1000)
        expect(page.locator("#cooldown_status")).to_contain_text("cooldown has ended")
        expect(update).to_be_enabled(timeout=5000)
        print("COOLDOWN_REENABLE_PASS", flush=True)
        # Deliberately do not click update: no Qualtrics download or publication.
        page.locator("#teacher_logout").click()
        page.locator("#teacher_login-user_id").wait_for()
        assert not errors
        browser.close()


if __name__ == "__main__":
    try:
        main()
    except Exception:
        # Playwright exception text can contain filled input values.
        print("TEACHER_CONTROLS_BROWSER_FAILED; no credential values logged.", flush=True)
        sys.exit(1)
