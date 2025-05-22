# System Patterns & Architecture

## Overall Architecture

```
Telegram Bot API
       ↓
   Bot Handler
       ↓
┌─────────────────┐
│   Middleware    │
│ - User Creation │
│ - Rate Limiting │
│ - Logging       │
└─────────────────┘
       ↓
┌─────────────────┐
│    Handlers     │
│ - Commands      │
│ - Callbacks     │
│ - Audio         │
└─────────────────┘
       ↓
┌─────────────────┐
│    Services     │
│ - OpenAI        │
│ - Database      │
│ - Language      │
└─────────────────┘
       ↓
┌─────────────────┐
│   Data Layer    │
│ - MongoDB       │
│ - File System   │
└─────────────────┘
```

## Key Design Patterns

### 1. Handler Pattern
- **Command Handlers**: Process bot commands (/start, /settings, etc.)
- **Callback Handlers**: Process button interactions
- **Audio Handlers**: Process voice messages

### 2. Service Layer Pattern
- **OpenAI Service**: Encapsulates all AI operations
- **Database Service**: Manages user data and statistics
- **Language Service**: Handles language settings and metadata

### 3. Middleware Pattern
- **User Middleware**: Ensures user exists in database
- **Rate Limiting**: Prevents abuse
- **Logging**: Tracks all operations

### 4. Strategy Pattern
- **Free vs Premium Processing**: Different workflows based on subscription
- **Language Detection**: Multiple strategies (Whisper-only vs GPT+Whisper)

## Core Components

### Bot Controller (`src/bot.js`)
- Main application entry point
- Sets up middleware chain
- Registers handlers
- Manages graceful shutdown

### Handlers Directory (`src/handlers/`)
- `commandHandlers.js`: Bot commands (/start, /settings, dev commands)
- `callbackHandlers.js`: Inline keyboard callbacks
- `audioHandler.js`: Voice message processing

### Services Directory (`src/services/`)
- `openaiService.js`: AI operations (speech-to-text, translation, detection)
- `databaseService.js`: MongoDB operations
- `languageService.js`: Language utilities and user preferences

### Models Directory (`src/models/`)
- `User.js`: User schema with subscription logic
- Removed: `Chat.js` (chat functionality eliminated in Phase 3)

## Data Flow Patterns

### Premium User Flow
```
Voice Message → Download → Whisper STT → GPT Detection → 
Translation → Back-translation → Format Response → Send Result
```

### Free User Flow  
```
Voice Message → Download → Show Language Buttons → 
User Selection → Whisper STT → Translation → Format Response → Send Result
```

## Error Handling Patterns
- **Graceful Degradation**: Fallback to simpler processing on errors
- **User-Friendly Messages**: Convert technical errors to readable messages
- **Comprehensive Logging**: Track errors for debugging
- **Cleanup**: Always clean temporary files

## Security Patterns
- **Rate Limiting**: 20 requests per minute per user
- **Input Validation**: Validate all user inputs
- **Token Limits**: Prevent API abuse through usage limits
- **Environment Variables**: Secure credential management

## Scalability Considerations
- **Stateless Design**: No in-memory session storage (except temporary audio)
- **Database Indexing**: Optimized queries for user lookup
- **File Cleanup**: Automatic temporary file removal
- **Connection Pooling**: MongoDB connection management 