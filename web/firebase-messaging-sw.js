// Firebase Cloud Messaging service worker.
// Must live at web/firebase-messaging-sw.js — the FCM SDK looks for it here
// by convention. Only runs when the site is served over HTTPS (or localhost).
//
// Config below MUST match `DefaultFirebaseOptions.web` in
// lib/firebase_options.dart. If you re-run `flutterfire configure`, update
// both files.

importScripts('https://www.gstatic.com/firebasejs/10.7.0/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.7.0/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey:            'AIzaSyAFx_apd70Er-5P5orPGannAIyHmIPiGP0',
  appId:             '1:230410219102:web:03b842c76f7f64c96fcecf',
  messagingSenderId: '230410219102',
  projectId:         'crunchy-hot',
  authDomain:        'crunchy-hot.firebaseapp.com',
  storageBucket:     'crunchy-hot.firebasestorage.app',
});

const messaging = firebase.messaging();

// Background handler: show a system-tray notification with our brand colour.
// Foreground messages are handled by flutter_local_notifications in-app.
messaging.onBackgroundMessage((payload) => {
  const notif = payload.notification || {};
  self.registration.showNotification(notif.title || 'كرانشي هوت', {
    body: notif.body || '',
    icon: '/icons/Icon-192.png',
    badge: '/icons/Icon-192.png',
    data: payload.data || {},
  });
});

// Route the click to whichever tab wants to open (data.screen === 'offers').
self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const url = self.location.origin + (event.notification.data?.screen === 'offers' ? '/#/offers' : '/');
  event.waitUntil(clients.openWindow(url));
});
