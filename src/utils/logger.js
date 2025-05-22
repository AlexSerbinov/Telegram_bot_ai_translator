const { config } = require('../config/config');

class Logger {
  constructor() {
    this.logLevel = config.bot.logLevel;
    this.levels = {
      error: 0,
      warn: 1,
      info: 2,
      debug: 3
    };
  }

  _log(level, message, ...args) {
    if (this.levels[level] <= this.levels[this.logLevel]) {
      const timestamp = new Date().toISOString();
      const formattedMessage = `[${timestamp}] [${level.toUpperCase()}] ${message}`;
      
      if (level === 'error') {
        console.error(formattedMessage, ...args);
      } else if (level === 'warn') {
        console.warn(formattedMessage, ...args);
      } else {
        console.log(formattedMessage, ...args);
      }
    }
  }

  error(message, ...args) {
    this._log('error', message, ...args);
  }

  warn(message, ...args) {
    this._log('warn', message, ...args);
  }

  info(message, ...args) {
    this._log('info', message, ...args);
  }

  debug(message, ...args) {
    this._log('debug', message, ...args);
  }
}

module.exports = new Logger(); 