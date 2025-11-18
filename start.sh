#!/usr/bin/env bash
set -e  # หยุดทันทีเมื่อเกิด error

echo "🚀 Starting All-in-One Deploy Script..."

# -----------------------------
# 1. ตรวจสอบ Flutter
# -----------------------------
if ! command -v flutter &> /dev/null
then
    echo "Flutter not found, installing..."
    git clone https://github.com/flutter/flutter.git -b stable --depth 1
    export PATH="$PATH:`pwd`/flutter/bin"
else
    echo "Flutter is installed"
fi

# -----------------------------
# 2. Build Flutter Web (web_admin)
# -----------------------------
WEB_DIR="web_admin"
if [ -d "$WEB_DIR" ]; then
    echo "🌐 Building Flutter Web for $WEB_DIR..."
    cd $WEB_DIR
    flutter pub get
    flutter build web --release
    cd ..
else
    echo "⚠ Directory $WEB_DIR not found, skipping Flutter Web build"
fi

# -----------------------------
# 3. Install Firebase Tools
# -----------------------------
if ! command -v firebase &> /dev/null
then
    echo "Installing Firebase CLI..."
    npm install -g firebase-tools
else
    echo "Firebase CLI is installed"
fi

# -----------------------------
# 4. Deploy Firebase Functions
# -----------------------------
FUNCTIONS_DIR="functions"
if [ -d "$FUNCTIONS_DIR" ]; then
    echo "⚡ Deploying Firebase Functions..."
    cd $FUNCTIONS_DIR
    npm install
    cd ..
    firebase deploy --only functions
else
    echo "⚠ Directory $FUNCTIONS_DIR not found, skipping Firebase Functions deploy"
fi

# -----------------------------
# 5. Serve Flutter Web on Railway
# -----------------------------
if [ -d "$WEB_DIR/build/web" ]; then
    echo "🚀 Serving Flutter Web..."
    npm install -g serve
    serve -s $WEB_DIR/build/web -l $PORT
else
    echo "❌ Build folder not found. Flutter Web was not built correctly."
    exit 1
fi
