#!/bin/bash
set -e

echo "🔄 Starting config restore from Neon PostgreSQL..."

# Check if DATABASE_URL is set
if [ -z "$DATABASE_URL" ]; then
  echo "⚠️  DATABASE_URL not set, skipping restore"
  exit 0
fi

# Install pg client if not exists
if ! command -v psql &> /dev/null; then
  echo "📦 Installing PostgreSQL client..."
  npm install -g pg
fi

# Create config directory
mkdir -p ~/.9router

# Node script to restore config from PostgreSQL
node << 'EOF'
const { Client } = require('pg');
const fs = require('fs');
const path = require('path');

async function restore() {
  const client = new Client({
    connectionString: process.env.DATABASE_URL,
    ssl: { rejectUnauthorized: false }
  });

  try {
    await client.connect();
    console.log('✅ Connected to Neon PostgreSQL');

    // Create table if not exists
    await client.query(`
      CREATE TABLE IF NOT EXISTS router_config (
        id SERIAL PRIMARY KEY,
        config JSONB NOT NULL,
        updated_at TIMESTAMP DEFAULT NOW()
      )
    `);

    // Get latest config
    const result = await client.query(
      'SELECT config FROM router_config ORDER BY updated_at DESC LIMIT 1'
    );

    if (result.rows.length > 0) {
      const configPath = path.join(process.env.HOME || '/app', '.9router', 'db.json');
      fs.writeFileSync(configPath, JSON.stringify(result.rows[0].config, null, 2));
      console.log('✅ Config restored to:', configPath);
    } else {
      console.log('ℹ️  No config found in database, starting fresh');
    }

  } catch (error) {
    console.error('❌ Restore error:', error.message);
    process.exit(0); // Don't fail the deployment
  } finally {
    await client.end();
  }
}

restore();
EOF
