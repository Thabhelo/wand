import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync, existsSync} from 'node:fs';
import {JSDOM} from 'jsdom';

const root = new URL('../public/',import.meta.url);
const posts = JSON.parse(readFileSync(new URL('../content/blog/posts.json',import.meta.url),'utf8'));
const read = file => readFileSync(new URL(file,root),'utf8');

test('published posts are discoverable with valid sharing metadata and RSS', () => {
  const index = new JSDOM(read('blog/index.html'));
  const feed = new JSDOM(read('blog/feed.xml'),{contentType:'text/xml'});
  const sitemap = read('sitemap.xml');
  for (const post of posts) {
    const path = `/blog/${post.slug}/`;
    const page = new JSDOM(read(`${path.slice(1)}index.html`));
    const doc = page.window.document;
    assert.ok(index.window.document.querySelector(`a[href="${path}"]`));
    assert.ok(sitemap.includes(`https://getwand.app${path}`));
    assert.ok([...feed.window.document.querySelectorAll('item link')].some(el=>el.textContent === `https://getwand.app${path}`));
    assert.equal(doc.querySelector('meta[property="og:title"]').content,post.title);
    assert.equal(doc.querySelector('meta[name="twitter:card"]').content,'summary_large_image');
    assert.ok(existsSync(new URL(post.image.slice(1),root)));
    const schema = JSON.parse(doc.querySelector('script[type="application/ld+json"]').textContent);
    assert.equal(schema['@type'],'BlogPosting');
    assert.equal(schema.mainEntityOfPage,`https://getwand.app${path}`);
    for (const link of doc.querySelectorAll('.post-toc a')) assert.ok(doc.getElementById(link.hash.slice(1)),`missing section ${link.hash}`);
    for (const link of doc.querySelectorAll('.post-body a')) {
      const url = new URL(link.getAttribute('href'),'https://getwand.app');
      assert.notEqual(url.hostname,'github.com','Wand source is private; public posts must link to public documentation');
      if (url.hostname === 'getwand.app' && url.hash && url.pathname !== path) {
        const destination = new JSDOM(read(url.pathname.replace(/^\//,'').replace(/\/?$/,'/')+'index.html'));
        assert.ok(destination.window.document.getElementById(url.hash.slice(1)),`missing destination ${url.href}`);
        destination.window.close();
      }
    }
    assert.equal(doc.querySelector('[data-architecture-diagram]'),null);
    // The full explanation remains present without JavaScript.
    assert.equal(doc.querySelectorAll('.flow-steps li > p').length,4);
    page.window.close();
  }
  index.window.close(); feed.window.close();
});

test('diagram changes steps without executing commands and share failures are explained', async () => {
  const dom = new JSDOM(read(`blog/${posts[0].slug}/index.html`),{runScripts:'outside-only',url:'https://getwand.app'});
  const {window} = dom;
  window.fetch = () => assert.fail('blog must never execute a remote action');
  let copied;
  Object.defineProperty(window.navigator,'clipboard',{value:{writeText:async value=>{copied=value;}}});
  window.eval(read('blog-assets/blog.js'));
  window.document.querySelector('[data-flow="3"]').click();
  assert.match(window.document.querySelector('.flow-detail').textContent,/waits for success or failure/);
  assert.equal(window.document.querySelectorAll('[data-flow][aria-pressed="true"]').length,1);
  assert.equal(window.document.querySelector('.architecture').dataset.step,'3');
  window.document.querySelector('.copy-link').click();
  await new Promise(resolve=>setImmediate(resolve));
  assert.equal(copied,`https://getwand.app/blog/${posts[0].slug}/`);
  assert.match(window.document.querySelector('.copy-status').textContent,/Link copied/);
  window.navigator.clipboard.writeText = async()=>{throw Error('denied');};
  window.document.querySelector('.copy-link').click();
  await new Promise(resolve=>setImmediate(resolve));
  assert.match(window.document.querySelector('.copy-status').textContent,/page address/);
  window.close();
});
