'use client';
import {useState} from 'react';
import PaygoPaymentSetup from './PaygoPaymentSetup';
import BillingDialog from './BillingDialog';
import {standardWalletAmount} from './funding-amount';
import type {StandardRate} from './SellerBillingOverview';
type Option={id:string;amount_minor:number;initial_fee_minor:number;winning_total_minor:number};
export default function CreditFundingDialog({open,onClose,options,busy,allowed,onChoose,onCustom,preview,standardEnabled,standard,onManage,initialMethod='wallet'}:{open:boolean;onClose:()=>void;options:Option[];busy:boolean;allowed:boolean;onChoose:(id:string)=>void;onCustom:(amount:number)=>void;preview:boolean;standardEnabled:boolean;standard?:StandardRate;onManage?:()=>void;initialMethod?:'wallet'|'card'}){
 const [chosenMethod,setMethod]=useState<'wallet'|'card'|null>(null),[amount,setAmount]=useState(''),[error,setError]=useState('');
 const method=chosenMethod??initialMethod;
 return <BillingDialog open={open} onClose={onClose} busy={busy} eyebrow="Your Hocalist wallet" title="Add credits">
  <p className="credit-funding-intro">Choose a discounted wallet deposit or use the standard rates. Adding credits does not charge a targeting fee.</p>
  {!allowed&&<p className="billing-message info">Your billing account needs review before you can add credits.</p>}
  <div className="credit-funding-packs">{options.map(option=><article key={option.id} className="credit-funding-pack">
   <h3>{(option.amount_minor/100).toFixed(option.amount_minor%100?2:0)} HC</h3><p>Wallet deposit · ${(option.amount_minor/100).toFixed(2)}</p>
   <dl><div><dt>Initial fee</dt><dd>{(option.initial_fee_minor/100).toFixed(2)} HC</dd></div><div><dt>Winning total</dt><dd>{(option.winning_total_minor/100).toFixed(2)} HC</dd></div></dl>
   <button className="button primary" type="button" disabled={busy||!allowed} onClick={()=>onChoose(option.id)}>Add {(option.amount_minor/100).toFixed(option.amount_minor%100?2:0)} HC</button>
  </article>)}</div>
  <section className="credit-standard-choice"><h3>Standard rates</h3><p>Top up with less than 20 HC, or save a card for pay as you go.</p>
   {standard?<dl className="credit-standard-rates"><div><dt>Initial fee</dt><dd>{(standard.initial_minor/100).toFixed(2)} HC</dd></div><div><dt>Winning total</dt><dd>{(standard.winning_minor/100).toFixed(2)} HC</dd></div></dl>:<p className="billing-message info">Your standard rates are unavailable. Please try again before choosing this option.</p>}
   <div className="credit-funding-method" role="group" aria-label="Standard funding method"><button type="button" aria-pressed={method==='wallet'} onClick={()=>setMethod('wallet')}>Wallet amount</button><button type="button" aria-pressed={method==='card'} onClick={()=>setMethod('card')}>Card</button></div>
   {method==='wallet'?<form onSubmit={event=>{event.preventDefault();const minor=standardWalletAmount(amount);if(minor===null){setError('Choose an amount from 0.50 HC to 19.99 HC, with up to two decimal places.');return;}setError('');onCustom(minor);}}>
    <label htmlFor="standard-wallet-amount">Wallet amount (HC)</label><div className="credit-amount-input"><span aria-hidden="true">HC</span><input id="standard-wallet-amount" inputMode="decimal" value={amount} onChange={event=>setAmount(event.target.value)} placeholder="Enter an amount" maxLength={8}/></div>
    <p className="billing-note">1 HC = $1. Standard targeting rates apply. Smaller top-ups can build your balance toward the amount needed for a deal.</p>
    {error&&<p role="alert" className="billing-message error">{error}</p>}
    {!standardEnabled&&!preview&&<p className="billing-message info">Custom wallet deposits are not available yet.</p>}
    <button className="button primary" disabled={busy||!allowed||!standard||(!standardEnabled&&!preview)} type="submit">Continue to secure payment</button>
   </form>:<PaygoPaymentSetup preview={preview} setupOnly onManage={onManage}/>}
  </section>
 </BillingDialog>;
}
