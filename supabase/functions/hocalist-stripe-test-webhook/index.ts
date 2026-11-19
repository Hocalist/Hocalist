import {createHandler,type Receipt} from './handler.ts';
import {billingEnvironment} from '../_shared/stripe-test-project.ts';

const url = Deno.env.get('SUPABASE_URL') ?? '';
const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
const configuration = billingEnvironment(url, Deno.env.get('HOCALIST_SELLER_TEST_ACCOUNT_ID'));
const signingSecret = Deno.env.get(configuration.webhookKey) ?? '';

async function persist(name:string,receipt:Receipt) {
  if (!serviceKey) throw new Error('configuration unavailable');
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
Deno.serve(createHandler({signingSecret,expectedAccount:configuration.account,
 receive:receipt=>persist('receive_stripe_test_event',receipt),
 ...(Deno.env.get('HOCALIST_PAYGO_TEST_ENABLED')==='true'?{receivePaygo:(receipt:Receipt)=>persist('receive_stripe_test_paygo_event',receipt)}:{}),
}));
