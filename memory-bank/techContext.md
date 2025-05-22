# Technical Context

## Technology Stack

### Core Technologies
- **Runtime**: Node.js v18+
- **Bot Framework**: Telegraf.js (Telegram Bot API)
- **Database**: MongoDB with Mongoose ODM
- **AI Services**: OpenAI API (Whisper, GPT-4o-nano)
- **Deployment**: Docker + Docker Compose

### Dependencies
```json
{
  "telegraf": "^4.x", // Telegram bot framework
  "openai": "^4.x",   // OpenAI API client
  "mongoose": "^8.x", // MongoDB ODM
  "axios": "^1.x",    // HTTP client
  "fs-extra": "^11.x", // File system utilities
  "winston": "^3.x"   // Logging framework
}
```

## Development Setup

### Environment Variables
```
TELEGRAM_BOT_TOKEN=your_telegram_bot_token
OPENAI_API_KEY=your_openai_api_key
MONGODB_URI=mongodb://mongo:27017/ai_translator
NODE_ENV=development
LOG_LEVEL=info
```

### Docker Configuration
- **Application**: Node.js container with volume mounts
- **Database**: MongoDB container with initialization scripts
- **Networking**: Internal Docker network for service communication
- **Volumes**: Persistent MongoDB data, temporary audio storage

### File Structure
```
ai-translator/
├── src/
│   ├── bot.js              # Main application
│   ├── config/             # Configuration
│   ├── handlers/           # Bot handlers
│   ├── models/             # Database models
│   ├── services/           # Business logic
│   └── utils/              # Utilities
├── temp/audio/             # Temporary files
├── memory-bank/            # Documentation
├── docker-compose.yml      # Container orchestration
└── package.json            # Dependencies
```

## Technical Constraints

### API Limitations
- **OpenAI**: Rate limits, token costs, model availability
- **Telegram**: File size limits (20MB), message length limits
- **MongoDB**: Document size limits (16MB)

### Performance Requirements
- **Response Time**: <10 seconds for voice processing
- **Concurrent Users**: Support for multiple simultaneous requests
- **Memory Usage**: Efficient cleanup of temporary files

### Security Considerations
- **API Keys**: Stored in environment variables
- **User Data**: Minimal storage, automatic cleanup
- **Rate Limiting**: 20 requests/minute per user
- **Input Validation**: All user inputs validated

## Development Patterns

### Error Handling
```javascript
try {
  // Operation
  const result = await service.process(data);
  return result;
} catch (error) {
  logger.error('Operation failed:', error);
  await ctx.reply('❌ Виникла помилка');
}
```

### Logging Strategy
- **Levels**: ERROR, WARN, INFO, DEBUG
- **Format**: Timestamp, level, message, metadata
- **Storage**: Console output (captured by Docker)

### Testing Approach
- **Manual Testing**: Telegram bot interaction
- **Unit Tests**: Service layer functions (planned)
- **Integration Tests**: API interactions (planned)

## Deployment Architecture

### Production Environment
- **Hosting**: Docker containers
- **Database**: MongoDB cluster
- **Monitoring**: Application logs
- **Backup**: Database snapshots

### CI/CD Pipeline (Future)
- **Source Control**: Git with feature branches
- **Build**: Docker image creation
- **Testing**: Automated test suite
- **Deployment**: Container orchestration

## Known Technical Debt
- **Error Recovery**: Limited fallback mechanisms
- **Testing**: No automated test suite
- **Monitoring**: Basic logging only
- **Scalability**: Single instance deployment
- **Security**: Basic rate limiting only

## Future Technical Improvements
- **Caching**: Redis for session management
- **Queue System**: Background job processing
- **Load Balancing**: Multiple bot instances
- **Monitoring**: Application metrics and alerts
- **Testing**: Comprehensive test coverage 