import { readFile, writeFile, mkdir } from 'node:fs/promises';

const origin = 'https://getwand.app';
const content = new URL('../content/blog/', import.meta.url);
const output = new URL('../public/', import.meta.url);
const posts = JSON.parse(await readFile(new URL('posts.json', content), 'utf8'));
const escape = value => String(value).replace(/[&<>"']/g, c => ({'&':'&amp;', '<':'&lt;', '>':'&gt;', '"':'&quot;', "'":'&#39;'}[c]));
const formatDate = date => new Date(`${date}T12:00:00Z`).toLocaleDateString('en-US', {month:'long', day:'numeric', year:'numeric', timeZone:'UTC'});
const seen = new Set();
for (const post of posts) {
  if (!/^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(post.slug) || seen.has(post.slug)) throw new Error('Blog slugs must be unique URL-safe names.');
  seen.add(post.slug);
  if (!/^\d{4}-\d{2}-\d{2}$/.test(post.date) || Number.isNaN(Date.parse(post.date))) throw new Error('Blog posts need a publication date.');
  for (const field of ['title','description','author','category','image']) if (typeof post[field] !== 'string' || !post[field]) throw new Error(`Missing blog field: ${field}`);
  if (!post.image.startsWith('/blog-assets/')) throw new Error('Blog share images must be local assets.');
  post.body = await readFile(new URL(`${post.slug}.html`, content), 'utf8');
  post.minutes = Math.max(1, Math.ceil(post.body.replace(/<[^>]*>/g, ' ').split(/\s+/).filter(Boolean).length / 220));
  post.path = `/blog/${post.slug}/`;
}
posts.sort((a,b) => b.date.localeCompare(a.date));

const nav = `<a class="skip" href="#main">Skip to content</a><header class="blog-nav"><a class="brand" href="/" aria-label="Wand home"><img src="/mark.svg?v=2" width="32" height="32" alt="">wand</a><nav aria-label="Main"><a href="/blog/" aria-current="page">Blog</a><a class="nav-connect" href="/download/">Get Wand ↗</a></nav></header>`;
const footer = `<footer class="blog-footer"><a class="brand" href="/">wand</a><p>We gave Muse more powers.</p><nav aria-label="Footer"><a href="/blog/feed.xml">RSS</a><a href="/developers/">Developers</a><a href="/support/">Support</a><a href="/privacy/">Privacy</a></nav></footer>`;
function page({title, description, path, image, structured, article = false}, body) {
  const url = origin + path;
  return `<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>${escape(title)} — Wand</title><meta name="description" content="${escape(description)}"><meta name="theme-color" content="#f5f5ed">
<link rel="icon" href="/mark.svg?v=2"><link rel="canonical" href="${escape(url)}"><link rel="alternate" type="application/rss+xml" title="Wand Blog" href="/blog/feed.xml">
<link rel="stylesheet" href="/style.css"><link rel="stylesheet" href="/blog-assets/blog.css"><script src="/blog-assets/blog.js" defer></script>
<meta property="og:type" content="${article ? 'article' : 'website'}"><meta property="og:site_name" content="Wand"><meta property="og:title" content="${escape(title)}"><meta property="og:description" content="${escape(description)}"><meta property="og:url" content="${escape(url)}"><meta property="og:image" content="${origin}${escape(image)}"><meta property="og:image:width" content="1200"><meta property="og:image:height" content="630"><meta property="og:image:alt" content="From your phone, through Wand, to your Mac"><meta name="twitter:card" content="summary_large_image">
<script type="application/ld+json">${JSON.stringify(structured).replace(/</g, '\\u003c')}</script></head>
<body class="blog-page">${nav}${body}${footer}</body></html>\n`;
}

const diagram = `<figure class="architecture" aria-labelledby="architecture-title">
<figcaption id="architecture-title">One request. Four steps.</figcaption>
<p class="diagram-hint">Follow a command from your phone to your Mac and back.</p>
<ol class="flow-steps">
<li><button type="button" data-flow="0" aria-pressed="true"><span>01</span> Ask</button><p>Muse reads your request and chooses an available Wand action.</p></li>
<li><button type="button" data-flow="1" aria-pressed="false"><span>02</span> Route</button><p>Wand checks ownership and permission, then finds your Mac’s connection.</p></li>
<li><button type="button" data-flow="2" aria-pressed="false"><span>03</span> Act</button><p>The Mac validates the command and runs it through native macOS APIs.</p></li>
<li><button type="button" data-flow="3" aria-pressed="false"><span>04</span> Verify</button><p>The result travels back. The caller waits for success or failure.</p></li>
</ol>
<div class="flow-map" aria-hidden="true"><span class="flow-node" data-node="phone"><svg viewBox="0 0 32 40"><rect x="5" y="2" width="22" height="36" rx="5"/><path d="M12 6h8M13 33h6"/></svg><b>Your phone</b></span><span class="flow-wire"></span><span class="flow-node" data-node="relay"><img src="/mark.svg" width="44" height="44" alt=""><b>Wand relay</b></span><span class="flow-wire"></span><span class="flow-node" data-node="mac"><svg viewBox="0 0 48 40"><rect x="6" y="4" width="36" height="25" rx="3"/><path d="M2 33h44l-4 3H6z"/></svg><b>Your Mac</b></span></div>
<p class="flow-detail" aria-live="polite" hidden></p><p class="diagram-footnote">The Mac opens the connection. The relay sends commands back through it. This diagram illustrates the flow; it does not control a device.</p></figure>`;

for (const post of posts) {
  const headings = [...post.body.matchAll(/<h2 id="([a-z0-9-]+)">([^<]+)<\/h2>/g)];
  const toc = headings.map(([,id,title]) => `<a href="#${id}">${title}</a>`).join('');
  const body = post.body.replace('<div data-architecture-diagram></div>', diagram);
  const url = origin + post.path;
  const structured = {'@context':'https://schema.org','@type':'BlogPosting',headline:post.title,description:post.description,datePublished:post.date,dateModified:post.date,author:{'@type':'Person',name:post.author,url:'https://thabheloduve.com'},publisher:{'@type':'Organization',name:'Wand',url:origin,logo:{'@type':'ImageObject',url:origin+'/blog-assets/wand-mark.png'}},image:origin+post.image,mainEntityOfPage:url};
  const html = page({...post, structured, article:true}, `<main id="main" class="post-main"><article>
<div class="post-heading"><a class="back-link" href="/blog/">← All posts</a><div class="post-kicker">${escape(post.category)} <span>·</span> <time datetime="${post.date}">${formatDate(post.date)}</time></div><h1>${escape(post.title)}</h1><p class="post-deck">${escape(post.description)}</p><div class="post-byline"><span>${escape(post.author)} <span class="byline-divider">/</span> ${post.minutes} min read</span><button class="copy-link" type="button" data-copy-link="${escape(url)}">Copy link ↗</button><span class="copy-status" role="status"></span></div></div>
<div class="post-layout"><aside class="post-toc" aria-label="In this article"><span>In this article</span>${toc}</aside><div class="post-body">${body}<div class="post-end"><img src="/mark.svg" width="42" height="42" alt=""><div><h2>Try it on your Mac.</h2><p>Connect once. Open Wand on your phone.</p></div><a class="button dark" href="/download/">Get Wand ↗</a></div></div></div></article></main>`);
  await mkdir(new URL(`blog/${post.slug}/`,output),{recursive:true});
  await writeFile(new URL(`blog/${post.slug}/index.html`,output),html);
}
const cards = posts.map(post => `<article class="post-card"><a class="post-card-link" href="${post.path}"><div class="post-card-art"><img src="${escape(post.image)}" alt="A phone connected to a Mac through Wand" width="1200" height="630"></div><div class="post-card-copy"><p class="post-kicker">${escape(post.category)} <span>·</span> ${formatDate(post.date)}</p><h2>${escape(post.title)}</h2><p>${escape(post.description)}</p><span class="read-story">Read the story <span aria-hidden="true">↗</span></span></div></a></article>`).join('');
const index = page({title:'Inside Wand',description:'How we build Wand, what we learn, and how it works.',path:'/blog/',image:posts[0]?.image || '/blog-assets/wand-mark.png',structured:{'@context':'https://schema.org','@type':'Blog',name:'Wand Blog',url:origin+'/blog/',blogPost:posts.map(post=>({'@type':'BlogPosting',headline:post.title,url:origin+post.path,datePublished:post.date}))}},`<main id="main" class="blog-index"><div class="blog-intro"><p class="post-kicker">The Wand blog</p><h1>Inside Wand.</h1><p>How it works. What we’re learning.</p></div><div class="posts">${cards}</div><p class="feed-note">Follow new posts with <a href="/blog/feed.xml">RSS ↗</a></p></main>`);
await mkdir(new URL('blog/',output),{recursive:true});
await writeFile(new URL('blog/index.html',output),index);
const rss = `<?xml version="1.0" encoding="UTF-8"?><rss version="2.0" xmlns:atom="http://www.w3.org/2005/Atom"><channel><title>Wand Blog</title><link>${origin}/blog/</link><description>How we build Wand, what we learn, and how it works.</description><language>en</language><atom:link href="${origin}/blog/feed.xml" rel="self" type="application/rss+xml"/>${posts.map(post=>`<item><title>${escape(post.title)}</title><link>${origin}${post.path}</link><guid isPermaLink="true">${origin}${post.path}</guid><description>${escape(post.description)}</description><pubDate>${new Date(post.date+'T12:00:00Z').toUTCString()}</pubDate></item>`).join('')}</channel></rss>\n`;
await writeFile(new URL('blog/feed.xml',output),rss);
// Preserve the website's other routes; the catalog owns only blog sitemap entries.
const sitemapPath = new URL('sitemap.xml',output);
const sitemap = (await readFile(sitemapPath,'utf8')).replace(/<url>\s*<loc>https:\/\/getwand\.app\/blog\/[^<]*<\/loc>[\s\S]*?<\/url>/g,'');
const blogUrls = ['/blog/',...posts.map(post=>post.path)].map(path=>`<url><loc>${origin}${path}</loc></url>`).join('');
await writeFile(sitemapPath,sitemap.replace('</urlset>',`${blogUrls}</urlset>`));
console.log(`Built ${posts.length} blog post${posts.length === 1 ? '' : 's'}, index, RSS and sitemap.`);
