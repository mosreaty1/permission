// ⚠️  REPLACE WITH YOUR OWN FIREBASE CONFIG
// 1. Go to https://console.firebase.google.com
// 2. Project Settings → General → Your apps → Web app → Add app
// 3. Copy the firebaseConfig object and paste below

import { initializeApp } from "https://www.gstatic.com/firebasejs/10.7.1/firebase-app.js";
import { getAuth }       from "https://www.gstatic.com/firebasejs/10.7.1/firebase-auth.js";
import { getFirestore }  from "https://www.gstatic.com/firebasejs/10.7.1/firebase-firestore.js";
import { getStorage }    from "https://www.gstatic.com/firebasejs/10.7.1/firebase-storage.js";

const firebaseConfig = {
  apiKey:            "YOUR_API_KEY",
  authDomain:        "YOUR_PROJECT_ID.firebaseapp.com",
  projectId:         "YOUR_PROJECT_ID",
  storageBucket:     "YOUR_PROJECT_ID.appspot.com",
  messagingSenderId: "YOUR_SENDER_ID",
  appId:             "YOUR_APP_ID"
};

const app = initializeApp(firebaseConfig);

export const auth      = getAuth(app);
export const firestore = getFirestore(app);
export const storage   = getStorage(app);
