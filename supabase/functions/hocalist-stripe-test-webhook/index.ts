import {createHandler,type Receipt} from './handler.ts';

const url = Deno.env.get('SUPABASE_URL') ?? '';
const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
const signingSecret = Deno.env.get('HOCALIST_STRIPE_TEST_WEBHOOK_SECRET') ?? '';
const expectedProject = 'https://icqwbzswokoulatomgql.supabase.co';

async function persist(name:string,receipt:Receipt) {
  if (url !== expectedProject || !serviceKey) throw new Error('configuration unavailable');
  const response = await fetch(`${url}/rest/v1/rpc/${name}`, {
    method:'POST', headers:{
      apikey:serviceKey, Authorization:`Bearer ${serviceKey}`,
      'Content-Type':'application/json', 'Content-Profile':'hocalist',
    }, body:JSON.stringify(receipt), signal:AbortSignal.timeout(10000),
  });
  if (!response.ok) throw new Error('receipt unavailable');
  const inserted = await response.json();
  if (typeof inserted !== 'boolean') throw new Error('invalid receipt response');
}
Deno.serve(createHandler({signingSecret,
 receive:receipt=>persist('receive_stripe_test_event',receipt),
 ...(Deno.env.get('HOCALIST_PAYGO_TEST_ENABLED')==='true'?{receivePaygo:(receipt:Receipt)=>persist('receive_stripe_test_paygo_event',receipt)}:{}),
}));
