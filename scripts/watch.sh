#!/bin/bash

echo "👀 Starting config watcher for auto-backup..."

# Check if DATABASE_URL is set
if [ -z "$DATABASE_URL" ]; then
  echo "⚠️  DATABASE_URL not set, skipping watch"
  exit 0
fi

# Wait for 9router to start and create config
sleep 10

# Node script to watch and backup config
node << 'EOF'
const { Client } = require('pg');
const fs = require('fs');
const path = require('path');

const configPath = path.join(process.env.HOME || '/app', '.9router', 'db.json');
let lastBackup = '';

async function backup() {
  const client = new Client({
    connectionString: process.env.DATABASE_URL,
    ssl: { rejectUnauthorized: false }
  });

  try {
    // Check if config file exists
    if (!fs.existsSync(configPath)) {
      return;
    }

    const configContent = fs.readFileSync(configPath, 'utf8');

    // Skip if no changes
    if (configContent === lastBackup) {
      return;
    }

    await client.connect();

    // Create table if not exists
    await client.query(`
      CREATE TABLE IF NOT EXISTS router_config (
        id SERIAL PRIMARY KEY,
        config JSONB NOT NULL,
        updated_at TIMESTAMP DEFAULT NOW()
      )
    `);

    // Insert new config
    await client.query(
      'INSERT INTO router_config (config) VALUES ($1)',
      [JSON.parse(configContent)]
    );

    lastBackup = configContent;
    console.log('✅ Config backed up at', new Date().toISOString());

    await client.end();
  } catch (error) {
    console.error('❌ Backup error:', error.message);
  }
}

// Backup every 2 minutes
console.log('🔄 Watching config file:', configPath);
setInterval(backup, 120000);

// Initial backup after 30 seconds
setTimeout(backup, 30000);
EOF
