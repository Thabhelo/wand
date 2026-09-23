import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';

test('each sitemap destination declares itself as its canonical URL',()=>{
 const root=new URL('../public/',import.meta.url);
 const sitemap=readFileSync(new URL('sitemap.xml',root),'utf8');
 const urls=[...sitemap.matchAll(/<loc>(.*?)<\/loc>/g)].map(m=>m[1]);
 assert.equal(urls.length,6);
 for(const url of urls){
  const path=new URL(url).pathname;
  assert.ok(path.endsWith('/'),'sitemap must use the final static-assets URL');
  const html=readFileSync(new URL(path.slice(1)+'index.html',root),'utf8');
  const tags=[...html.matchAll(/<link rel="canonical" href="([^"]+)"/g)];
  assert.equal(tags.length,1);assert.equal(tags[0][1],url);
 }
});
