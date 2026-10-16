import {createHandler} from './handler.ts';

const url = Deno.env.get('SUPABASE_URL') ?? '';
const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
const signingSecret = Deno.env.get('HOCALIST_STRIPE_TEST_WEBHOOK_SECRET') ?? '';
const expectedProject = 'https://icqwbzswokoulatomgql.supabase.co';

Deno.serve(createHandler({signingSecret, receive: async (receipt) => {
  if (url !== expectedProject || !serviceKey) throw new Error('configuration unavailable');
  const response = await fetch(`${url}/rest/v1/rpc/receive_stripe_test_event`, {
    method:'POST', headers:{
      apikey:serviceKey, Authorization:`Bearer ${serviceKey}`,
      'Content-Type':'application/json', 'Content-Profile':'hocalist',
    }, body:JSON.stringify(receipt), signal:AbortSignal.timeout(10000),
  });
  if (!response.ok) throw new Error('receipt unavailable');
  const inserted = await response.json();
  if (typeof inserted !== 'boolean') throw new Error('invalid receipt response');
}}));
