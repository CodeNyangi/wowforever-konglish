const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('konglish', {
  overlayStatus: () => ipcRenderer.invoke('overlay-status'),
  startOverlay: () => ipcRenderer.invoke('start-overlay'),
  reselectOverlay: () => ipcRenderer.invoke('reselect-overlay'),
  stopOverlay: () => ipcRenderer.invoke('stop-overlay'),
  onOverlayStatus: callback => { ipcRenderer.on('overlay-status', (_, value) => callback(value)); },
  appVersion: () => ipcRenderer.invoke('app-version'),
  onUpdateStatus: callback => { ipcRenderer.on('update-status', (_, value) => callback(value)); },
});
