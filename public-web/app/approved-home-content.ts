/** Explicitly illustrative homepage examples, never live marketplace facts. */
export const stories = [
  {tag:'ILLUSTRATIVE REQUEST',title:['An unlocked iPhone.','A useful little upgrade.'],description:'iPhone 14 Pro, good condition. East Austin. Budget: $360–$430.',caption:'LET’S SEE WHAT’S OUT THERE ↗'},
  {tag:'ILLUSTRATIVE OFFERS',title:['Two possibilities.','One fresh perspective.'],description:'Offer A: $395, available tonight. Offer B: $420, includes a case. Compare before selecting.',caption:'YOUR OPTIONS, YOUR CHOICE ↗'},
  {tag:'ILLUSTRATIVE CONVERSATION',title:['“Could we meet','this weekend?”'],description:'Agree on the details with your chosen seller. Meet, inspect and pay for the item offline.',caption:'FROM AN ASK TO A CONNECTION ↗'},
] as const;
export const audiences = {
 buyer:[
  {title:'Start with what matters.',description:'A particular product, a useful service, a budget or an idea. Your request sets the direction.'},
  {title:'Make room for options.',description:'Compare offers and talk with sellers before choosing the right fit.'},
  {title:'Take it into the real world.',description:'Agree on your meeting, inspect the item and pay the seller directly offline.'},
 ],
 seller:[
  {title:'Meet a clearer starting point.',description:'Find buyer requests that describe what people actually need.'},
  {title:'Bring your offer to the table.',description:'Share the relevant details, discuss your proposal and make a useful connection.'},
  {title:'Keep the exchange personal.',description:'Coordinate with your buyer and settle item payment directly, offline. Platform fees remain separate.'},
 ],
} as const;
