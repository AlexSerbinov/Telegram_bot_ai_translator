/**
 * Standalone server for the live ES→UK prototype.
 * Boots only Express + WebSocket TTS proxy — no Telegraf, no MongoDB.
 * Open http://localhost:<SERVER_PORT>/webapp/live.html
 */
require('dotenv').config();
const { startServer } = require('../src/server');

startServer();
