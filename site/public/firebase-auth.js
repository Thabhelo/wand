'use strict';
// Firebase keeps its sign-in session in this browser. Only its ID token goes to Wand.
window.wandAuth={async create(config){
 const [{initializeApp,getApps},{getAuth,GoogleAuthProvider,FacebookAuthProvider,linkWithPopup,signInWithPopup,signOut,browserLocalPersistence,setPersistence}]=await Promise.all([
  import('https://www.gstatic.com/firebasejs/12.2.1/firebase-app.js'),
  import('https://www.gstatic.com/firebasejs/12.2.1/firebase-auth.js')
 ]);
 const app=getApps()[0]||initializeApp(config.firebase);
 const auth=getAuth(app);await setPersistence(auth,browserLocalPersistence);await auth.authStateReady();
 return {
  isAuthenticated:async()=>!!auth.currentUser,
  getUser:async()=>auth.currentUser,
  getTokenSilently:async()=>{if(!auth.currentUser)throw Error('Please sign in again.');return auth.currentUser.getIdToken()},
  loginWithRedirect:async(method='google')=>{const provider=method==='facebook'?new FacebookAuthProvider():new GoogleAuthProvider();if(method==='google')provider.setCustomParameters({prompt:'select_account'});await signInWithPopup(auth,provider);location.reload()},
  linkFacebook:async()=>{if(!auth.currentUser)throw Error('Please sign in first.');await linkWithPopup(auth.currentUser,new FacebookAuthProvider());await auth.currentUser.getIdToken(true)},
  logout:async()=>{await signOut(auth);location.reload()}
 };
}};
