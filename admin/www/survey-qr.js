import { createSurveyInvite, qrSvgMarkup, QR_BORDER } from './survey-qr-core.js';

import { qrcodegen } from './qrcodegen-v1.8.0.js';

customElements.define('dashboard-qr', class extends HTMLElement {
  connectedCallback() {
    const qr = qrcodegen.QrCode.encodeText(this.dataset.url, qrcodegen.QrCode.Ecc.QUARTILE);
    this.innerHTML = qrSvgMarkup(qr);
    this.firstElementChild.setAttribute('aria-label', 'QR code for the student results dashboard');
  }
});

let current = null;
let currentStage = null;
const element = (id) => document.getElementById(id);
const announce = (text) => {
  const status = element('survey_qr_status');
  if (status) status.textContent = text;
};
const activeInvite = () => currentStage === element('surveyQrStage') ? current : null;

function generate() {
  const stage = element('surveyQrStage');
  if (!stage) return;
  try {
    const invite = createSurveyInvite(activeInvite()?.code);
    element('survey_qr_image').innerHTML = qrSvgMarkup(invite.qr);
    element('survey_qr_code').textContent = invite.code;
    element('survey_qr_link').href = invite.url;
    element('survey_qr_link').textContent = invite.url;
    element('survey_qr_empty').hidden = true;
    element('survey_qr_ready').hidden = false;
    element('survey_qr_actions').hidden = false;
    element('generate_survey_qr').textContent = 'Generate new QR';
    current = invite;
    currentStage = stage;
    announce('Class QR ready. Keep this code for everyone in this group.');
    stage.focus({ preventScroll: true });
  } catch {
    announce('The QR could not be generated. Keep the existing code, or reload the panel and try again.');
  }
}

async function present() {
  if (!activeInvite()) return;
  try {
    if (!currentStage.requestFullscreen) throw new Error('Fullscreen unavailable');
    await currentStage.requestFullscreen();
    currentStage.focus();
  } catch {
    announce('Full screen is unavailable in this browser. Project this view or download the QR image.');
  }
}

async function copyLink() {
  const invite = activeInvite();
  if (!invite) return;
  try {
    await navigator.clipboard.writeText(invite.url);
    announce('Survey link copied. It includes this group’s code.');
  } catch {
    announce('Copy the survey link shown below the QR. It includes this group’s code.');
  }
}

function download() {
  const invite = activeInvite();
  if (!invite) return;
  try {
    const canvas = document.createElement('canvas');
    canvas.width = 1200;
    canvas.height = 1450;
    const context = canvas.getContext('2d');
    if (!context) throw new Error('Canvas unavailable');
    context.fillStyle = '#fff';
    context.fillRect(0, 0, canvas.width, canvas.height);
    const scale = Math.floor(1100 / (invite.qr.size + QR_BORDER * 2));
    const left = Math.floor((canvas.width - invite.qr.size * scale) / 2);
    const top = 50 + QR_BORDER * scale;
    context.fillStyle = '#000';
    for (let y = 0; y < invite.qr.size; y++) {
      for (let x = 0; x < invite.qr.size; x++) {
        if (invite.qr.getModule(x, y)) context.fillRect(left + x * scale, top + y * scale, scale, scale);
      }
    }
    context.textAlign = 'center';
    context.font = '48px sans-serif';
    context.fillText('Code', 600, 1240);
    context.font = 'bold 112px sans-serif';
    context.fillText(invite.code, 600, 1370);
    canvas.toBlob((blob) => {
      if (!blob) { announce('The image could not be downloaded. Use the survey link instead.'); return; }
      const url = URL.createObjectURL(blob);
      const link = document.createElement('a');
      link.href = url;
      link.download = `RIHM-survey-${invite.code}.png`;
      document.body.append(link);
      link.click();
      link.remove();
      setTimeout(() => URL.revokeObjectURL(url), 1000);
      announce('QR image downloaded with the class code underneath.');
    }, 'image/png');
  } catch {
    announce('The image could not be downloaded. Use the survey link instead.');
  }
}

document.addEventListener('click', (event) => {
  const target = event.target.closest('button');
  if (!target) return;
  if (['generate_survey_qr', 'present_survey_qr', 'copy_survey_link',
    'download_survey_qr', 'exit_survey_qr'].includes(target.id)) {
    // Count deliberate activity for the existing login timeout, without sending
    // the invitation or class code to the Shiny server.
    window.Shiny?.setInputValue('survey_qr_activity', Date.now(), { priority: 'event' });
  }
  if (target.id === 'project_results') {
    const stage = element('resultsQrStage');
    const toggle = document.fullscreenElement === stage
      ? () => document.exitFullscreen() : () => stage.requestFullscreen();
    Promise.resolve().then(toggle).catch(() => {
      element('results_qr_status').textContent = 'Project this page or share the link below the QR.';
    });
  }
  if (target.id === 'generate_survey_qr') generate();
  if (target.id === 'present_survey_qr') void present();
  if (target.id === 'copy_survey_link') void copyLink();
  if (target.id === 'download_survey_qr') download();
  if (target.id === 'exit_survey_qr' && document.fullscreenElement === currentStage) {
    void document.exitFullscreen().catch(() => {});
  }
  if (target.id === 'teacher_logout') { current = null; currentStage = null; }
});

// Authentication can expire without a logout click. No class code survives a
// new authenticated UI, and no code is written to browser storage or the server.
if (window.jQuery) {
  window.jQuery(document).on('shiny:bound.surveyQr', (event) => {
    if (event.target?.id === 'teacher_login-user_id') { current = null; currentStage = null; }
  });
}

document.addEventListener('fullscreenchange', () => {
  const button = element('project_results');
  if (button) button.textContent = document.fullscreenElement === element('resultsQrStage')
    ? 'Exit full screen' : 'Project results QR';
});
