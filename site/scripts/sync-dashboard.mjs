import { copyFile } from 'node:fs/promises';
for (const [source,target] of [['index.html','dashboard.html'],['dashboard.css','dashboard.css'],['dashboard.js','dashboard.js'],['firebase-auth.js','firebase-auth.js']]) await copyFile(new URL('../../web/'+source, import.meta.url),new URL('../public/'+target,import.meta.url));
