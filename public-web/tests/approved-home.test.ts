import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createElement } from 'react';
import { renderToStaticMarkup } from 'react-dom/server';
import ApprovedHome from '../app/ApprovedHome';

test('the public homepage renders the approved illustrated composition', () => {
  const page = renderToStaticMarkup(createElement(ApprovedHome));
  assert.match(page, /Less searching\.<br\/>More <em>finding\.<\/em>/);
  assert.match(page, /id="photo-frame"/);
  assert.match(page, /clip-path="url\(#photo-frame\)"/);
  assert.match(page, /images\.pexels\.com\/photos\/4881162/);
  assert.match(page, /\/brand\/hocalist-concept-wordmark\.png/);
  assert.match(page, /ILLUSTRATIVE REQUEST/);
  assert.match(page, /aria-live="polite"/);
  assert.doesNotMatch(page, /class="request-field|marketplace-hero|Local design concept/);
});

test('approved homepage preserves real route destinations and accessible controls', () => {
  const page = renderToStaticMarkup(createElement(ApprovedHome));
  for (const destination of ['/billing','/download','/pricing','/support','/how-it-works','/privacy','/terms','/refund-cancellation','/safety']) {
    assert.ok(page.includes(`href="${destination}"`), `Missing route ${destination}`);
  }
  for (const section of ['how','requests','sellers','discover','plans','safety']) {
    assert.ok(page.includes(`id="${section}"`), `Missing approved section ${section}`);
  }
  assert.match(page, /aria-label="Primary navigation"/);
  assert.match(page, /aria-controls="home-mobile-navigation"/);
  assert.match(page, /aria-pressed="false">Pause motion/);
  assert.match(page, /<main id="home-content">/);
});
