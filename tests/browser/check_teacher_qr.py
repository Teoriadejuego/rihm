"""Authenticated teacher QR check; never opens or submits the Qualtrics survey."""
from io import BytesIO
from pathlib import Path
import re
import sys
import traceback
from urllib.parse import parse_qs, urlsplit

from PIL import Image
from playwright.sync_api import sync_playwright, expect
import zxingcpp

ROOT = Path(__file__).resolve().parents[2]
BASE = sys.argv[1] if len(sys.argv) > 1 else 'http://127.0.0.1:8124/'
LABEL = 'local' if BASE.startswith('http://127.0.0.1:') else 'live'
STAGE = 'initialisation'


def decode(image):
    barcode = zxingcpp.read_barcode(image)
    assert barcode is not None, 'Independent QR decoder found no barcode'
    return barcode.text


def main():
    global STAGE
    settings = {key: value.strip().strip('"\x27') for key, value in re.findall(
        r'^([A-Z_]+)=(.*)$', (ROOT / 'config' / 'hosting.Renviron').read_text(encoding='utf-8'), re.M)}
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)
        context = browser.new_context(viewport={'width': 1440, 'height': 1000},
                                      permissions=['clipboard-read', 'clipboard-write'], accept_downloads=True)
        page = context.new_page()
        requests, errors = [], []
        page.on('request', lambda request: requests.append(request.url))
        page.on('pageerror', lambda error: errors.append(type(error).__name__))
        # Hosted Shiny may keep a SockJS long-poll request open indefinitely.
        # Verify the login and socket explicitly instead of waiting for idle HTTP.
        page.goto(BASE, wait_until='domcontentloaded', timeout=90000)
        page.locator('#teacher_login-user_id').wait_for(timeout=90000)
        expect(page.locator('#generate_survey_qr')).to_have_count(0)

        def login():
            page.wait_for_function('window.Shiny?.shinyapp?.$socket?.readyState === 1')
            page.locator('#teacher_login-user_id').fill(settings['TEACHER_USERNAME'])
            page.locator('#teacher_login-user_pwd').fill(settings['TEACHER_PASSWORD'])
            page.locator('#teacher_login-user_pwd').press('Tab')
            page.wait_for_timeout(500)
            page.locator('#teacher_login-go_auth').click()
            page.locator('a[data-value="Survey QR"]').wait_for(timeout=30000)
            page.locator('a[data-value="Survey QR"]').click()
            expect(page.locator('#survey_qr_empty')).to_be_visible()
            expect(page.locator('#survey_qr_ready')).to_be_hidden()

        STAGE = 'authentication'
        login()
        STAGE = 'generation and independent decoding'
        page.locator('#generate_survey_qr').click()
        expect(page.locator('#survey_qr_image svg')).to_be_visible()
        code = page.locator('#survey_qr_code').inner_text()
        assert re.fullmatch(r'[1-9][0-9]{5}', code)
        url = page.locator('#survey_qr_link').get_attribute('href')
        parsed = urlsplit(url)
        assert parsed.scheme == 'https'
        assert parsed.netloc == 'investigadoresloyola.eu.qualtrics.com'
        assert parsed.path == '/jfe/form/SV_cw4cVf23LI4rJzg'
        assert parse_qs(parsed.query) == {'Treatment_choice': [code]}
        qr = page.locator('#survey_qr_image svg')
        assert decode(Image.open(BytesIO(qr.screenshot()))) == url
        assert page.locator('#survey_qr_code').bounding_box()['y'] > qr.bounding_box()['y'] + qr.bounding_box()['height']
        page.screenshot(path=str(ROOT / 'staging' / f'teacher-qr-{LABEL}.png'), full_page=True)

        STAGE = 'clipboard and downloadable image'
        page.locator('#copy_survey_link').click()
        expect(page.locator('#survey_qr_status')).to_contain_text('copied')
        assert page.evaluate('navigator.clipboard.readText()') == url
        with page.expect_download() as pending:
            page.locator('#download_survey_qr').click()
        download = pending.value
        assert download.suggested_filename == f'RIHM-survey-{code}.png'
        destination = ROOT / 'staging' / f'teacher-qr-download-{LABEL}.png'
        download.save_as(destination)
        assert decode(Image.open(destination)) == url

        STAGE = 'projection and preserved class code'
        page.locator('#present_survey_qr').click()
        page.wait_for_function('document.fullscreenElement?.id === "surveyQrStage"')
        assert decode(Image.open(BytesIO(qr.screenshot()))) == url
        assert page.evaluate('document.fullscreenElement.scrollHeight <= document.fullscreenElement.clientHeight')
        page.screenshot(path=str(ROOT / 'staging' / f'teacher-qr-projection-{LABEL}.png'))
        page.locator('#exit_survey_qr').click()
        page.wait_for_function('document.fullscreenElement === null')
        page.locator('a[data-value="Teach"]').click()
        page.locator('a[data-value="Survey QR"]').click()
        expect(page.locator('#survey_qr_code')).to_have_text(code)

        STAGE = 'mobile QR and regeneration'
        page.set_viewport_size({'width': 390, 'height': 844})
        assert decode(Image.open(BytesIO(qr.screenshot()))) == url
        assert page.evaluate('document.documentElement.scrollWidth <= innerWidth')
        page.screenshot(path=str(ROOT / 'staging' / f'teacher-qr-mobile-{LABEL}.png'), full_page=True)
        page.locator('#generate_survey_qr').click()
        replacement = page.locator('#survey_qr_code').inner_text()
        assert re.fullmatch(r'[1-9][0-9]{5}', replacement) and replacement != code
        replacement_url = page.locator('#survey_qr_link').get_attribute('href')
        assert decode(Image.open(BytesIO(qr.screenshot()))) == replacement_url
        assert parse_qs(urlsplit(replacement_url).query) == {'Treatment_choice': [replacement]}

        STAGE = 'student dashboard invitation'
        tabs = page.locator('#teacher_tabs a[data-value]').evaluate_all('(items) => items.map(a => a.dataset.value)')
        assert tabs[:5] == ['Project', 'Survey QR', 'Update', 'Teach', 'Results QR']
        page.locator('a[data-value="Results QR"]').click()
        results_qr = page.locator('dashboard-qr svg')
        expect(results_qr).to_be_visible()
        dashboard_url = settings['PAGES_BASE_URL']
        assert decode(Image.open(BytesIO(results_qr.screenshot()))) == dashboard_url
        expect(page.locator('#resultsQrStage a')).to_have_attribute('href', dashboard_url)
        page.set_viewport_size({'width': 1366, 'height': 768})
        page.locator('#project_results').click()
        page.wait_for_function('document.fullscreenElement?.id === "resultsQrStage"')
        assert decode(Image.open(BytesIO(results_qr.screenshot()))) == dashboard_url
        page.locator('#project_results').click()
        page.wait_for_function('document.fullscreenElement === null')

        STAGE = 'logout and isolation'
        page.locator('#teacher_logout').click()
        page.locator('#teacher_login-user_id').wait_for()
        expect(page.locator('#survey_qr_code')).to_have_count(0)
        login()
        expect(page.locator('#survey_qr_image svg')).to_have_count(0)
        page.locator('#teacher_logout').click()
        assert not errors, 'Browser JavaScript errors'
        assert not any('qualtrics.com' in urlsplit(item).netloc for item in requests)
        assert not page.evaluate('Object.keys(sessionStorage).some(key => /survey|invite|qr/i.test(key))')
        browser.close()
    print(f'Teacher QR {LABEL} PASS: authenticated generation, independent decoding, shared URL/code, clipboard, PNG, fullscreen, tab persistence, mobile, regeneration, logout, no survey requests or JS errors.')


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        frames = [frame for frame in traceback.extract_tb(error.__traceback__) if Path(frame.filename).resolve() == Path(__file__).resolve()]
        print(f'Teacher QR failed at {STAGE}; line={frames[-1].lineno if frames else "?"}; private inputs omitted.')
        sys.exit(1)
