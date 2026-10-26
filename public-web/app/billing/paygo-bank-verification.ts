type StripeClient={confirmCardPayment:(secret:string)=>Promise<{error?:{message?:string}}>};
type StripeFactory=(key:string)=>StripeClient;
let loading:Promise<StripeFactory>|null=null;
export async function verifyPaygoBankPayment(key:string,secret:string):Promise<void>{
 if(!/^pk_test_[A-Za-z0-9]+$/.test(key)||!/^pi_[A-Za-z0-9]+_secret_[A-Za-z0-9]+$/.test(secret))throw new Error('Payment verification is unavailable.');
 const factory=await load();const result=await factory(key).confirmCardPayment(secret);
 if(result.error)throw new Error('Your bank could not verify this payment. Please try again or save another card.');
}
function load():Promise<StripeFactory>{
 const current=(window as unknown as {Stripe?:StripeFactory}).Stripe;if(current)return Promise.resolve(current);
 if(loading)return loading;
 loading=new Promise<StripeFactory>((resolve,reject)=>{
  const script=document.createElement('script');script.src='https://js.stripe.com/v3/';script.async=true;
  const timeout=window.setTimeout(()=>{script.remove();loading=null;reject(new Error('Secure payment verification could not load. Please try again.'));},15000);
  script.onload=()=>{window.clearTimeout(timeout);const stripe=(window as unknown as {Stripe?:StripeFactory}).Stripe;if(stripe)resolve(stripe);else{loading=null;reject(new Error('Secure payment verification is unavailable.'));}};
  script.onerror=()=>{window.clearTimeout(timeout);script.remove();loading=null;reject(new Error('Secure payment verification could not load. Please try again.'));};
  document.head.appendChild(script);
 });return loading;
}
