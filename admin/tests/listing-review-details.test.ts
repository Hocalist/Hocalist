import {test} from 'node:test';
import assert from 'node:assert/strict';
import {createElement} from 'react';
import {renderToStaticMarkup} from 'react-dom/server';
import {ListingReviewDetails} from '../app/moderation/listing-review-details';
import type {AdminListing} from '../app/lib/admin-data';
test('review displays submitted content and every attached photo',()=>{
 const listing={id:'listing',description:'<script>not markup</script>',service_area:'Chicago',availability:'Weekdays',image_media_ids:['one','two']} as AdminListing;
 const html=renderToStaticMarkup(createElement(ListingReviewDetails,{listing}));
 assert.match(html,/&lt;script&gt;not markup&lt;\/script&gt;/);assert.match(html,/Chicago/);assert.match(html,/Weekdays/);
 assert.match(html,/Loading photo 1/);assert.match(html,/Loading photo 2/);
});
