import { app, BrowserWindow, globalShortcut, ipcMain, Menu, nativeImage, Tray } from 'electron';
import { join } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { createChatOverlay } from './overlay.js';

app.setName('WoW Forever Konglish');
const page = fileURLToPath(new URL('./index.html', import.meta.url));
const draftShortcut = 'Command+Shift+K';
let window;
let tray;
let quitting = false;
let overlayStatus = { running: false, text: '와우에서 채팅 영역을 드래그해 연결하세요.' };

const overlay = createChatOverlay({
  settings: join(app.getPath('userData'), 'overlay-region.json'),
  onUpdate(status) {
    overlayStatus = status;
    if (window && !window.isDestroyed()) window.webContents.send('overlay-status', status);
    refreshTray();
    if (!status.running && status.error) showSettings();
  },
  onForeground(inWoW) {
    if (inWoW && !globalShortcut.isRegistered(draftShortcut)) {
      globalShortcut.register(draftShortcut, () => overlay.translateDraft());
    } else if (!inWoW) {
      globalShortcut.unregister(draftShortcut);
    }
  },
});

function showSettings() {
  window?.show();
  window?.focus();
}

function refreshTray() {
  if (!tray) return;
  tray.setContextMenu(Menu.buildFromTemplate([
    { label: 'Konglish 열기', click: showSettings },
    { label: '채팅 영역 다시 지정', enabled: overlayStatus.running, click: () => overlay.reselect() },
    { label: '연결 끊기', enabled: overlayStatus.running, click: () => overlay.stop() },
    { type: 'separator' },
    { label: '종료', role: 'quit' },
  ]));
}

function register(channel, action) {
  ipcMain.handle(channel, event => {
    if (event.sender !== window?.webContents || event.senderFrame !== window.webContents.mainFrame ||
        event.senderFrame.url !== pathToFileURL(page).href) return;
    return action();
  });
}

if (!app.requestSingleInstanceLock()) {
  app.quit();
} else {
  app.on('second-instance', showSettings);
  app.on('activate', showSettings);
  app.whenReady().then(() => {
    window = new BrowserWindow({
      width: 450, height: 255, minWidth: 400, minHeight: 235,
      title: 'Konglish', autoHideMenuBar: true,
      webPreferences: {
        preload: fileURLToPath(new URL('./preload.cjs', import.meta.url)),
        contextIsolation: true, sandbox: true, nodeIntegration: false, devTools: false,
      },
    });
    window.webContents.setWindowOpenHandler(() => ({ action: 'deny' }));
    window.webContents.on('will-navigate', event => event.preventDefault());
    window.on('close', event => {
      if (!quitting && overlayStatus.running) { event.preventDefault(); window.hide(); }
    });
    tray = new Tray(nativeImage.createEmpty());
    tray.setTitle('Konglish');
    refreshTray();
    register('overlay-status', () => overlayStatus);
    register('start-overlay', () => { window.hide(); overlay.start(); });
    register('reselect-overlay', () => { window.hide(); overlay.reselect(); });
    register('stop-overlay', () => overlay.stop());
    window.loadFile(page);
  });
  app.on('window-all-closed', () => app.quit());
  app.on('before-quit', () => { quitting = true; overlay.stop(); });
}
