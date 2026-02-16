FROM node:18-alpine

# Set working directory
WORKDIR /app

# Copy package files
COPY package*.json ./

# Install dependencies
RUN npm ci --only=production

# Copy source code
COPY src/ ./src/

# Note: Running as root for simplicity with volume mounts

# Expose port (optional, for health checks)
EXPOSE 3000

# Start the application
CMD ["npm", "start"] 