'use strict';
// Firebase keeps its sign-in session in this browser. Only its ID token goes to Wand.
window.wandAuth={async create(config){
 if(this.client)return this.client;
 const [{initializeApp,getApps},{getAuth,GoogleAuthProvider,FacebookAuthProvider,linkWithPopup,linkWithCredential,EmailAuthProvider,signInWithPopup,signInWithEmailAndPassword,createUserWithEmailAndPassword,sendEmailVerification,sendPasswordResetEmail,reload,signOut,browserLocalPersistence,setPersistence}]=await Promise.all([
  import('https://www.gstatic.com/firebasejs/12.2.1/firebase-app.js'),
  import('https://www.gstatic.com/firebasejs/12.2.1/firebase-auth.js')
 ]);
 const app=getApps()[0]||initializeApp(config.firebase);
 const auth=getAuth(app);await setPersistence(auth,browserLocalPersistence);await auth.authStateReady();
 const back={url:location.origin+'/'};
 return this.client={
  isAuthenticated:async()=>!!auth.currentUser,
  getUser:async()=>auth.currentUser,
  getTokenSilently:async()=>{if(!auth.currentUser)throw Error('Please sign in again.');return auth.currentUser.getIdToken()},
  loginWithRedirect:async(method='google')=>{const provider=method==='facebook'?new FacebookAuthProvider():new GoogleAuthProvider();if(method==='google')provider.setCustomParameters({prompt:'select_account'});await signInWithPopup(auth,provider);location.reload()},
  loginWithPassword:async(email,password)=>{await signInWithEmailAndPassword(auth,email,password);location.reload()},
  // A new password account stays unable to use Wand until its emailed link is opened.
  signUpWithPassword:async(email,password)=>{const {user}=await createUserWithEmailAndPassword(auth,email,password);try{await sendEmailVerification(user,back)}catch{}location.reload()},
  sendVerification:async()=>{if(!auth.currentUser)throw Error('Please sign in again.');await sendEmailVerification(auth.currentUser,back)},
  refreshUser:async()=>{if(!auth.currentUser)throw Error('Please sign in again.');await reload(auth.currentUser);await auth.currentUser.getIdToken(true);return auth.currentUser},
  resetPassword:email=>sendPasswordResetEmail(auth,email,back),
  // Linking only ever adds a sign-in method to the account that is signed in right now.
  linkPassword:async password=>{if(!auth.currentUser?.email)throw Error('Please sign in first.');await linkWithCredential(auth.currentUser,EmailAuthProvider.credential(auth.currentUser.email,password));await auth.currentUser.getIdToken(true)},
  linkGoogle:async()=>{if(!auth.currentUser)throw Error('Please sign in first.');await linkWithPopup(auth.currentUser,new GoogleAuthProvider());await auth.currentUser.getIdToken(true)},
  linkFacebook:async()=>{if(!auth.currentUser)throw Error('Please sign in first.');await linkWithPopup(auth.currentUser,new FacebookAuthProvider());await auth.currentUser.getIdToken(true)},
  logout:async()=>{await signOut(auth);location.reload()}
 };
}};
