import {uuidHint} from '../lib/website-rules';

export function paygoReturn(search:URLSearchParams) {
  return {setupId:uuidHint(search.get('paygo_setup')),cancelled:search.get('paygo_cancelled')==='1'};
}
