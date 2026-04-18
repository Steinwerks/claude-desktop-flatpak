'use strict';

// Linux stub for @ant/claude-native — replaces the Windows-only native binary.
// Implements the same API surface using Electron built-ins where possible.

const { BrowserWindow } = require('electron');

const KeyboardKey = {
  Backspace: 43,
  Tab: 44,
  Return: 40,
  Enter: 40,
  Shift: 225,
  Control: 224,
  Alt: 226,
  Pause: 72,
  CapsLock: 57,
  Escape: 41,
  Space: 44,
  PageUp: 75,
  PageDown: 78,
  End: 77,
  Home: 74,
  ArrowLeft: 80,
  ArrowUp: 82,
  ArrowRight: 79,
  ArrowDown: 81,
  PrintScreen: 70,
  Insert: 73,
  Delete: 76,
  Meta: 227,
  F1: 58,
  F2: 59,
  F3: 60,
  F4: 61,
  F5: 62,
  F6: 63,
  F7: 64,
  F8: 65,
  F9: 66,
  F10: 67,
  F11: 68,
  F12: 69,
  NumLock: 83,
  ScrollLock: 71,
};

function getWindow() {
  const focused = BrowserWindow.getFocusedWindow();
  if (focused && !focused.isDestroyed()) return focused;
  const all = BrowserWindow.getAllWindows();
  return all.find(w => !w.isDestroyed()) || null;
}

class AuthRequest {
  static isAvailable() {
    return false; // Not available on Linux; falls back to system browser auth
  }
}

function getIsMaximized() {
  const win = getWindow();
  return win ? win.isMaximized() : false;
}

function flashFrame() {
  const win = getWindow();
  if (win) win.flashFrame(true);
}

function clearFlashFrame() {
  const win = getWindow();
  if (win) win.flashFrame(false);
}

function setProgressBar(progress) {
  const win = getWindow();
  if (win) win.setProgressBar(typeof progress === 'number' && progress >= 0 ? progress : -1);
}

function clearProgressBar() {
  const win = getWindow();
  if (win) win.setProgressBar(-1);
}

// No-ops for Windows-only effects
function setWindowEffect() {}
function removeWindowEffect() {}
function showNotification() {}
function setOverlayIcon() {}
function clearOverlayIcon() {}
function getWindowsVersion() { return '0.0.0'; }

module.exports = {
  KeyboardKey,
  AuthRequest,
  getIsMaximized,
  flashFrame,
  clearFlashFrame,
  setProgressBar,
  clearProgressBar,
  setWindowEffect,
  removeWindowEffect,
  showNotification,
  setOverlayIcon,
  clearOverlayIcon,
  getWindowsVersion,
};
