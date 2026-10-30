import {backend} from '../_shared/stripe-test-billing.ts';
import {createPaygoRecoveryHandler} from './handler.ts';
Deno.serve(createPaygoRecoveryHandler(backend(),{
 enabled:Deno.env.get('HOCALIST_PAYGO_TEST_ENABLED')==='true',
 publishableKey:Deno.env.get('HOCALIST_STRIPE_TEST_PUBLISHABLE_KEY')??'',
}));
