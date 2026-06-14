import { initializeApp } from "https://www.gstatic.com/firebasejs/10.7.1/firebase-app.js";
import { getAuth }       from "https://www.gstatic.com/firebasejs/10.7.1/firebase-auth.js";
import { getFirestore }  from "https://www.gstatic.com/firebasejs/10.7.1/firebase-firestore.js";
import { getStorage }    from "https://www.gstatic.com/firebasejs/10.7.1/firebase-storage.js";

const firebaseConfig = {
  apiKey:            "AIzaSyAwVeCSzwO50MPqp9SkjDKk3AZ91xml0Uk",
  authDomain:        "permisionn.firebaseapp.com",
  projectId:         "permisionn",
  storageBucket:     "permisionn.firebasestorage.app",
  messagingSenderId: "444805548673",
  appId:             "1:444805548673:web:de27c34201ed6b07b89b80",
  measurementId:     "G-XMHGL36R74"
};

const app = initializeApp(firebaseConfig);

export const auth      = getAuth(app);
export const firestore = getFirestore(app);
export const storage   = getStorage(app);
