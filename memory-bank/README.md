# Memory Bank - AI Translator Bot

## Overview
This Memory Bank contains comprehensive documentation for the AI Translator Bot project. It serves as the primary knowledge base for understanding the project's current state, architecture, and ongoing development.

## File Structure

### Core Documentation
- **`projectbrief.md`** - Foundation document with project overview and requirements
- **`productContext.md`** - Product vision, user problems, and value proposition  
- **`systemPatterns.md`** - Technical architecture and design patterns
- **`techContext.md`** - Technology stack, setup, and constraints
- **`activeContext.md`** - Current work focus and recent changes
- **`progress.md`** - Comprehensive status of completed and remaining work

## Quick Reference

### Project Status
- **Phase 3**: ✅ Complete (Premium system implemented)
- **Phase 4**: 🚧 In Progress (Production polish)
- **Current Focus**: Process management and testing

### Key Technologies
- Node.js + Telegraf.js (Telegram Bot)
- MongoDB (User data and analytics)
- OpenAI API (Whisper + GPT-4o-nano)
- Docker + Docker Compose

### User Tiers
- **Free**: Manual language selection, basic features, 10k tokens/day
- **Premium**: Auto-detection, back-translation, 100k tokens/day

### Dev Commands (Hidden)
- `/go_premium` - Switch user to premium status
- `/go_free` - Switch user to free status

## Recent Changes
1. Implemented premium vs free user differentiation
2. Added hidden dev commands for testing
3. Removed chat functionality completely
4. Enhanced Free user experience with manual language selection
5. Updated to GPT-4o-nano model

## Next Steps
1. Implement process management (PM2)
2. Comprehensive testing and validation
3. Performance optimization
4. Production monitoring setup

## How to Use This Memory Bank
1. Start with `projectbrief.md` for overall understanding
2. Review `activeContext.md` for current work status
3. Check `progress.md` for detailed status of features
4. Reference `systemPatterns.md` and `techContext.md` for technical details
5. Update `activeContext.md` when resuming work after breaks

---

*This Memory Bank is designed to preserve project knowledge across development sessions and team handoffs. Keep it updated as the project evolves.* 