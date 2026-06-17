/* FCM service worker for SILENCE web push.
   Handles notifications while the browser tab is in the background / closed.
   Config below mirrors the `web` entry in lib/firebase_options.dart. */
importScripts('https://www.gstatic.com/firebasejs/10.12.0/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.12.0/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: 'AIzaSyAVz_jy942WB_3awZgcQ7Sm1S_6SjuB_RQ',
  authDomain: 'silence-v6.firebaseapp.com',
  projectId: 'silence-v6',
  storageBucket: 'silence-v6.firebasestorage.app',
  messagingSenderId: '1085738355311',
  appId: '1:1085738355311:web:6f55a6c0a0cd7f68285b9a',
  measurementId: 'G-P5LCD9583D',
});

const messaging = firebase.messaging();

messaging.onBackgroundMessage((payload) => {
  const n = (payload && payload.notification) || {};
  self.registration.showNotification(n.title || 'SILENCE', {
    body: n.body || '',
    icon: '/icons/Icon-192.png',
  });
});
