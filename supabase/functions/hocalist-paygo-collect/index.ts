import {backend} from '../_shared/stripe-test-billing.ts';
import {createPaygoCollectionHandler} from './handler.ts';
const secret=Deno.env.get('HOCALIST_PAYGO_WORKER_SECRET')??'';
Deno.serve(createPaygoCollectionHandler(backend(),{
 enabled:Deno.env.get('HOCALIST_PAYGO_TEST_ENABLED')==='true',
 authorise:request=>secret.length>=32&&request.headers.get('Authorization')===`Bearer ${secret}`,
}));
