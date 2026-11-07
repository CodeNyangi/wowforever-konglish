const api = window.konglish;
const get = id => document.getElementById(id);
let running = false;

function displayOverlay(value) {
  if (!value) return;
  running = value.running;
  get('connect').textContent = running ? '채팅 영역 다시 지정' : '와우 채팅 연결';
  get('stop').hidden = !running;
  get('state').textContent = running ? value.text : '와우에서 채팅 영역을 드래그해 연결하세요.';
  get('error').textContent = value.error ? value.text : '';
  get('error').hidden = !value.error;
}

get('connect').addEventListener('click', () => running ? api.reselectOverlay() : api.startOverlay());
get('stop').addEventListener('click', () => api.stopOverlay());
api.onOverlayStatus(displayOverlay);
api.overlayStatus().then(displayOverlay);
let version = '';
function displayUpdate(value) {
  if (value.version) version = value.version;
  get('version').textContent = `v${version} · ${value.text}`;
}
api.onUpdateStatus(displayUpdate);
api.appVersion().then(displayUpdate);
