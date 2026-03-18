# Deployment Guide

To publish your latest changes to the live website, run these two commands in your terminal:

1. **Build the web application:**
```powershell
flutter build web --release
```

2. **Deploy to Firebase Hosting:**
```powershell
firebase deploy --only hosting
```
